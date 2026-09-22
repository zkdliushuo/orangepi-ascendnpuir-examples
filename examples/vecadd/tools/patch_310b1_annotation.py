#!/usr/bin/env python3
"""为 lowering 后的设备 LLVM IR 补上 CCEC 需要的内核入口元数据。"""

import argparse
import re
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--symbol", default="add")
    args = parser.parse_args()

    ir = args.input.read_text(encoding="utf-8")
    if "!hivm.annotations" not in ir:
        used_ids = {
            int(value)
            for value in re.findall(r"(?m)^!(\d+)\s*=", ir)
        }
        metadata_id = 0
        while metadata_id in used_ids:
            metadata_id += 1
        ir = ir.rstrip() + (
            "\n"
            f"!hivm.annotations = !{{!{metadata_id}}}\n"
            f'!{metadata_id} = !{{ptr @{args.symbol}, !"kernel", i32 1}}\n'
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(ir, encoding="utf-8")


if __name__ == "__main__":
    main()
