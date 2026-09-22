#!/usr/bin/env bash
# 从上游 dev/regbase 分支编译 Ascend310B1 的 BiShengIR 前端
# （bishengir-compile）。
#
# A5 前端的工程根在 `<repo>/bishengir`，因此外部工程源码目录指向那里。
# 构建目录里的 LLVM/MLIR 部分与 scripts/11_build_hivmc.sh 共用：
# 只编译一次，之后复用。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

require_file "$ASCENDNPU_IR_A5_DIR/bishengir/lib/Tools/bishengir-compile/BiShengIRCompileMain.cpp" \
  "clone AscendNPU-IR and add the dev/regbase worktree as deps/AscendNPU-IR-a5"
require_file "$ASCENDNPU_IR_DIR/third-party/llvm-project/llvm/CMakeLists.txt" \
  "clone AscendNPU-IR (with submodules) as deps/AscendNPU-IR"

apply_patches() {
  local patch_dir="$1" tree="$2" patch
  shopt -s nullglob
  for patch in "$patch_dir"/*.patch; do
    if git -C "$tree" apply --check --reverse "$patch" >/dev/null 2>&1; then
      echo "  already applied: $(basename "$patch")"
    else
      git -C "$tree" apply "$patch"
      echo "  applied:         $(basename "$patch")"
    fi
  done
  shopt -u nullglob
}

echo "=== apply front-end patches (GCC / toolchain compatibility) ==="
apply_patches "$REPO_ROOT/patches/frontend" "$ASCENDNPU_IR_A5_DIR"

echo "=== configure (shared build tree, dev/regbase front end) ==="
cmake -S "$ASCENDNPU_IR_DIR/third-party/llvm-project/llvm" \
      -B "$ASCENDNPU_IR_BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_ENABLE_PROJECTS=mlir \
      -DLLVM_TARGETS_TO_BUILD=Native \
      -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
      -DLLVM_EXTERNAL_BISHENGIR_SOURCE_DIR="$ASCENDNPU_IR_A5_DIR/bishengir"

echo "=== build bishengir-compile (this takes hours on a 3-core board) ==="
cmake --build "$ASCENDNPU_IR_BUILD_DIR" --target bishengir-compile -- -j"$JOBS"

ensure_dir "$OUT_DIR/bin"
install -m 755 "$ASCENDNPU_IR_BUILD_DIR/bin/bishengir-compile" "$FRONTEND_BIN"
echo "built $(rel_path "$FRONTEND_BIN")"
"$FRONTEND_BIN" --version
