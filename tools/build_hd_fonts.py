"""从已锁定的思源黑体生成独立高清字体样板；不修改正式 Mod。"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
ROLES = {"title": (12, "Medium"), "body": (10, "Regular"), "caption": (10, "Regular")}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def charset():
    # 保守包含源码中所有可见字符，覆盖字符串、文案和注释；另补 GB2312。
    required = set(range(32, 127))
    for folder in ("workshop-mod", "workshop-mod-en", "tools/font-probe"):
        for path in (ROOT / folder).rglob("*.lua"):
            text = path.read_text(encoding="utf-8-sig")
            # 分类装饰图标由原有图标路径绘制，不作为正文字形。
            text = re.sub(r'icon\s*=\s*"[^"]*"', '', text)
            required.update(ord(c) for c in text if c.isprintable())
    common = set()
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                common.add(ord(bytes((high, low)).decode("gb2312")))
            except UnicodeDecodeError:
                pass
    return required, common


def block(kind, content):
    return struct.pack("<BI", kind, len(content)) + content


def generate(font_path, role, logical_size, codes, output):
    size = logical_size * 2
    font = ImageFont.truetype(str(font_path), size, layout_engine=ImageFont.Layout.BASIC)
    ascent, descent = font.getmetrics()
    line_height = max(ascent + descent, math.ceil(size * 1.4))
    side, padding = 1024, 2
    pages = [Image.new("RGBA", (side, side), (255, 255, 255, 0))]
    x = y = padding
    row_height = 0
    records = []
    for code in sorted(codes):
        char = chr(code)
        left, top, right, bottom = font.getbbox(char, anchor="ls")
        width, height = max(1, right - left), max(1, bottom - top)
        if x + width + padding > side:
            x, y, row_height = padding, y + row_height + padding * 2, 0
        if y + height + padding > side:
            pages.append(Image.new("RGBA", (side, side), (255, 255, 255, 0)))
            x = y = padding
            row_height = 0
        mask = Image.new("L", (width, height))
        ImageDraw.Draw(mask).text((-left, -top), char, font=font, fill=255, anchor="ls")
        glyph = Image.new("RGBA", mask.size, (255, 255, 255, 0))
        glyph.putalpha(mask)
        pages[-1].paste(glyph, (x, y))
        advance = round(font.getlength(char))
        records.append(struct.pack("<IHHHHhhhBB", code, x, y, width, height,
                                   left, ascent + top, advance, len(pages) - 1, 15))
        x += width + padding * 2
        row_height = max(row_height, height)
    if len(pages) > 255:
        raise ValueError("字体纹理页超过 BMFont 格式限制")
    names = [f"hd_{role}_{i:03d}.png" for i in range(len(pages))]
    # OFL 保留名称不用于派生字体的主名称。
    info = struct.pack("<hBBHBBBBBBBB", size, 0x40, 0, 100, 1, 0, 0, 0, 0, 1, 1, 0)
    info += f"Isaac Console HD {role}".encode() + b"\0"
    common = struct.pack("<HHHHHBBBBB", line_height, ascent, side, side, len(pages), 0, 0, 4, 4, 4)
    data = b"BMF\x03" + block(1, info) + block(2, common)
    data += block(3, b"".join(name.encode() + b"\0" for name in names))
    data += block(4, b"".join(records))
    (output / f"hd_{role}.fnt").write_bytes(data)
    for page, name in zip(pages, names):
        page.save(output / name)
    return {"logicalSize": logical_size, "atlasSize": size, "scale": 0.5,
            "lineHeight": line_height / 2, "baseline": ascent / 2,
            "glyphs": len(codes), "pages": len(pages)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() and any(args.output.iterdir()):
        raise ValueError("输出目录必须为空，避免混入旧纹理页")
    args.output.mkdir(parents=True, exist_ok=True)
    source = json.loads((args.sources / "source.json").read_text(encoding="utf-8-sig"))
    for entry in source["files"]:
        entry["Path"] = Path(entry["Path"]).name
    expected = {Path(item["Path"]).name: item["Hash"].lower() for item in source["files"]}
    required, common = charset()
    profiles = {}
    for role, (size, weight) in ROLES.items():
        path = args.sources / f"{weight}.otf"
        if digest(path) != expected[path.name]:
            raise ValueError(f"源字体哈希不匹配：{path}")
        cmap = TTFont(path).getBestCmap()
        missing = required - cmap.keys()
        if missing:
            raise ValueError(f"源码字符缺失：{''.join(chr(c) for c in sorted(missing))}")
        codes = required | (common & cmap.keys())
        profiles[role] = generate(path, role, size, codes, args.output)
    shutil.copyfile(args.sources / "LICENSE-OFL.txt", args.output / "LICENSE-OFL.txt")
    (args.output / "coverage.lua").write_text("return {" + ",".join(f"[{c}]=true" for c in sorted(codes)) + "}\n", encoding="utf-8")
    manifest = {"source": source, "profiles": profiles, "requiredGlyphs": len(required),
                "files": {p.name: digest(p) for p in sorted(args.output.iterdir())}}
    (args.output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": "PASS", "profiles": profiles, "requiredGlyphs": len(required)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
