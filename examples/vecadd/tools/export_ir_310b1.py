#!/usr/bin/env python3
"""Validate native debugger snapshots and publish sanitized IR provenance."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile


STAGES = [
    ("10-hfusion.mlir", "convert-linalg-to-hfusion/module/0"),
    ("20-hfusion-scheduled.mlir", "hfusion-auto-schedule/module/0"),
    ("30-hivm-tensor.mlir", "convert-to-hivm-op/module/0"),
    ("40-hivm-buffer.mlir", "one-shot-bufferize/module/0"),
    ("50-hivm-memory-planned.mlir", "hivm-plan-memory/module/2"),
    ("60-hivm-synchronized.mlir", "hivm-graph-sync-solver/add/0"),
]
FILES = ["00-input.mlir", *(name for name, _ in STAGES),
         "70-final-frontend.mlir", "80-device.ll", "81-device-annotated.ll"]
BEGIN = "=== BEGIN NATIVE OPERATION DUMP ==="
END = "=== END NATIVE OPERATION DUMP ==="


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract(args):
    log = Path(args.log).read_text(encoding="utf-8", errors="replace")
    if args.exit_status != 1:
        raise SystemExit(f"expected intentional compiler exit 1, got {args.exit_status}; see {args.log}")
    if log.count(BEGIN) != 1 or log.count(END) != 1:
        raise SystemExit(f"expected exactly one complete native dump; see {args.log}")
    if re.search(r"(?:received|terminated with) signal|Error in sourced command file", log):
        raise SystemExit(f"debugger signal or command failure; see {args.log}")
    if "Unknown command line argument '--intentionally-stop-ir-dump'" not in log:
        raise SystemExit(f"deliberate backend stop not observed; see {args.log}")
    if log.count(f"inject IR file does not exist: {args.missing}") != 1:
        raise SystemExit(f"expected missing-file injection diagnostic was not unique; see {args.log}")
    ir = log.split(BEGIN, 1)[1].split(END, 1)[0].strip() + "\n"
    # Operation::dump prints a self-contained module, including any aliases.
    if not re.search(r'(?m)^(?:module\b|"builtin\.module")', ir):
        raise SystemExit(f"native snapshot is not a complete module; see {args.log}")
    if not ir.lstrip().startswith(("module", "#", "!", '"builtin.module"')):
        raise SystemExit(f"unexpected text before native module; see {args.log}")
    Path(args.output).write_text(
        f"// Native Operation::dump after {args.pass_id}\n" + ir, encoding="utf-8")
    print(f"native snapshot validated: {Path(args.output).name}")


def make_sanitizer(args):
    replacements = {}
    for path, label in (
        (args.device_bitcode, "<DEVICE_BITCODE>"),
        (args.host_bitcode, "<HOST_BITCODE>"),
        (args.scratch, "<EXPORT_SCRATCH>"),
        (args.repo, "<REPO_ROOT>"),
        (args.cann, "<CANN_ROOT>"),
        (args.driver, "<ASCEND_DRIVER_ROOT>"),
        (str(Path.home()), "<HOME>"),
    ):
        if not path:
            continue
        replacements[str(path).rstrip("/")] = label
        replacements[str(Path(path).resolve()).rstrip("/")] = label
    ordered = sorted(replacements.items(), key=lambda item: len(item[0]), reverse=True)

    def sanitize(text):
        for path, label in ordered:
            text = text.replace(path, label)
        # Generated LLVM source filenames may use compiler-created /tmp paths.
        text = re.sub(r'/(?:var/tmp|tmp)/[^"\s<>]*', "<TMP>", text)
        return text
    return sanitize


def repository_revision(repo):
    try:
        return subprocess.check_output(
            ["git", "-C", repo, "rev-parse", "--verify", "HEAD"],
            stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def publish(args):
    scratch = Path(args.scratch)
    source = scratch / "publish"
    destination = Path(args.destination)
    sanitize = make_sanitizer(args)
    for name in FILES:
        path = source / name
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"missing export artifact: {name}")
        text = sanitize(path.read_text(encoding="utf-8"))
        text = "\n".join(line.rstrip() for line in text.splitlines()).rstrip() + "\n"
        path.write_text(text, encoding="utf-8")
    cann_version = "unrecorded (installed separately)"
    cann_metadata = Path(args.cann) / "compiler" / "version.info"
    if cann_metadata.is_file():
        for line in cann_metadata.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("Version="):
                cann_version = line.partition("=")[2].strip()
                break
    common_flags = ["--target=Ascend310B1", "-enable-hfusion-compile=true", "-block-dim=1",
                    "--link-aicore-bitcode=<DEVICE_BITCODE>",
                    "--enable-tuning-mode", "--mlir-disable-threading"]
    provenance = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "target": "Ascend310B1 / dav-m300",
        "input": {"path": "examples/vecadd/mlir/add_310b1.mlir",
                  "sha256": sha256(args.input)},
        "example_repository_commit": repository_revision(args.repo),
        "compilers": {
            "frontend": {"version": sanitize((scratch / "frontend-version.txt").read_text()).strip(),
                         "sha256": sha256(args.frontend), "original_build_revision": "unrecorded"},
            "backend": {"version": sanitize((scratch / "backend-version.txt").read_text()).strip(),
                        "sha256": sha256(args.backend)},
        },
        "environment": {"platform": "Linux aarch64", "libc": " ".join(platform.libc_ver()),
                        "cann": cann_version},
        "common_compile_flags": common_flags,
        "native_snapshots": [
            {"file": name, "after_pass_execution_id": pass_id,
             "method": "GDB exact-entry Operation::emitError breakpoint calling the unchanged ELF Operation::dump",
             "compiler_exit_status": 1,
             "expected_error": "missing injection file followed by deliberately invalid backend option",
             "additional_flags": [f"--inject-ir-after={pass_id}@<EXPECTED_MISSING_FILE>",
                                  "--hivmc-args=--link-host-bitcode=<HOST_BITCODE> --intentionally-stop-ir-dump",
                                  "--save-temps=<RUN_SCRATCH>/temps"],
             "compiler_success_test": False}
            for name, pass_id in STAGES
        ],
        "independent_normal_compilation": {
            "compiler_exit_status": 0,
            "final_frontend_mlir": "70-final-frontend.mlir",
            "device_llvm_ir": "80-device.ll",
            "output_object_produced": True,
            "additional_flags": ["--hivmc-args=--link-host-bitcode=<HOST_BITCODE>",
                                 "--save-temps=<RUN_SCRATCH>/temps"],
            "npu_program_launched": False,
        },
        "annotated_device_ir": {
            "file": "81-device-annotated.ll",
            "tool": "examples/vecadd/tools/patch_310b1_annotation.py --symbol add",
            "purpose": "Add the kernel-entry annotations used by scripts/20_build_vecadd.sh",
        },
        "reproduce": "./examples/vecadd/tools/export_ir_310b1.sh",
        "limitations": [
            "Trailing whitespace is removed and files end with one newline; IR operation contents are unchanged.",
            "This is a version-specific diagnostic export method for the unstripped Linux AArch64 1.2.0 frontend; pass names and occurrence indexes may change in other builds.",
            "The six diagnostic runs intentionally fail and are separate from the successful normal compilation.",
            "Machine-local paths are replaced with placeholders; restore local bitcode paths before recompiling a saved module directly.",
            "CANN binaries, drivers and template bitcode are not included in this output directory.",
            "The original exact frontend source commit is unrecorded; no bit-for-bit compiler rebuild is claimed.",
        ],
    }
    (source / "provenance.json").write_text(
        json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    generated = [*FILES, "provenance.json"]
    (source / "SHA256SUMS").write_text(
        "".join(f"{sha256(source / name)}  {name}\n" for name in generated), encoding="utf-8")
    generated.append("SHA256SUMS")
    destination.mkdir(parents=True, exist_ok=True)
    # Replace only known generated filenames, after every export/check succeeds.
    # An old same-name symlink is replaced, never followed to another file.
    for name in generated:
        descriptor, temporary = tempfile.mkstemp(prefix=f".{name}.", dir=destination)
        try:
            with os.fdopen(descriptor, "wb") as output:
                output.write((source / name).read_bytes())
            os.chmod(temporary, 0o644)
            os.replace(temporary, destination / name)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    print(f"published {len(generated)} sanitized artifacts; SHA256SUMS covers all IR and provenance")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    extraction = commands.add_parser("extract")
    for option in ("log", "output", "pass-id", "missing"):
        extraction.add_argument(f"--{option}", required=True)
    extraction.add_argument("--exit-status", required=True, type=int)
    publication = commands.add_parser("publish")
    for option in ("scratch", "destination", "repo", "frontend", "backend", "input", "cann",
                   "driver", "device-bitcode", "host-bitcode"):
        publication.add_argument(f"--{option}", required=True)
    args = parser.parse_args()
    (extract if args.command == "extract" else publish)(args)


if __name__ == "__main__":
    main()
