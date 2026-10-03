"""使用既有 Lua 5.1 编译实验主文件，捕获块级局部变量上限等错误。"""
import importlib.util
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mock", root / "tests/workshop-mod/run_mock_game_tests.py")
mock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mock)
dll, _ = mock.load_lua()
mock.configure_lua(dll)
for name in ("zh-main.lua", "en-main.lua"):
    raw = (Path(sys.argv[1]) / name).read_bytes()
    state = dll.luaL_newstate()
    try:
        status = dll.luaL_loadbuffer(state, raw, len(raw), name.encode())
        if status:
            raise AssertionError(mock.error_text(dll, state))
        print("PACKAGE_LUA_COMPILE_PASS", name)
    finally:
        dll.lua_close(state)
