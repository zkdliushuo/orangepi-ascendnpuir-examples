#!/usr/bin/env bash
# 为 Ascend310B1 编译 vecadd 算子，并构建主机侧运行程序。
#
#   add_310b1.mlir  --(bishengir-compile + hivmc)-->  device LLVM IR
#                   --(+ kernel-entry metadata)----->  annotated IR
#                   --(ccec + ld.lld)--------------->  device ELF
#                   --(+ AscendC container)--------->  out/vecadd/kernel.o
#
# 产物使用的 ABI 就是 AscendC 运行时要求的那套，详见
# docs/02-vecadd-pipeline.md。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

require_file "$FRONTEND_BIN" "run scripts/10_build_frontend.sh (or set FRONTEND_BIN)"
require_file "$HIVMC_BIN" "run scripts/11_build_hivmc.sh (or set HIVMC_BIN)"
require_file "$DEVICE_BITCODE" "run scripts/05_capture_a5_templates.sh"
require_file "$HOST_BITCODE" "run scripts/05_capture_a5_templates.sh"

example_dir="$REPO_ROOT/examples/vecadd"
build_dir="$OUT_DIR/vecadd"
fakebin="$build_dir/fakebin"
capture_dir="$build_dir/capture"
mkdir -p "$build_dir" "$capture_dir"

# ---------------------------------------------------------------------------
# 私有工具目录：CANN 的设备工具、把本仓库的 hivmc 伪装成前端要找的
# `hivmc-a5`，以及一个捕获 shim 替换 bisheng，用于保存后端即将编译的
# 设备 LLVM IR。
# ---------------------------------------------------------------------------
mkdir -p "$fakebin"
for tool in "$CCEC_DIR"/*; do
  name="$(basename "$tool")"
  [[ "$name" == "bisheng" ]] && continue
  ln -sf "$tool" "$fakebin/$name"
done
ln -sf "$HIVMC_BIN" "$fakebin/hivmc-a5"
install -m 755 "$example_dir/tools/capture_bisheng_310b1.sh" "$fakebin/bisheng"

rel_mlir="${example_dir#"$REPO_ROOT"/}/mlir/add_310b1.mlir"
rel_build="${build_dir#"$REPO_ROOT"/}"

echo "=== lower $rel_mlir (front end + back end) ==="
CAPTURE_DIR="$capture_dir" \
REAL_BISHENG="$CCEC_DIR/bisheng" \
BISHENG_INSTALL_PATH="$fakebin" \
PATH="$fakebin:$ASCEND_HOME_PATH/bin:$CCEC_DIR:$PATH" \
"$FRONTEND_BIN" \
  --target=Ascend310B1 \
  -enable-hfusion-compile=true \
  -block-dim=1 \
  --link-aicore-bitcode="$DEVICE_BITCODE" \
  --hivmc-args=--link-host-bitcode="$HOST_BITCODE" \
  "$example_dir/mlir/add_310b1.mlir" \
  -o "$build_dir/pipeline.o" \
  >"$build_dir/pipeline.log" 2>&1

# shim 会记录交给设备编译器的每个 .ll；内核是其中*定义*了 @add 的那个
# （host 模块只是调用它）。
device_ir=""
for candidate in "$capture_dir"/module-*.ll; do
  [[ -f "$candidate" ]] || continue
  if grep -qE '^define .*@add\(' "$candidate"; then
    device_ir="$candidate"
  fi
done
if [[ -z "$device_ir" ]]; then
  echo "no device IR captured; see $build_dir/capture and $build_dir/pipeline.log" >&2
  exit 1
fi
echo "=== device IR: ${device_ir#"$REPO_ROOT"/} ==="

# ---------------------------------------------------------------------------
# 内核入口元数据：没有它 ccec 不会生成参数前导，内核读到的会是垃圾地址。
# ---------------------------------------------------------------------------
python3 "$example_dir/tools/patch_310b1_annotation.py" \
  "$device_ir" "$build_dir/kernel.annotated.ll" --symbol add

echo "=== compile device code (ccec, dav-m300) ==="
"$CCEC_DIR/ccec" \
  --cce-aicore-arch=dav-m300 \
  --cce-aicore-only -O2 \
  -Wno-override-module \
  -cce-bitcode-is-aicore \
  -cce-link-aicore-ll-module "$DEVICE_BITCODE" \
  -mllvm --cce-vf-auto-sync=global \
  -mllvm -cce-aicore-dcci-insert-for-scalar=false \
  --cce-aicore-input-parameter-size=1536 \
  -o "$build_dir/kernel.reloc.o" \
  "$build_dir/kernel.annotated.ll"

"$CCEC_DIR/ld.lld" -m aicorelinux -Ttext=0 \
  "$build_dir/kernel.reloc.o" \
  -static -o "$build_dir/kernel.linked.o"

# ---------------------------------------------------------------------------
# AscendC 容器格式：入口符号为 <name>_<tilingkey> 且 st_size 非 0，
# <name>_<tilingkey>__ 位于 __CCE_KernelArgSize 节，参数区大小 24 字节。
# ---------------------------------------------------------------------------
python3 - "$build_dir/argsz.bin" <<'PY'
import struct
import sys

with open(sys.argv[1], "wb") as output:
    output.write(struct.pack("<I", 24))  # 三个设备指针
PY

"$CCEC_DIR/llvm-objcopy" \
  --add-section __CCE_KernelArgSize="$build_dir/argsz.bin" \
  --redefine-sym add=add_0 \
  --add-symbol add_0__=__CCE_KernelArgSize:0,object,weak \
  "$build_dir/kernel.linked.o" \
  "$build_dir/kernel.o"

# ---------------------------------------------------------------------------
# 主机侧：一个普通的 C++ 运行程序，负责注册内核 ELF 并启动它
# ---------------------------------------------------------------------------
echo "=== build host runner ==="
"${CXX:-g++}" -O2 -std=c++17 \
  "$example_dir/src/vecadd_runner_310b1.cpp" \
  -o "$build_dir/run_add" \
  -I"$ASCEND_HOME_PATH/aarch64-linux/include" \
  -L"$ASCEND_HOME_PATH/lib64" \
  -L"$ASCEND_HOME_PATH/aarch64-linux/lib64" \
  -L"$ASCEND_DRIVER_DIR/lib64" \
  -Wl,-rpath-link,"$ASCEND_HOME_PATH/lib64" \
  -Wl,-rpath-link,"$ASCEND_HOME_PATH/aarch64-linux/lib64" \
  -Wl,-rpath-link,"$ASCEND_DRIVER_DIR/lib64" \
  "$ASCEND_HOME_PATH/aarch64-linux/lib64/libascendc_runtime.a" \
  -lruntime -lascendcl -lmmpa -lc_sec -lslog -lprofapi -ldl -lpthread

echo "built $rel_build/kernel.o"
echo "built $rel_build/run_add"
