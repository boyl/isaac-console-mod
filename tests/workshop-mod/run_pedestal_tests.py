"""执行真实入口的底座设置与生成集成场景。"""
from pathlib import Path
import run_mock_game_tests as harness


def main():
    root = Path(__file__).resolve().parents[2]
    assert (root / "workshop-mod/scripts/collectible_pedestals.lua").read_bytes() == (root / "workshop-mod-en/scripts/collectible_pedestals.lua").read_bytes(), "双语生成逻辑必须一致"
    dll, path = harness.load_lua()
    harness.configure_lua(dll)
    for folder, name, language in (("workshop-mod", "Isaac Chinese Console", "zh"),
                                    ("workshop-mod-en", "Console UI", "en")):
        harness.MOD_ROOT = root / folder
        import re
        version = re.search(r'local VERSION = "([^"]+)"', (harness.MOD_ROOT / "main.lua").read_text(encoding="utf-8"))[1]
        for runtime, plus, dragon in (("Repentance", False, False), ("Repentance+", True, False), ("REPENTOGON", False, True)):
            for saved in ("", "version=old\nfavorites=\nhistory=", "pedestalEnabled=1\n", "pedestalEnabled=invalid\n"):
                harness.run_scenario(dll, dict(scenario="pedestals", label=f"{language} {runtime} save={saved!r}",
                    expectedModName=name, expectedVersion=version, language=language,
                    repPlus=plus, repentogon=dragon, updatePause=dragon, initialSave=saved))
            harness.run_scenario(dll, dict(scenario="pedestals", label=f"{language} {runtime} 480x270",
                expectedModName=name, expectedVersion=version, language=language,
                repPlus=plus, repentogon=dragon, updatePause=dragon, initialSave="",
                screenWidth=480, screenHeight=270))
    print(f"PEDESTAL_GATE=OK; 30 scenarios; Lua={path}", flush=True)


if __name__ == "__main__":
    main()
