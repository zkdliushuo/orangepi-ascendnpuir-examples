#!/usr/bin/env bash
# 在 Ascend310B1 开发板上运行 vecadd 内核。
#
# 若当前登录会话没有设备组（刚执行 usermod -aG HwHiAiUser 时，要到下次登录才
# 生效），可设置 ASCEND_SSH=localhost，通过一个全新的会话运行。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

runner="$OUT_DIR/vecadd/run_add"
kernel="$OUT_DIR/vecadd/kernel.o"
require_file "$runner" "run scripts/20_build_vecadd.sh first"
require_file "$kernel" "run scripts/20_build_vecadd.sh first"

if ! run_on_device ./out/vecadd/run_add out/vecadd/kernel.o; then
  device_run_hint
  exit 1
fi
