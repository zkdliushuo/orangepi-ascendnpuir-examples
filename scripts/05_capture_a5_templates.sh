#!/usr/bin/env bash
# 抽取设备编译器需要的 A5（Ascend310B / dav-m300）模板 bitcode。
#
# CANN toolkit 把这些模板放在自带的 hivmc-a5 内部，并没有安装成普通文件，
# 因此我们用一次"捕获 shim"替换 bisheng 运行 toolkit 编译器，把它调用
# bisheng 时传入的 `-cce-link-aicore-ll-module <file>.bc` 参数保存下来。
#
# 输出（相对工作区）：
#   out/a5-templates/host.bc            - 直接从 toolkit 复制
#   out/a5-templates/regbaseM300.bc     - 从 toolkit 流水线中捕获
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

require_file "$ASCEND_HOME_PATH/bin/bishengir-compile-a5" \
  "install CANN 9.0.0 into <workspace>/deps/cann-9.0.0 or export ASCEND_HOME_PATH"
ensure_dir "$TEMPLATE_DIR"

cp -f "$ASCEND_HOME_PATH/tools/bishengir/lib/host.bc" "$HOST_BITCODE"
echo "captured host bitcode        -> $(rel_path "$HOST_BITCODE")"

capture_root="$(mktemp -d "$OUT_DIR/capture-templates.XXXXXX")"
trap 'rm -rf -- "$capture_root"' EXIT
capture_bin="$capture_root/bin"
capture_out="$capture_root/out"
mkdir -p "$capture_bin" "$capture_out"

# 一个私有的工具目录：行为与 toolkit 一致，只是把 bisheng 换成捕获 shim。
for tool in "$CCEC_DIR"/*; do
  [[ "$(basename "$tool")" == "bisheng" ]] && continue
  ln -sf "$tool" "$capture_bin/$(basename "$tool")"
done
install -m 755 "$REPO_ROOT/examples/vecadd/tools/capture_bisheng_310b1.sh" \
  "$capture_bin/bisheng"

set +e
CAPTURE_DIR="$capture_out" \
REAL_BISHENG="$CCEC_DIR/bisheng" \
BISHENG_INSTALL_PATH="$capture_bin" \
PATH="$capture_bin:$ASCEND_HOME_PATH/bin:$CCEC_DIR:$PATH" \
"$ASCEND_HOME_PATH/bin/bishengir-compile-a5" \
  --target=Ascend310B1 \
  -enable-hfusion-compile=true \
  -block-dim=1 \
  "$REPO_ROOT/examples/vecadd/mlir/add_310b1.mlir" \
  -o "$capture_root/pipeline.o" \
  >"$capture_root/pipeline.log" 2>&1
pipeline_status=$?
set -e

captured_bc="$(find "$capture_out" -maxdepth 1 -name 'm300-support.bc' | head -1)"
if [[ -z "$captured_bc" ]]; then
  echo "could not capture the device template bitcode (status=$pipeline_status)" >&2
  tail -30 "$capture_root/pipeline.log" >&2 || true
  exit 1
fi
cp -f "$captured_bc" "$DEVICE_BITCODE"
echo "captured device bitcode      -> $(rel_path "$DEVICE_BITCODE")"

captured_ir="$(find "$capture_out" -maxdepth 1 -name 'device-*.ll' | sort | tail -1)"
if [[ -n "$captured_ir" ]]; then
  cp -f "$captured_ir" "$TEMPLATE_DIR/device-reference.ll"
  echo "captured reference device IR -> $(rel_path "$TEMPLATE_DIR/device-reference.ll")"
fi
