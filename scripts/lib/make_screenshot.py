#!/usr/bin/env python3
"""把验证日志渲染成终端风格的 PNG 截图。

用法: make_screenshot.py <日志> <输出.png> [--title 文本] [--root 目录]

位于 --root 之下的绝对路径会被改写成相对路径，因此图片里不会出现
与具体机器相关的目录。
"""

import argparse
import os
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

BACKGROUND = (24, 26, 31)
BAR = (44, 47, 56)
TEXT = (222, 226, 230)
GREEN = (126, 214, 143)
CYAN = (137, 200, 240)
YELLOW = (230, 200, 120)
DOT_RED = (237, 108, 96)
DOT_YELLOW = (245, 191, 79)
DOT_GREEN = (98, 197, 84)


def color_for(line: str):
    if "PASS" in line:
        return GREEN
    if line.startswith("==="):
        return CYAN
    if "FAIL" in line or "error" in line.lower():
        return DOT_RED
    if "check:" in line or "Warning" in line:
        return YELLOW
    return TEXT


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--title", default="orangepi: ~/ascend310b1-vecadd")
    parser.add_argument("--root", default=None)
    parser.add_argument("--width", type=int, default=1120)
    args = parser.parse_args()

    root = args.root or os.getcwd()
    lines = []
    for line in args.log.read_text(encoding="utf-8").splitlines():
        if line.startswith("Warning: Permanently added"):
            continue
        if line.strip() == "":
            continue
        line = line.replace(root.rstrip("/") + "/", "")
        line = re.sub(r"module-\d+-\d+\.ll", "module-<pid>.ll", line)
        lines.append(line)

    font = ImageFont.truetype(FONT, 17)
    bold = ImageFont.truetype(FONT_BOLD, 19)

    padding = 22
    line_height = 24
    bar_height = 46
    text_width = max(font.getlength(line) for line in lines)
    width = max(args.width, int(text_width) + 2 * padding)
    height = bar_height + padding + line_height * len(lines) + padding

    image = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, width, bar_height], fill=BAR)
    for index, color in enumerate((DOT_RED, DOT_YELLOW, DOT_GREEN)):
        x = 20 + index * 22
        draw.ellipse([x, bar_height // 2 - 7, x + 14, bar_height // 2 + 7],
                     fill=color)
    draw.text((20 + 3 * 22 + 16, bar_height // 2 - 11), args.title,
              font=bold, fill=(206, 212, 218))

    y = bar_height + padding
    for line in lines:
        draw.text((padding, y), line, font=font, fill=color_for(line))
        y += line_height

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    print(f"wrote {args.output} ({width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
