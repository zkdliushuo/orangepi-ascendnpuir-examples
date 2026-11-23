#!/usr/bin/env bash
# 使用现有 1.2.0 ELF 导出 vecadd 的原生分阶段 IR；不重编译编译器、不运行 NPU。
# 用法：./examples/vecadd/tools/export_ir_310b1.sh [输出目录]
# 默认更新 examples/vecadd/output/ 中已知的生成文件；原始日志仅保存在 out/。
set -euo pipefail
tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tool_dir/../../.." && pwd)"
source "$repo/scripts/00_env.sh"
[[ $# -le 1 ]] || { echo "usage: $0 [output-directory]" >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] || {
  echo "requires Linux aarch64: the debugger reads the AArch64 x0 argument register" >&2
  exit 1
}
for command in gdb python3 install cp ln mktemp realpath; do
  command -v "$command" >/dev/null || { echo "missing command: $command (Ubuntu: install gdb/python3/coreutils)" >&2; exit 1; }
done
for required in "$FRONTEND_BIN" "$HIVMC_BIN" "$CCEC_DIR/bisheng"; do
  [[ -x "$required" ]] || { echo "missing executable: $required" >&2; exit 1; }
done
for required in "$DEVICE_BITCODE" "$HOST_BITCODE"; do
  [[ -r "$required" ]] || {
    echo "missing local CANN template: $required; run scripts/05_capture_a5_templates.sh first" >&2
    exit 1
  }
done
for required in "$tool_dir/export_ir_310b1.py" "$tool_dir/export_ir_310b1.gdb" \
  "$REPO_ROOT/examples/vecadd/tools/patch_310b1_annotation.py"; do
  [[ -r "$required" ]] || { echo "missing exporter helper: $required" >&2; exit 1; }
done
input="$REPO_ROOT/examples/vecadd/mlir/add_310b1.mlir"
[[ -r "$input" ]] || { echo "missing example input: $input" >&2; exit 1; }

destination="${1:-$REPO_ROOT/examples/vecadd/output}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
mkdir -p "$OUT_DIR"
scratch="$(mktemp -d "$OUT_DIR/ir-export.XXXXXXXX")"
stage=initialization
trap 'status=$?; if [[ "$status" != 0 ]]; then echo "IR export failed at: $stage; raw logs retained in $scratch" >&2; fi' EXIT
publish="$scratch/publish"
fakebin="$scratch/fakebin"
mkdir -p "$publish" "$fakebin"

# 独立的工具目录，不读取或改写 out/vecadd/fakebin。
for executable in "$CCEC_DIR"/*; do
  [[ -e "$executable" ]] || continue
  name="$(basename "$executable")"
  [[ "$name" != bisheng && "$name" != hivmc-a5 ]] || continue
  ln -s "$executable" "$fakebin/$name"
done
ln -s "$(realpath "$HIVMC_BIN")" "$fakebin/hivmc-a5"
# 这里只保存 .ll；既不复制也不发布 CANN 模板 bitcode。
cat >"$fakebin/bisheng" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
: "${CAPTURE_DIR:?}" "${REAL_BISHENG:?}"
mkdir -p "$CAPTURE_DIR"
index=0
for argument in "$@"; do
  if [[ "$argument" == *.ll && -f "$argument" ]]; then
    index=$((index + 1))
    cp "$argument" "$CAPTURE_DIR/module-$$-$index.ll"
  fi
done
exec "$REAL_BISHENG" "$@"
SHIM
chmod 755 "$fakebin/bisheng"

"$FRONTEND_BIN" --version >"$scratch/frontend-version.txt"
"$HIVMC_BIN" --version >"$scratch/backend-version.txt"
grep -q 'bishengir-compile 1.2.0' "$scratch/frontend-version.txt" || { echo "requires frontend 1.2.0" >&2; exit 1; }
grep -q 'hivmc 1.2.0' "$scratch/backend-version.txt" || { echo "requires backend 1.2.0" >&2; exit 1; }
cp "$input" "$publish/00-input.mlir"

common_args=(
  --target=Ascend310B1 -enable-hfusion-compile=true -block-dim=1
  "--link-aicore-bitcode=$DEVICE_BITCODE"
  --enable-tuning-mode --mlir-disable-threading
)
stages=(
  '10-hfusion.mlir|convert-linalg-to-hfusion/module/0'
  '20-hfusion-scheduled.mlir|hfusion-auto-schedule/module/0'
  '30-hivm-tensor.mlir|convert-to-hivm-op/module/0'
  '40-hivm-buffer.mlir|one-shot-bufferize/module/0'
  '50-hivm-memory-planned.mlir|hivm-plan-memory/module/2'
  '60-hivm-synchronized.mlir|hivm-graph-sync-solver/add/0'
)
for specification in "${stages[@]}"; do
  filename="${specification%%|*}"
  pass_id="${specification#*|}"
  stage="native snapshot $pass_id"
  run="$scratch/${filename%.mlir}"
  mkdir -p "$run/temps" "$run/capture"
  missing="$run/intentionally-missing-inject.mlir"
  echo "=== $filename: after $pass_id ==="
  # 缺失文件使 inject 在任何函数替换发生前调用 emitError；GDB 在精确入口
  # 调用已有 Operation::dump。随后让后端有意失败，重发编译器收集的诊断。
  # 此处的 exit=1 是导出机制的一部分，绝不能计作正常编译通过。
  if CAPTURE_DIR="$run/capture" REAL_BISHENG="$CCEC_DIR/bisheng" \
    BISHENG_INSTALL_PATH="$fakebin" PATH="$fakebin:$ASCEND_HOME_PATH/bin:$CCEC_DIR:$PATH" \
    gdb -nx --batch --return-child-result -x "$tool_dir/export_ir_310b1.gdb" --args \
      "$FRONTEND_BIN" "${common_args[@]}" \
      "--hivmc-args=--link-host-bitcode=$HOST_BITCODE --intentionally-stop-ir-dump" \
      "--inject-ir-after=$pass_id@$missing" "--save-temps=$run/temps" \
      "$input" -o "$run/pipeline.o" >"$run/gdb.log" 2>&1; then
    status=0
  else
    status=$?
  fi
  python3 "$tool_dir/export_ir_310b1.py" extract \
    --log "$run/gdb.log" --output "$publish/$filename" \
    --pass-id "$pass_id" --missing "$missing" --exit-status "$status"
done

stage="independent successful compilation"
normal="$scratch/normal"
mkdir -p "$normal/temps" "$normal/capture"
echo "=== independent normal compilation (must exit 0) ==="
CAPTURE_DIR="$normal/capture" REAL_BISHENG="$CCEC_DIR/bisheng" \
BISHENG_INSTALL_PATH="$fakebin" PATH="$fakebin:$ASCEND_HOME_PATH/bin:$CCEC_DIR:$PATH" \
  "$FRONTEND_BIN" "${common_args[@]}" \
    "--hivmc-args=--link-host-bitcode=$HOST_BITCODE" \
    "--save-temps=$normal/temps" "$input" -o "$normal/pipeline.o" \
    >"$normal/compile.log" 2>&1
[[ -s "$normal/pipeline.o" && -s "$normal/temps/module.hivm.opt.mlir" ]] || {
  echo "normal compilation did not produce its object/final frontend MLIR" >&2
  exit 1
}
cp "$normal/temps/module.hivm.opt.mlir" "$publish/70-final-frontend.mlir"
device_ir=""
count=0
for candidate in "$normal/capture"/module-*.ll; do
  [[ -f "$candidate" ]] || continue
  if grep -qE '^define .*@add\(' "$candidate"; then
    device_ir="$candidate"
    count=$((count + 1))
  fi
done
[[ "$count" == 1 ]] || { echo "expected exactly one captured LLVM module defining @add, found $count" >&2; exit 1; }
cp "$device_ir" "$publish/80-device.ll"
python3 "$REPO_ROOT/examples/vecadd/tools/patch_310b1_annotation.py" \
  "$publish/80-device.ll" "$publish/81-device-annotated.ll" --symbol add

stage="sanitize and publish reproducibility evidence"
python3 "$tool_dir/export_ir_310b1.py" publish \
  --scratch "$scratch" --destination "$destination" --repo "$REPO_ROOT" \
  --frontend "$FRONTEND_BIN" --backend "$HIVMC_BIN" --input "$input" \
  --cann "$ASCEND_HOME_PATH" --driver "$ASCEND_DRIVER_DIR" \
  --device-bitcode "$DEVICE_BITCODE" --host-bitcode "$HOST_BITCODE"
stage=complete
echo "Exported: $destination"
echo "Raw logs retained locally: $scratch"
echo "Six diagnostic snapshots intentionally exited 1; the independent normal compilation exited 0."
echo "This exporter does not launch an NPU program or redistribute CANN bitcode."
