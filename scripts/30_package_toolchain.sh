#!/usr/bin/env bash
# 将现有的两个开源编译器原件封装为可搬迁的 Release asset；不重新构建、不 strip。
# 用法：./scripts/30_package_toolchain.sh [输出目录，默认 out/releases]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

[[ $# -le 1 ]] || { echo "usage: $0 [release-directory]" >&2; exit 2; }
[[ "$(uname -m)" == aarch64 ]] || { echo "package these binaries on the aarch64 build host" >&2; exit 1; }
for command in python3 tar gzip sha256sum readelf ldd git install mktemp getconf; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done
for binary in "$FRONTEND_BIN" "$HIVMC_BIN"; do
  [[ -x "$binary" ]] || { echo "missing executable: $binary" >&2; exit 1; }
done
"$FRONTEND_BIN" --version | grep -q 'bishengir-compile 1.2.0' || { echo "expected front end 1.2.0" >&2; exit 1; }
"$HIVMC_BIN" --version | grep -q 'hivmc 1.2.0' || { echo "expected back end 1.2.0" >&2; exit 1; }

name=ascend310b1-toolchain-1.2.0-linux-aarch64
release_dir="${1:-$OUT_DIR/releases}"
mkdir -p "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
work="$(mktemp -d "$release_dir/.package.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
payload="$work/$name"
mkdir -p "$payload/bin" "$payload/licenses" "$payload/patches"
install -m 755 "$FRONTEND_BIN" "$payload/bin/bishengir-compile"
install -m 755 "$HIVMC_BIN" "$payload/bin/hivmc"
cp -a "$REPO_ROOT/patches/." "$payload/patches/"

copy_license() {
  local source="$1" destination="$2"
  [[ -f "$source" ]] || { echo "missing required license/notice: $source" >&2; exit 1; }
  mkdir -p "$(dirname "$payload/licenses/$destination")"
  install -m 644 "$source" "$payload/licenses/$destination"
}
copy_license "$ASCENDNPU_IR_DIR/LICENSE" AscendNPU-IR/LICENSE
copy_license "$ASCENDNPU_IR_DIR/NOTICE" AscendNPU-IR/NOTICE
copy_license "$ASCENDNPU_IR_DIR/Third_Party_Open_Source_Software_Notice" AscendNPU-IR/Third_Party_Open_Source_Software_Notice
copy_license "$ASCENDNPU_IR_A5_DIR/LICENSE.TXT" AscendNPU-IR-a5/LICENSE.TXT
copy_license "$ASCENDNPU_IR_A5_DIR/Third_Party_Open_Source_Software_Notice" AscendNPU-IR-a5/Third_Party_Open_Source_Software_Notice
copy_license "$ASCENDNPU_IR_DIR/bishengir/triton/LICENSE" triton/LICENSE
copy_license "$ASCENDNPU_IR_DIR/third-party/llvm-project/LICENSE.TXT" llvm-project/LICENSE.TXT
copy_license "$ASCENDNPU_IR_DIR/third-party/llvm-project/llvm/LICENSE.TXT" llvm-project/llvm/LICENSE.TXT
copy_license "$ASCENDNPU_IR_DIR/third-party/llvm-project/mlir/LICENSE.TXT" llvm-project/mlir/LICENSE.TXT
for component in torch-mlir shmem; do
  if [[ -f "$ASCENDNPU_IR_DIR/third-party/$component/LICENSE" ]]; then
    copy_license "$ASCENDNPU_IR_DIR/third-party/$component/LICENSE" "$component/LICENSE"
  fi
done

{
  echo "Release: toolchain-v1.2.0-310b1-20261123"
  echo "Package created (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Host architecture: $(uname -m)"
  . /etc/os-release
  echo "Packaging host OS: $PRETTY_NAME"
  echo "Packaging host libc: $(getconf GNU_LIBC_VERSION)"
  echo "Package payload: original existing out/bin ELF files, copied without strip/relink/rebuild"
  echo "Tested deployment baseline: Ubuntu 22.04 aarch64, CANN 9.0.0, Ascend310B1"
  echo "Required symbol versions: GLIBC_2.34, GLIBCXX_3.4.30, CXXABI_1.3.11 (or newer)"
  echo ""
  echo "Provenance limitations:"
  echo "These are previously built compiler files. The original build directory is not required"
  echo "and this package does not claim that the current source trees reproduce them bit for bit."
  echo "The front-end ELF has no embedded Git revision; its original exact build commit is unrecorded."
  echo "The back-end ELF embeds revision f8e8d68cd492 (current checkout SHA recorded below if available)."
  echo "Current source checkouts and available patches are packaging-time evidence only."
  echo ""
  for item in "examples:$REPO_ROOT" "backend:$ASCENDNPU_IR_DIR" "frontend:$ASCENDNPU_IR_A5_DIR" "llvm:$ASCENDNPU_IR_DIR/third-party/llvm-project"; do
    label="${item%%:*}"
    tree="${item#*:}"
    echo "[$label current source checkout]"
    # 必须有本目录自己的 .git，且 Git 返回的仓库根确为本目录，避免无元数据的
    # 前端快照向上发现父仓库并冒用其 commit。损坏的子模块 gitfile 也只记未知。
    if [[ ! -e "$tree/.git" ]] || \
       ! source_root="$(git -C "$tree" rev-parse --show-toplevel 2>/dev/null)" || \
       ! physical_root="$(cd "$tree" && pwd -P)" || \
       ! git_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || \
       [[ "$physical_root" != "$git_root" ]] || \
       ! source_revision="$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null)"; then
      echo "Git metadata unavailable; exact revision unknown/unrecorded"
    else
      echo "$source_revision"
      echo "Tracked-file changes (submodules excluded):"
      if source_status="$(git -C "$tree" status --porcelain=v1 -uno --ignore-submodules=all 2>/dev/null)"; then
        if [[ -n "$source_status" ]]; then
          printf '%s\n' "$source_status"
        else
          echo "none"
        fi
      else
        echo "Git status unavailable; source modification state unknown/unrecorded"
      fi
    fi
    echo ""
  done
  for tool in bishengir-compile hivmc; do
    echo "[$tool --version]"
    "$payload/bin/$tool" --version
    echo "[$tool ELF interpreter/dynamic dependencies/RUNPATH]"
    readelf -l "$payload/bin/$tool" | grep 'Requesting program interpreter'
    readelf -d "$payload/bin/$tool" | grep -E 'NEEDED|RPATH|RUNPATH'
    echo "[$tool required symbol versions]"
    readelf --version-info "$payload/bin/$tool" | grep -oE '(GLIBCXX|GLIBC|CXXABI)_[0-9]+(\.[0-9]+)+' | sort -Vu
    echo "[$tool runtime dependency resolution]"
    ldd "$payload/bin/$tool"
    echo ""
  done
} >"$payload/build-info.txt"

cat >"$payload/README.txt" <<'EOF'
Ascend310B1 open-source toolchain 1.2.0 (Linux aarch64)

Contents: the existing bishengir-compile and hivmc executables, original upstream
licenses/notices, available example-project source patches, build information
and checksums. The ELF executables have not been stripped or relinked.
These are locally built, modified toolchains. patches/ records the available
GCC compatibility, target-architecture and other source changes used by this
example project; build-info.txt explains the remaining provenance limitations.

Tested system: Ubuntu 22.04 aarch64. Runtime needs glibc >= 2.34,
GLIBCXX_3.4.30-capable libstdc++6, libgcc-s1 and zlib1g. This package cannot run
on an x86_64 PC. Only Ascend310B1 with CANN 9.0.0 is the tested device setup.

Not included: CANN toolkit/device compilers, Ascend drivers/firmware, CANN
host/device template bitcode, or any credentials. Install CANN 9.0.0 separately
and run the repository's 05_capture_a5_templates.sh on the target installation.

Verify the downloaded archive against the Release's external SHA256SUMS first.
Then use scripts/06_install_toolchain.sh /path/to/this-package.tar.gz from the
example repository. The installer verifies this package's internal manifest,
architecture, runtime dependencies and compiler self checks before replacing
out/bin, and retains a backup of a previous bin directory.

Full download, extraction, installation and vecadd validation instructions:
https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/blob/main/docs/01-toolchain-build.md

The exact original front-end source commit is unrecorded. build-info.txt
separately records embedded compiler versions and current source-checkout
evidence, with no claim of bit-for-bit reproducibility.
EOF

python3 - "$payload" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
paths = sorted(path for path in root.rglob("*") if path.is_file())
with (root / "SHA256SUMS").open("w", encoding="utf-8", newline="\n") as manifest:
    for path in paths:
        digest = hashlib.sha256()
        with path.open("rb") as input_file:
            for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
                digest.update(chunk)
        manifest.write(f"{digest.hexdigest()}  {path.relative_to(root).as_posix()}\n")
PY

tar --owner=0 --group=0 --numeric-owner -C "$work" -cf - "$name" | gzip -n >"$work/$name.tar.gz"
mv "$work/$name.tar.gz" "$release_dir/$name.tar.gz"
(cd "$release_dir" && sha256sum "$name.tar.gz" >SHA256SUMS)
echo "created: $release_dir/$name.tar.gz"
cat "$release_dir/SHA256SUMS"
