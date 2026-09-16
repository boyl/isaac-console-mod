"""执行高清开关、持久化、缺字补绘与经典几何恢复的双语回归。"""
from pathlib import Path
import sys
import run_mock_game_tests as game

root = Path(__file__).resolve().parents[2]
dll, _ = game.load_lua()
game.configure_lua(dll)
for language, folder, name, version in (
    ('zh', 'workshop-mod', 'Isaac Chinese Console', '2.5.22'),
    ('en', 'workshop-mod-en', 'Console UI', '2.5.4-en.17'),
):
    game.MOD_ROOT = root / folder
    for plus in (False, True):
        for missing in (False, True):
            game.run_scenario(dll, dict(scenario='hd_font', language=language,
                expectedModName=name, expectedVersion=version, repPlus=plus,
                hdFonts=True, hdFail=missing,
                label=f'HD {language} plus={plus} missing={missing}'))
print('PASS: 8 HD toggle / persistence / fallback / geometry scenarios; live visuals NOT_RUN')
if len(sys.argv) > 1:
    baseline = Path(sys.argv[1])
    for language, name, version in [('zh', 'Isaac Chinese Console', '2.5.21'), ('en', 'Console UI', '2.5.4-en.16')]:
        game.MOD_ROOT = baseline / f'installed-{language}'
        game.run_scenario(dll, dict(scenario='upgrade', language=language, expectedModName=name,
            expectedVersion=version, repPlus=True, label=f'old {language} ignores additive HD preference',
            initialSave='version=2.4.2\nhdFontEnabled=1\nfavorites=260,182\nhistory=giveitem c260|spawn 5.10.1'))
    print('PASS: both actual old installation copies read the additive HD field')
