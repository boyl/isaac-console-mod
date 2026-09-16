"""验证 BMFont 页面、度量、灰度抗锯齿、源码覆盖与 Lua 样板语法。"""
import hashlib
import json
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    folder = Path(sys.argv[1])
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    for name, sha in manifest["files"].items():
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == sha, name
    for role, expected in manifest["profiles"].items():
        data = (folder / f"hd_{role}.fnt").read_bytes()
        assert data[:4] == b"BMF\x03"
        offset, blocks = 4, {}
        while offset < len(data):
            kind, size = struct.unpack_from("<BI", data, offset)
            assert kind not in blocks
            blocks[kind] = data[offset + 5:offset + 5 + size]
            assert len(blocks[kind]) == size
            offset += 5 + size
        assert offset == len(data)
        height, base, width, texheight, pages = struct.unpack_from("<HHHHH", blocks[2])
        assert height / 2 == expected["lineHeight"]
        assert 0 < base <= height and height >= expected["atlasSize"] * 1.4
        names = blocks[3].rstrip(b"\0").split(b"\0")
        assert len(names) == pages == expected["pages"]
        assert len({len(name) for name in names}) == 1, "BMFont 页面名须固定长度"
        assert len(blocks[4]) == expected["glyphs"] * 20
        glyphs = set()
        for start in range(0, len(blocks[4]), 20):
            code, x, y, w, h, xo, yo, advance, page, channel = struct.unpack_from("<IHHHHhhhBB", blocks[4], start)
            assert code not in glyphs and x + w <= width and y + h <= texheight
            assert yo >= 0 and yo + h <= height and advance >= 0 and page < pages
            glyphs.add(code)
        assert set(map(ord, "中文ABC懒惧鬱龍0123")) <= glyphs
        for name in names:
            im = Image.open(folder / name.decode())
            assert im.mode == "RGBA" and im.size == (width, texheight)
            histogram = im.getchannel("A").histogram()
            assert sum(histogram[1:255]) > 0, "没有抗锯齿灰度"
        print(f"PASS {role}: {len(glyphs)} glyphs / {pages} pages / metrics / grayscale")
    import run_mock_game_tests as lua
    dll, _ = lua.load_lua()
    lua.configure_lua(dll)
    state = dll.luaL_newstate()
    try:
        source = (ROOT / "tools/font-probe/main.lua").read_bytes()
        status = dll.luaL_loadbuffer(state, source, len(source), b"hd-font-probe")
        assert status == 0, lua.error_text(dll, state)
    finally:
        dll.lua_close(state)
    print("PASS Lua 5.1 syntax; actual game visual gate NOT_RUN")


if __name__ == "__main__":
    main()
