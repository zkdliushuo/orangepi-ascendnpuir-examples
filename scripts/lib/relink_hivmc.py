#!/usr/bin/env python3
"""把 ninja 的 hivmc 链接命令改写成会重新扫描静态库的命令。

BiShengIR 与 Triton 的静态库互相依赖
（BiShengIRHIVMTransforms <-> BiShengIRHIVMCLib、TritonAscendGPUToLLVM <->
TritonAscendGPUToDPX 等），而 CMake 会把最后一组库追加在
tools/hivmc/CMakeLists.txt 设置的链接分组之后。把所有归档包进一个
"-Wl,--start-group ... -Wl,--end-group" 里，GNU ld 就能解析这些环。

用法: relink_hivmc.py <ninja 链接命令文件> <输出二进制> [替换用的输出路径]
"""

import re
import sys


def main() -> int:
    command_file, output_binary = sys.argv[1], sys.argv[2]
    replacement = sys.argv[3] if len(sys.argv) > 3 else output_binary

    command = open(command_file, encoding="utf-8").read().strip()
    command = command.replace(" -Wl,--start-group", "")
    command = command.replace(" -Wl,--end-group", "")

    # 把 ninja 末尾的 "&& :" 留在链接分组之外
    tail = ""
    match = re.search(r"\s*&&\s*:\s*$", command)
    if match:
        tail = command[match.start():]
        command = command[: match.start()]

    first_archive = re.search(r"(?<![\w/.-])lib/", command)
    if not first_archive:
        raise SystemExit("链接命令里没有找到静态库")

    grouped = (
        command[: first_archive.start()]
        + "-Wl,--start-group "
        + command[first_archive.start():]
        + " -Wl,--end-group"
        + tail
    )
    grouped = grouped.replace("bin/hivmc", replacement)
    print(grouped)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
