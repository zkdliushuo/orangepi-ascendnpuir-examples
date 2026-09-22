#!/usr/bin/env bash
# 示例的端到端验证。
#
#   ./scripts/99_verify.sh                     # 使用已经构建好的工具链
#   BUILD_TOOLCHAIN=1 ./scripts/99_verify.sh   # 先构建工具链再验证
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

if [[ "${BUILD_TOOLCHAIN:-0}" == "1" ]]; then
  bash "$REPO_ROOT/scripts/10_build_frontend.sh"
  bash "$REPO_ROOT/scripts/11_build_hivmc.sh"
fi

bash "$REPO_ROOT/scripts/05_capture_a5_templates.sh"
bash "$REPO_ROOT/scripts/20_build_vecadd.sh"
bash "$REPO_ROOT/scripts/21_run_vecadd.sh"
bash "$REPO_ROOT/scripts/22_llvm_ir_launcher.sh"
