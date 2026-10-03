"""验证暂停期间的真实菜单源码与命令队列，不替代实机测试。"""
import importlib.util
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / "tests/workshop-mod/run_mock_game_tests.py"
spec = importlib.util.spec_from_file_location("mock", path)
mock = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mock)
dll, runtime = mock.load_lua()
mock.configure_lua(dll)
source = mock.HARNESS.read_text(encoding="utf-8")
marker = "local scenario = scenarios[TEST_CONFIG.scenario]"
assert source.count(marker) == 1
scenario = Path(__file__).with_name("integration-scenario.lua").read_text(encoding="utf-8")
# 临时扩展同目录 Harness，使其相对引用和原有回归保持不变。
temporary = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", suffix=".lua",
    prefix="native-pause-", dir=mock.HARNESS.parent, delete=False)
temporary.write(source.replace(marker, scenario + "\n" + marker))
temporary.close()
mock.HARNESS = Path(temporary.name)
for directory, name, version, language in [
    ("workshop-mod", "Isaac Chinese Console", "2.5.24", "zh"),
    ("workshop-mod-en", "Console UI", "2.5.4-en.19", "en"),
]:
    mock.MOD_ROOT = root / directory
    mock.run_scenario(dll, {
        "scenario": "native_pause_prototype", "repPlus": True,
        "expectedModName": name, "expectedVersion": version,
        "language": language, "label": "native pause " + language,
    })
print("PAUSE_MENU_INTEGRATION_PASS languages=2")
mock.HARNESS.unlink()
