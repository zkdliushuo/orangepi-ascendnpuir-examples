#!/usr/bin/env bash
# 安装已下载并通过外部 SHA256SUMS 校验的 Linux aarch64 工具链包。
# 用法：./scripts/06_install_toolchain.sh /path/to/ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: $0 /path/to/toolchain.tar.gz (verify the release SHA256SUMS first)" >&2
  exit 2
fi
[[ "$(uname -m)" == aarch64 ]] || { echo "requires Linux aarch64; this package does not run on x86_64" >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo "requires Linux" >&2; exit 1; }
for command in python3 ldd getconf cp mv install realpath mktemp grep date; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

archive="$(realpath "$1")"
mkdir -p "$OUT_DIR"
work="$(mktemp -d "$OUT_DIR/.toolchain-install.XXXXXXXX")"
backup=""
replaced=0
cleanup() {
  local status=$?
  if [[ "$replaced" == 0 && -n "$backup" && -d "$backup" && ! -e "$OUT_DIR/bin" ]]; then
    mv "$backup" "$OUT_DIR/bin" || echo "restore the previous tools from $backup" >&2
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 只解包普通文件/目录；拒绝绝对路径、..、链接、设备文件及重复路径。
# 同时验证包内清单覆盖所有文件，避免把未校验的二进制装入 out/bin。
python3 - "$archive" "$work" <<'PY'
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile

archive, destination = sys.argv[1:]
prefix = "ascend310b1-toolchain-1.2.0-linux-aarch64"
seen = set()
files = set()
with tarfile.open(archive, "r:gz") as package:
    members = package.getmembers()
    if len(members) > 10000 or sum(m.size for m in members) > 2 * 1024**3:
        raise SystemExit("unexpectedly large toolchain archive")
    for member in members:
        path = PurePosixPath(member.name)
        if (path.is_absolute() or ".." in path.parts or "\\" in member.name
                or not path.parts or path.parts[0] != prefix
                or not (member.isdir() or member.isfile())):
            raise SystemExit(f"unsafe archive member: {member.name!r}")
        normalized = str(path)
        if normalized in seen:
            raise SystemExit(f"duplicate archive member: {member.name!r}")
        seen.add(normalized)
        target = Path(destination).joinpath(*path.parts)
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            source = package.extractfile(member)
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            os.chmod(target, 0o755 if path.parts[1:2] == ("bin",) else 0o644)
            files.add(str(PurePosixPath(*path.parts[1:])))

root = Path(destination) / prefix
manifest = root / "SHA256SUMS"
listed = set()
for line in manifest.read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
    if not match:
        raise SystemExit("invalid package SHA256SUMS")
    checksum, name = match.groups()
    if name not in files or name == "SHA256SUMS" or name in listed:
        raise SystemExit(f"unexpected checksum path: {name!r}")
    digest = hashlib.sha256()
    with (root / name).open("rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != checksum:
        raise SystemExit(f"checksum mismatch: {name}")
    listed.add(name)
if listed != files - {"SHA256SUMS"}:
    raise SystemExit("package SHA256SUMS does not cover every payload file")
for name in ("bishengir-compile", "hivmc"):
    with (root / "bin" / name).open("rb") as executable:
        data = executable.read(20)
    if len(data) != 20 or data[:6] != b"\x7fELF\x02\x01" or int.from_bytes(data[18:20], "little") != 183:
        raise SystemExit(f"not an ELF64 little-endian AArch64 executable: {name}")
print("archive paths, payload SHA256SUMS and ELF architecture: OK")
PY

payload="$work/ascend310b1-toolchain-1.2.0-linux-aarch64"
glibc="$(getconf GNU_LIBC_VERSION)"
python3 - "$glibc" <<'PY'
import sys
version = tuple(int(part) for part in sys.argv[1].split()[-1].split("."))
if version < (2, 34):
    raise SystemExit("this package requires glibc >= 2.34; Ubuntu 22.04 aarch64 is the tested system")
PY

for tool in bishengir-compile hivmc; do
  echo "=== check $tool runtime libraries ==="
  ldd "$payload/bin/$tool" >"$work/$tool.ldd" 2>&1 || { cat "$work/$tool.ldd" >&2; exit 1; }
  if grep -q 'not found' "$work/$tool.ldd"; then
    cat "$work/$tool.ldd" >&2
    echo "install the required runtime libraries (including GLIBCXX_3.4.30-capable libstdc++6)" >&2
    exit 1
  fi
  "$payload/bin/$tool" --version | tee "$work/$tool.version"
  grep -q "$tool 1.2.0" "$work/$tool.version" || { echo "unexpected $tool version" >&2; exit 1; }
done
"$payload/bin/bishengir-compile" --help >"$work/frontend.help"
grep -q Ascend310B1 "$work/frontend.help" || { echo "front end does not advertise Ascend310B1" >&2; exit 1; }
"$payload/bin/hivmc" --help >"$work/hivmc.help"

# 先构造完整的新 bin，保留原目录中的其它工具；只有所有检查通过才替换。
# 两个工具随目录一起切换。每次 rename 在同一文件系统完成；中断会恢复旧目录。
[[ ! -L "$OUT_DIR/bin" ]] || { echo "out/bin is a symlink; choose another OUT_DIR" >&2; exit 1; }
mkdir "$work/new-bin"
if [[ -d "$OUT_DIR/bin" ]]; then
  cp -a "$OUT_DIR/bin/." "$work/new-bin/"
elif [[ -e "$OUT_DIR/bin" ]]; then
  echo "out/bin exists but is not a directory" >&2
  exit 1
fi
# 不跟随旧目录里同名工具的符号链接。
rm -f -- "$work/new-bin/bishengir-compile" "$work/new-bin/hivmc"
install -m 755 "$payload/bin/bishengir-compile" "$work/new-bin/bishengir-compile"
install -m 755 "$payload/bin/hivmc" "$work/new-bin/hivmc"
if [[ -d "$OUT_DIR/bin" ]]; then
  backup="$OUT_DIR/bin.backup.$(date -u +%Y%m%dT%H%M%SZ).$$"
  mv "$OUT_DIR/bin" "$backup"
fi
mv "$work/new-bin" "$OUT_DIR/bin"
replaced=1
info="$OUT_DIR/toolchain-info.$(date -u +%Y%m%dT%H%M%SZ).$$"
mkdir "$info"
cp -a "$payload/licenses" "$payload/patches" "$payload/build-info.txt" "$payload/README.txt" "$payload/SHA256SUMS" "$info/"
echo "installed: $OUT_DIR/bin/bishengir-compile and $OUT_DIR/bin/hivmc"
echo "licenses and build information: $info"
[[ -z "$backup" ]] || echo "previous bin directory retained: $backup"
echo "next: ./scripts/05_capture_a5_templates.sh && ./scripts/20_build_vecadd.sh && ./scripts/21_run_vecadd.sh && ./scripts/22_llvm_ir_launcher.sh"
