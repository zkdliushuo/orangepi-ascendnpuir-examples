#!/usr/bin/env bash
# 本仓库所有脚本共用的环境定义。
#
#   source "$(dirname "$0")/00_env.sh"
#
# 这里不需要任何绝对路径：目录布局由本仓库在工作区中的位置推导而来：
#
#   <workspace>/
#     deps/
#       AscendNPU-IR          上游克隆（master）            -> hivmc
#       AscendNPU-IR-a5       分支 dev/regbase 的 worktree  -> bishengir-compile
#       cann-9.0.0            CANN 9.0.0 toolkit 安装目录
#       build-ascendnpu-ir    共享的 LLVM/MLIR + bishengir 构建目录
#     ascend310b1-vecadd/     本仓库
#
# 所有变量都可以从外部覆盖：直接 export，或在本文件旁边放一个
# config.local.sh（已被 git 忽略）。

set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$_script_dir/.." && pwd)"

# 本地覆盖值（可选）。
if [[ -f "$_script_dir/config.local.sh" ]]; then
  # shellcheck disable=SC1091
  source "$_script_dir/config.local.sh"
fi

WORK_ROOT="${WORK_ROOT:-$(dirname "$REPO_ROOT")}"
DEPS_DIR="${DEPS_DIR:-$WORK_ROOT/deps}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/out}"

# --- 源码 --------------------------------------------------------------------
ASCENDNPU_IR_DIR="${ASCENDNPU_IR_DIR:-$DEPS_DIR/AscendNPU-IR}"
ASCENDNPU_IR_A5_DIR="${ASCENDNPU_IR_A5_DIR:-$DEPS_DIR/AscendNPU-IR-a5}"
ASCENDNPU_IR_BUILD_DIR="${ASCENDNPU_IR_BUILD_DIR:-$DEPS_DIR/build-ascendnpu-ir}"
ASCENDNPU_IR_URL="${ASCENDNPU_IR_URL:-https://github.com/Ascend/AscendNPU-IR.git}"

# --- CANN toolkit ------------------------------------------------------------
# 优先使用已存在的 ASCEND_HOME_PATH，但必须确认它真的是一个 toolkit
# （指向已卸载版本的失效取值不能生效）。
_looks_like_cann() {
  [[ -n "${1:-}" && -x "$1/bin/bishengir-compile-a5" ]]
}
if ! _looks_like_cann "${ASCEND_HOME_PATH:-}"; then
  if _looks_like_cann "$DEPS_DIR/cann-9.0.0"; then
    ASCEND_HOME_PATH="$DEPS_DIR/cann-9.0.0"
  else
    ASCEND_HOME_PATH="${ASCEND_HOME_PATH:-$DEPS_DIR/cann-9.0.0}"
  fi
fi
export ASCEND_HOME_PATH
ASCEND_OPP_PATH="${ASCEND_OPP_PATH:-$ASCEND_HOME_PATH/opp}"
export ASCEND_OPP_PATH
# 设备驱动由设备镜像/驱动包安装，不属于 CANN toolkit；位置不同时请覆盖。
ASCEND_DRIVER_DIR="${ASCEND_DRIVER_DIR:-/usr/local/Ascend/driver}"
export LD_LIBRARY_PATH="$ASCEND_HOME_PATH/lib64:$ASCEND_HOME_PATH/aarch64-linux/lib64:$ASCEND_DRIVER_DIR/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

CCEC_DIR="$ASCEND_HOME_PATH/tools/ccec_compiler/bin"

# --- 本仓库构建出的工具 ------------------------------------------------------
FRONTEND_BIN="${FRONTEND_BIN:-$OUT_DIR/bin/bishengir-compile}"
HIVMC_BIN="${HIVMC_BIN:-$OUT_DIR/bin/hivmc}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$OUT_DIR/a5-templates}"
DEVICE_BITCODE="${DEVICE_BITCODE:-$TEMPLATE_DIR/regbaseM300.bc}"
HOST_BITCODE="${HOST_BITCODE:-$TEMPLATE_DIR/host.bc}"

# --- 运行时开关 --------------------------------------------------------------
JOBS="${JOBS:-$(nproc)}"
ASCEND_DEVICE_ID="${ASCEND_DEVICE_ID:-0}"
# 若当前登录会话没有设备组（例如刚执行过 usermod -aG HwHiAiUser），
# 可设置 ASCEND_SSH=localhost，通过一个全新的登录会话运行上板程序。
ASCEND_SSH="${ASCEND_SSH:-}"
# 该 ssh 调用的额外参数，例如
#   ASCEND_SSH_OPTS="-i .ssh/id_ed25519"        （路径相对于 $HOME）
ASCEND_SSH_OPTS="${ASCEND_SSH_OPTS:-}"

ensure_dir() { mkdir -p "$1"; }

# 尽量打印相对于仓库的路径：脚本既不应该泄露、也不应该依赖绝对路径。
rel_path() { printf '%s' "${1#"$REPO_ROOT"/}"; }

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "missing: $1" >&2
    echo "  hint: $2" >&2
    exit 1
  fi
}

ensure_dir "$OUT_DIR"

# 在仓库根目录下、带着 toolkit 环境运行一条命令。
#
# 未设置 ASCEND_SSH 时在当前会话执行；设置 ASCEND_SSH=localhost（或其它主机）
# 时通过一个全新的登录会话执行——当 usermod -aG HwHiAiUser 之后当前会话尚未
# 取得设备组时，这是最可靠的运行方式。
run_on_device() {
  local env_string
  env_string="ASCEND_HOME_PATH='$ASCEND_HOME_PATH' ASCEND_OPP_PATH='$ASCEND_OPP_PATH' LD_LIBRARY_PATH='$LD_LIBRARY_PATH'"
  if [[ -n "$ASCEND_SSH" ]]; then
    echo "=== run via ssh $ASCEND_SSH ===" >&2
    # shellcheck disable=SC2086
    ssh $ASCEND_SSH_OPTS "$ASCEND_SSH" \
      "cd '$REPO_ROOT' && $env_string $*"
  else
    echo "=== run in the current session ===" >&2
    ( cd "$REPO_ROOT" && eval "$env_string" "$@" )
  fi
}

device_run_hint() {
  cat >&2 <<EOF

If the log above mentions
    aclInit failed ... open device manager fail ... err=13
the session is missing the device groups.  Log in again, or run through a fresh
session, for example:
    ASCEND_SSH=localhost ASCEND_SSH_OPTS="-i .ssh/<your-key>" \\
        ./scripts/21_run_vecadd.sh
EOF
}
