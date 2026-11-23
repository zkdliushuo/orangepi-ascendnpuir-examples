#!/usr/bin/env bash
# 一键下载、校验、安装二进制工具链，并在本机重新编译和运行两个 vecadd 示例。
# 用法：./scripts/06_install_toolchain.sh [已下载的固定 Release tar.gz]
# 可用 ASCEND_HOME_PATH=/实际/CANN/目录 ./scripts/06_install_toolchain.sh 指定 CANN。
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00_env.sh"

stage=initialization
stage_log=""
work=""
backup=""
replaced=0
main_log="$REPO_ROOT/out/logs/install-toolchain.log"
cleanup() {
  local status=$?
  if [[ "$replaced" == 0 && -n "$backup" && -d "$backup" && ! -e "$OUT_DIR/bin" ]]; then
    mv "$backup" "$OUT_DIR/bin" || echo "restore the previous tools from $backup" >&2
  fi
  [[ -z "$work" ]] || rm -rf -- "$work"
  if [[ "$status" != 0 ]]; then
    echo "FAILED during stage: $stage (exit=$status)" >&2
    echo "Main log: $main_log" >&2
    [[ -z "$stage_log" ]] || echo "Stage log: $stage_log" >&2
    [[ "$stage" != "20: build vecadd" ]] || echo "Compiler log: $OUT_DIR/vecadd/pipeline.log" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

apt_hint() {
  echo "Ubuntu dependencies (run yourself if needed):" >&2
  echo "  sudo apt-get update" >&2
  echo "  sudo apt-get install -y build-essential python3 curl binutils libc6 libstdc++6 libgcc-s1 zlib1g" >&2
}
fail() { echo "ERROR: $*" >&2; exit 1; }
command -v tee >/dev/null || { apt_hint; fail "missing command: tee (coreutils)"; }
mkdir -p "$REPO_ROOT/out/logs"
run_id="$(date -u +%Y%m%dT%H%M%SZ).$$"
log_dir="$REPO_ROOT/out/logs/install-$run_id"
mkdir "$log_dir"
if [[ -f "$main_log" ]]; then
  cp "$main_log" "$log_dir/previous-install-toolchain.log"
fi
exec > >(tee "$main_log") 2>&1
echo "=== Ascend310B1 binary deployment: $run_id ==="
echo "Logs: $main_log ; per-stage logs: $log_dir"

stage="environment preflight"
[[ $# -le 1 ]] || fail "usage: $0 [local-toolchain.tar.gz]"
[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] || fail "requires Linux aarch64; this package cannot run on an x86_64 PC"
for command in python3 ldd getconf cp mv install realpath mktemp grep date find head tail sort basename nproc; do
  command -v "$command" >/dev/null || { apt_hint; fail "missing command: $command"; }
done
command -v "${CXX:-g++}" >/dev/null || { apt_hint; fail "missing C++ compiler: ${CXX:-g++}"; }
if [[ $# == 0 ]]; then
  command -v curl >/dev/null || { apt_hint; fail "missing command: curl"; }
fi

# 21/22 的运行路径固定为 ./out；不允许通过旧产物或其它机器完成自检。
[[ "$(realpath -m "$OUT_DIR")" == "$(realpath -m "$REPO_ROOT/out")" ]] || fail "this one-click workflow requires OUT_DIR=$REPO_ROOT/out because the runners use ./out; remove the OUT_DIR override"
for pair in \
  "FRONTEND_BIN:$FRONTEND_BIN:$REPO_ROOT/out/bin/bishengir-compile" \
  "HIVMC_BIN:$HIVMC_BIN:$REPO_ROOT/out/bin/hivmc" \
  "TEMPLATE_DIR:$TEMPLATE_DIR:$REPO_ROOT/out/a5-templates" \
  "DEVICE_BITCODE:$DEVICE_BITCODE:$REPO_ROOT/out/a5-templates/regbaseM300.bc" \
  "HOST_BITCODE:$HOST_BITCODE:$REPO_ROOT/out/a5-templates/host.bc"; do
  variable="${pair%%:*}"
  paths="${pair#*:}"
  value="${paths%%:*}"
  expected="${paths#*:}"
  [[ "$(realpath -m "$value")" == "$(realpath -m "$expected")" ]] || fail "$variable must use the default path $expected; remove its environment/config.local.sh override"
done
[[ -z "$ASCEND_SSH" ]] || fail "this workflow validates the current board; unset ASCEND_SSH and log in again if device-group membership has changed"
[[ "$ASCEND_DEVICE_ID" == 0 ]] || fail "the example runners use device 0; set ASCEND_DEVICE_ID=0"
OUT_DIR="$REPO_ROOT/out"
FRONTEND_BIN="$OUT_DIR/bin/bishengir-compile"
HIVMC_BIN="$OUT_DIR/bin/hivmc"
TEMPLATE_DIR="$OUT_DIR/a5-templates"
DEVICE_BITCODE="$TEMPLATE_DIR/regbaseM300.bc"
HOST_BITCODE="$TEMPLATE_DIR/host.bc"
export OUT_DIR FRONTEND_BIN HIVMC_BIN TEMPLATE_DIR DEVICE_BITCODE HOST_BITCODE

glibc="$(getconf GNU_LIBC_VERSION)"
python3 - "$glibc" <<'PY'
import ctypes
import sys
version = tuple(int(part) for part in sys.argv[1].split()[-1].split("."))
if version < (2, 34):
    raise SystemExit("requires glibc >= 2.34; Ubuntu 22.04 aarch64 is the tested system")
for library in ("libz.so.1", "libstdc++.so.6", "libgcc_s.so.1"):
    try:
        ctypes.CDLL(library)
    except OSError as error:
        raise SystemExit(f"missing/unusable runtime library {library}: {error}; install zlib1g/libstdc++6/libgcc-s1")
print("system runtime libraries and glibc: OK")
PY

# 常见安装位置只在当前配置无法定位 toolkit 时使用，不扫描整个文件系统。
previous_cann="$ASCEND_HOME_PATH"
if ! _looks_like_cann "$ASCEND_HOME_PATH"; then
  shopt -s nullglob
  for candidate in \
    "$HOME/Ascend/cann/latest" /usr/local/Ascend/cann/latest \
    "$HOME/Ascend/ascend-toolkit/latest" /usr/local/Ascend/ascend-toolkit/latest \
    "$HOME"/Ascend/cann/9.0* /usr/local/Ascend/cann/9.0* \
    "$HOME"/Ascend/ascend-toolkit/9.0* /usr/local/Ascend/ascend-toolkit/9.0*; do
    if _looks_like_cann "$candidate"; then
      ASCEND_HOME_PATH="$candidate"
      break
    fi
  done
  shopt -u nullglob
fi
_looks_like_cann "$ASCEND_HOME_PATH" || fail "CANN 9.0.0 toolkit not found. Install the aarch64 toolkit and 310B kernel package, then run ASCEND_HOME_PATH=/actual/CANN $0"
if [[ "$ASCEND_OPP_PATH" == "$previous_cann/opp" ]]; then
  ASCEND_OPP_PATH="$ASCEND_HOME_PATH/opp"
fi
export ASCEND_HOME_PATH ASCEND_OPP_PATH
export LD_LIBRARY_PATH="$ASCEND_HOME_PATH/lib64:$ASCEND_HOME_PATH/aarch64-linux/lib64:$ASCEND_DRIVER_DIR/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
CCEC_DIR="$ASCEND_HOME_PATH/tools/ccec_compiler/bin"
echo "CANN: $ASCEND_HOME_PATH ; OPP: $ASCEND_OPP_PATH ; driver: $ASCEND_DRIVER_DIR"
for version_file in "$ASCEND_HOME_PATH/compiler/version.info" "$ASCEND_OPP_PATH/version.info"; do
  [[ -r "$version_file" ]] || fail "missing CANN version metadata: $version_file; install the complete CANN 9.0.0 toolkit + 310B kernel package"
  grep -Eq '^Version=9\.0\.0[[:space:]]*$' "$version_file" || fail "expected CANN 9.0.0 in $version_file"
done
for executable in \
  "$ASCEND_HOME_PATH/bin/bishengir-compile-a5" "$ASCEND_HOME_PATH/bin/hivmc-a5" \
  "$CCEC_DIR/ccec" "$CCEC_DIR/bisheng" "$CCEC_DIR/ld.lld" "$CCEC_DIR/llvm-objcopy"; do
  [[ -x "$executable" ]] || fail "missing CANN executable: $executable; install the complete CANN 9.0.0 toolkit"
done
host_bisheng="$ASCEND_HOME_PATH/tools/bisheng_compiler/bin/bisheng"
[[ -x "$host_bisheng" ]] || host_bisheng="$CCEC_DIR/bisheng"
for required in \
  "$ASCEND_HOME_PATH/tools/bishengir/lib/host.bc" \
  "$ASCEND_HOME_PATH/aarch64-linux/include/acl/acl.h" \
  "$ASCEND_HOME_PATH/aarch64-linux/include/acl/acl_rt.h" \
  "$ASCEND_HOME_PATH/aarch64-linux/lib64/libascendc_runtime.a" \
  "$ASCEND_DRIVER_DIR/lib64/libascend_hal.so"; do
  [[ -r "$required" ]] || fail "missing CANN/driver file: $required; install the complete toolkit/driver or correct ASCEND_HOME_PATH/ASCEND_DRIVER_DIR"
done
for library in libruntime.so libascendcl.so libmmpa.so libc_sec.so libslog.so libprofapi.so; do
  found=0
  for directory in "$ASCEND_HOME_PATH/lib64" "$ASCEND_HOME_PATH/aarch64-linux/lib64" "$ASCEND_DRIVER_DIR/lib64"; do
    [[ ! -r "$directory/$library" ]] || found=1
  done
  [[ "$found" == 1 ]] || fail "missing link library: $library; check the CANN toolkit and driver installation"
done
for executable in "$ASCEND_HOME_PATH/bin/bishengir-compile-a5" "$ASCEND_HOME_PATH/bin/hivmc-a5" "$CCEC_DIR/ccec" "$host_bisheng"; do
  "$executable" --version >"$log_dir/$(basename "$executable").version.log" 2>&1 || fail "CANN tool cannot run: $executable; see $log_dir"
done
for device in /dev/davinci0 /dev/davinci_manager; do
  [[ -c "$device" ]] || fail "missing character device: $device; install/start the board's Ascend driver"
  if [[ ! -r "$device" || ! -w "$device" ]]; then
    echo "Device access denied: $device ; current groups: $(id -nG)"
    echo "Ask the administrator to grant the device groups, for example:"
    echo '  sudo usermod -aG HwHiAiUser,HwBaseUser,HwDmUser "$(whoami)"'
    fail "log out and log in again, then rerun this command; the installer does not change device permissions"
  fi
done
# 子脚本会再次读取 config.local.sh；若它重新覆盖自动发现的路径，提前报错。
child_cann="$(bash -c 'source "$1/scripts/00_env.sh"; printf "%s" "$ASCEND_HOME_PATH"' _ "$REPO_ROOT")"
[[ "$child_cann" == "$ASCEND_HOME_PATH" ]] || fail "scripts/config.local.sh overrides the selected CANN path for child scripts; correct its ASCEND_HOME_PATH setting"
for script in 05_capture_a5_templates.sh 20_build_vecadd.sh 21_run_vecadd.sh 22_llvm_ir_launcher.sh; do
  [[ -r "$REPO_ROOT/scripts/$script" ]] || fail "missing repository script: scripts/$script"
done
echo "environment preflight: OK (device 0 is readable/writable)"

tag=toolchain-v1.2.0-310b1-20261123
asset=ascend310b1-toolchain-1.2.0-linux-aarch64.tar.gz
expected_sha=49b7e2bd5fb2d63f396446291479bb2b4ba5000d00e8054dbfe774a36cf73221
manifest=""
if [[ $# == 0 ]]; then
  stage="download fixed GitHub Release"
  download_dir="$OUT_DIR/downloads/install-$run_id"
  mkdir -p "$download_dir"
  base="https://github.com/zkdliushuo/orangepi-ascendnpuir-examples/releases/download/$tag"
  for download in "$asset" SHA256SUMS; do
    echo "Downloading: $base/$download"
    curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 \
      --max-time 900 --proto '=https' --proto-redir '=https' \
      "$base/$download" --output "$download_dir/$download.part"
    mv "$download_dir/$download.part" "$download_dir/$download"
  done
  archive="$download_dir/$asset"
  manifest="$download_dir/SHA256SUMS"
else
  stage="read local Release archive"
  [[ -f "$1" ]] || fail "local archive not found: $1"
  archive="$(realpath "$1")"
fi
stage="verify Release SHA256"
python3 - "$archive" "$manifest" "$asset" "$expected_sha" <<'PY'
import hashlib
from pathlib import Path
import re
import sys
archive, manifest, name, expected = sys.argv[1:]
if manifest:
    matches = []
    for line in Path(manifest).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
        if match and match.group(2) == name:
            matches.append(match.group(1).lower())
    if matches != [expected]:
        raise SystemExit("Release SHA256SUMS is missing, duplicated or different from the pinned checksum")
digest = hashlib.sha256()
with open(archive, "rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != expected:
    raise SystemExit(f"archive SHA256 mismatch: expected {expected}, got {digest.hexdigest()}")
print(f"Release archive SHA256: OK ({expected})")
PY
work="$(mktemp -d "$OUT_DIR/.toolchain-install.XXXXXXXX")"
stage="extract and verify package payload"

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
stage="compiler runtime and target self checks"
for tool in bishengir-compile hivmc; do
  echo "=== check $tool runtime libraries ==="
  ldd "$payload/bin/$tool" >"$work/$tool.ldd" 2>&1 || { cat "$work/$tool.ldd" >&2; exit 1; }
  if grep -q 'not found' "$work/$tool.ldd"; then
    cat "$work/$tool.ldd" >&2
    apt_hint
    echo "The libstdc++6 runtime must provide GLIBCXX_3.4.30 (the compiler version itself is not restricted)." >&2
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
stage="install compiler binaries"
[[ ! -L "$OUT_DIR/bin" ]] || fail "out/bin is a symlink; use a real out/bin directory for this workflow"
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

# 保存旧生成物后重新生成模板/IR/内核/runner，防止从旧文件获得虚假的测试成功。
stage="prepare clean example output directories"
for directory in "$TEMPLATE_DIR" "$OUT_DIR/vecadd"; do
  [[ ! -L "$directory" ]] || fail "generated output directory is a symlink: $directory; use a real directory"
  if [[ -e "$directory" ]]; then
    [[ -d "$directory" ]] || fail "generated output path is not a directory: $directory"
    mv "$directory" "$directory.before-install.$run_id"
    echo "previous generated files retained: $directory.before-install.$run_id"
  fi
done

run_stage() {
  stage="$1"
  stage_log="$log_dir/$3"
  echo "=== $stage ==="
  if (cd "$REPO_ROOT" && bash "$REPO_ROOT/scripts/$2") 2>&1 | tee "$stage_log"; then
    return 0
  else
    local -a pipeline_status=("${PIPESTATUS[@]}")
    echo "stage failed; see $stage_log" >&2
    [[ "${pipeline_status[0]}" != 0 ]] || exit 1
    exit "${pipeline_status[0]}"
  fi
}
run_stage "05: capture A5 templates" 05_capture_a5_templates.sh 05-capture-templates.log
run_stage "20: build vecadd" 20_build_vecadd.sh 20-build-vecadd.log
run_stage "21: run C runner" 21_run_vecadd.sh 21-run-c.log
stage="21: verify C runner results"
grep -Fx 'VECADD PASS' "$stage_log" >/dev/null || fail "C runner did not report VECADD PASS"
grep -Eq '^check: 0/1024 mismatched;' "$stage_log" || fail "C runner did not report 0/1024 mismatched"
run_stage "22: build and run LLVM IR launcher" 22_llvm_ir_launcher.sh 22-run-llvm.log
stage="22: verify LLVM IR launcher results"
grep -Fx 'VECADD PASS (LLVM IR launcher)' "$stage_log" >/dev/null || fail "LLVM IR launcher did not report VECADD PASS"
grep -Eq '^check: 0/1024 mismatched;' "$stage_log" || fail "LLVM IR launcher did not report 0/1024 mismatched"

stage=complete
echo "=== SUCCESS: binary toolchain installed and both device tests passed ==="
echo "C runner: VECADD PASS; 0/1024 mismatched"
echo "LLVM IR launcher: VECADD PASS (LLVM IR launcher); 0/1024 mismatched"
echo "Compilers: $OUT_DIR/bin/bishengir-compile ; $OUT_DIR/bin/hivmc"
echo "Main log: $main_log"
echo "Per-stage logs: $log_dir"
