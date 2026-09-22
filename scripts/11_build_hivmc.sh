#!/usr/bin/env bash
# 编译 Ascend310B1 的 BiShengIR 设备后端（hivmc）。
#
# dev/regbase 里没有 hivmc：它按名字调用外部 `hivmc-a5`。开源树中带 A5 后端的
# 是 master，而 master 与 dev/regbase 是同一个 BiShengIR 版本（1.2.0）——
# 这正是让前后端匹配的前提。这里复用 scripts/10_build_frontend.sh 建立的
# 共享 LLVM/MLIR 构建目录，因此最耗时的部分只编译一次。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

require_file "$ASCENDNPU_IR_DIR/bishengir/lib/Tools/hivmc/HIVMCMain.cpp" \
  "clone AscendNPU-IR (master) as deps/AscendNPU-IR"
require_file "$ASCENDNPU_IR_BUILD_DIR/CMakeCache.txt" \
  "run scripts/10_build_frontend.sh first (it bootstraps LLVM/MLIR)"

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

echo "=== apply hivmc patches ==="
apply_patches "$REPO_ROOT/patches/hivmc" "$ASCENDNPU_IR_DIR"

echo "=== configure (shared build tree, master hivmc) ==="
cmake -S "$ASCENDNPU_IR_DIR/third-party/llvm-project/llvm" \
      -B "$ASCENDNPU_IR_BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_ASSERTIONS=OFF \
      -DLLVM_ENABLE_PROJECTS=mlir \
      -DLLVM_TARGETS_TO_BUILD=Native \
      -DCMAKE_CXX_COMPILER="${CXX:-g++}" \
      -DLLVM_EXTERNAL_BISHENGIR_SOURCE_DIR="$ASCENDNPU_IR_DIR" \
      -DBISHENGIR_BUILD_HIVMC=ON \
      -DLLVM_INCLUDE_TESTS=ON \
      -DMLIR_INCLUDE_TESTS=ON

# hivmc 会链接 MLIR 的测试库；它的循环形状指纹表由一个自定义命令生成，
# 而对象库并没有依赖该生成目标；这里先手工生成一次，避免并行构建时竞态。
skew_table="$ASCENDNPU_IR_BUILD_DIR/tools/bishengir/bishengir/lib/Dialect/HIVM/Transforms/SkewShapeTable.inc"
if [[ ! -f "$skew_table" ]]; then
  mkdir -p "$(dirname "$skew_table")"
  python3 "$ASCENDNPU_IR_DIR/build-tools/coverage/shape_registry.py" \
    --emit-cxx "$skew_table"
  echo "pre-generated $skew_table"
fi

echo "=== build hivmc objects (link step is expected to fail, see below) ==="
cmake --build "$ASCENDNPU_IR_BUILD_DIR" --target hivmc -- -j"$JOBS" || true

# BiShengIR/Triton 的静态库互相成环，而 CMake 追加的最后一组库位于链接分组
# 之外，因此最后一次链接需要让链接器重新扫描。这里拿 ninja 自己的链接命令，
# 把所有归档包进同一个链接分组后重新执行。
echo "=== relink hivmc with a link group ==="
ninja -C "$ASCENDNPU_IR_BUILD_DIR" -t commands hivmc | tail -1 >"$OUT_DIR/hivmc-link.cmd"
python3 "$REPO_ROOT/scripts/lib/relink_hivmc.py" \
  "$OUT_DIR/hivmc-link.cmd" "$ASCENDNPU_IR_BUILD_DIR/bin/hivmc" \
  >"$OUT_DIR/hivmc-link.sh"
(cd "$ASCENDNPU_IR_BUILD_DIR" && bash "$OUT_DIR/hivmc-link.sh")

ensure_dir "$OUT_DIR/bin"
install -m 755 "$ASCENDNPU_IR_BUILD_DIR/bin/hivmc" "$HIVMC_BIN"
echo "built $(rel_path "$HIVMC_BIN")"
"$HIVMC_BIN" --version
