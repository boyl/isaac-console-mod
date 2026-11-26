"""复用菜单行为契约，独立模拟 J514 查询 API 与玩家索引不一致的边界。"""
from pathlib import Path
import run_mock_game_tests as runner


def main():
    root = Path(__file__).resolve().parents[2]
    dll, _ = runner.load_lua()
    runner.configure_lua(dll)
    count = 0
    # Use the existing behavioral cases; only the engine input boundary changes.
    cases = [case for case in runner.scenarios()
             if case.get("repPlus") and str(case.get("scenario", "")).startswith("controller")
             and case.get("scenario") != "controller_enumeration_failure"]
    assert cases, "No controller behavior cases selected"
    cases = [dict(scenario="j514_device_isolation", label=f"device isolation signed={signed}",
                  repPlus=True, signedKeyboardId=signed) for signed in (False, True)] + cases
    for folder, name, version in (
        ("workshop-mod", "Isaac Chinese Console", "2.5.35"),
        ("workshop-mod-en", "Console UI", "2.5.4-en.30"),
    ):
        runner.MOD_ROOT = root / folder
        for case in cases:
            config = dict(case, j514Input=True, keyboardIndex=-2,
                          expectedModName=name, expectedVersion=version,
                          language="zh" if folder == "workshop-mod" else "en")
            print(f"J514 {folder}: {case['label']}", flush=True)
            runner.run_scenario(dll, config)
            count += 1
    print(f"J514_INPUT_PASS scenarios={count}")


if __name__ == "__main__":
    main()
