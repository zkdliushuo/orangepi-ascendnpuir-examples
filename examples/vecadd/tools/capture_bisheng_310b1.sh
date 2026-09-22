#!/usr/bin/env bash
set -euo pipefail

# bisheng 的临时替身：先保存当前的设备 LLVM IR 与 M300 支持 bitcode，
# 再把调用转发给真正的编译器。
: "${CAPTURE_DIR:?CAPTURE_DIR is required}"
: "${REAL_BISHENG:?REAL_BISHENG is required}"

mkdir -p "$CAPTURE_DIR"

# 记录每次设备编译器调用：既让流水线透明，也是抓取不完整时的第一排查点。
{
  echo "=== $(date +%T) bisheng $*"
} >>"$CAPTURE_DIR/calls.log"

previous=""
index=0
for argument in "$@"; do
  if [[ "$previous" == "-cce-link-aicore-ll-module" && -f "$argument" ]]; then
    cp -f "$argument" "$CAPTURE_DIR/m300-support.bc"
  fi

  case "$argument" in
    *.ll)
      if [[ -f "$argument" ]]; then
        index=$((index + 1))
        # 用 $$（进程号）区分不同次调用的抓取结果：该工具会为设备模块和
        # host 模块各调用一次，而两者都是 .ll 文件。
        cp -f "$argument" "$CAPTURE_DIR/module-$$-$index.ll"
      fi
      ;;
    *.bc)
      if [[ -f "$argument" ]]; then
        index=$((index + 1))
        cp -f "$argument" "$CAPTURE_DIR/bitcode-$$-$index.bc"
      fi
      ;;
  esac
  previous="$argument"
done

exec "$REAL_BISHENG" "$@"
