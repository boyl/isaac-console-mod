"""键盘路由、释放、手柄别名和旧运行时契约。"""
from pathlib import Path
import run_mock_game_tests as runner


def main():
    root = Path(__file__).resolve().parents[2]
    paths = [root / name for name in ("workshop-mod", "workshop-mod-en")]
    assert (paths[0] / "scripts/keyboard_input.lua").read_bytes() == (paths[1] / "scripts/keyboard_input.lua").read_bytes()
    runner.HARNESS = Path(__file__).with_name("keyboard_input_contract.lua")
    dll, _ = runner.load_lua()
    runner.configure_lua(dll)
    for path in paths:
        runner.MOD_ROOT = path
        runner.run_scenario(dll, {})


if __name__ == "__main__":
    main()
