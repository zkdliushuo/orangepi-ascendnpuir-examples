#!/usr/bin/env bash
# 示例的 LLVM IR 部分。
#
# 1. launch_add.ll / direct_aclrt_launch.ll 是上游的 CPU 侧 IR 示例：
#    一份调用稳定的 C ABI shim，一份直接声明 ACL Runtime 接口的教学版本。
#    两者都会编译成 .o 以验证可用性。
# 2. launch_add_310b1.ll 是 Ascend310B1 的启动版本：在 IR 里调用 AscendC
#    运行时 ABI（RegisterAscendBinary / LaunchAscendKernel）。它与一个小的
#    C++ 驱动链接（驱动负责显存与结果校验），产物直接在板子上运行。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

example_dir="$REPO_ROOT/examples/vecadd"
build_dir="$OUT_DIR/vecadd"
kernel="$build_dir/kernel.o"
require_file "$kernel" "run scripts/20_build_vecadd.sh first"
mkdir -p "$build_dir"

bisheng="$ASCEND_HOME_PATH/tools/bisheng_compiler/bin/bisheng"
[[ -x "$bisheng" ]] || bisheng="$CCEC_DIR/bisheng"

echo "=== compile the CPU-side LLVM IR examples ==="
"$bisheng" -c "$example_dir/llvm/launch_add.ll" -o "$build_dir/launch_add.o"
"$bisheng" -c "$example_dir/llvm/direct_aclrt_launch.ll" \
  -o "$build_dir/direct_aclrt_launch.o"
echo "built out/vecadd/launch_add.o"
echo "built out/vecadd/direct_aclrt_launch.o"

echo "=== build the Ascend310B1 LLVM IR launcher (IR + C++ driver) ==="
"$bisheng" -c "$example_dir/llvm/launch_add_310b1.ll" \
  -o "$build_dir/launch_add_310b1.o"
"${CXX:-g++}" -O2 -std=c++17 \
  "$example_dir/src/llvm_launch_driver_310b1.cpp" \
  "$build_dir/launch_add_310b1.o" \
  -o "$build_dir/llvm_launch" \
  -I"$ASCEND_HOME_PATH/aarch64-linux/include" \
  -L"$ASCEND_HOME_PATH/lib64" \
  -L"$ASCEND_HOME_PATH/aarch64-linux/lib64" \
  -L"$ASCEND_DRIVER_DIR/lib64" \
  -Wl,-rpath-link,"$ASCEND_HOME_PATH/lib64" \
  -Wl,-rpath-link,"$ASCEND_HOME_PATH/aarch64-linux/lib64" \
  -Wl,-rpath-link,"$ASCEND_DRIVER_DIR/lib64" \
  "$ASCEND_HOME_PATH/aarch64-linux/lib64/libascendc_runtime.a" \
  -lruntime -lascendcl -lmmpa -lc_sec -lslog -lprofapi -ldl -lpthread
echo "built out/vecadd/llvm_launch"

echo "=== run the LLVM IR launcher ==="
if ! run_on_device ./out/vecadd/llvm_launch out/vecadd/kernel.o; then
  device_run_hint
  exit 1
fi
