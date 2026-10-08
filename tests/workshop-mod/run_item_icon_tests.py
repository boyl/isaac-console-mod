"""运行双语图标 Lua 契约和动画资源断言。"""
import ctypes
from pathlib import Path
import xml.etree.ElementTree as ET
import run_mock_game_tests as game

ROOT = Path(__file__).resolve().parents[2]
HARNESS = Path(__file__).with_name('item_icons_contract.lua')

def main():
    dll, runtime = game.load_lua()
    game.configure_lua(dll)
    for folder in ('workshop-mod', 'workshop-mod-en'):
        mod = ROOT / folder
        # 先编译所有发布 Lua；覆盖 Lua 5.1 主块局部变量上限。
        for path in mod.rglob('*.lua'):
            state = dll.luaL_newstate()
            try:
                source = path.read_bytes()
                result = dll.luaL_loadbuffer(state, source, len(source), str(path).encode())
                assert result == 0, game.error_text(dll, state)
            finally:
                dll.lua_close(state)
        source = (f'MOD_ROOT = {game.lua_string(mod.as_posix())}\n'
                  f'dofile({game.lua_string(HARNESS.as_posix())})').encode()
        state = dll.luaL_newstate()
        try:
            dll.luaL_openlibs(state)
            assert dll.luaL_loadbuffer(state, source, len(source), b'item-icons-contract') == 0
            assert dll.lua_pcall(state, 0, 0, 0) == 0, game.error_text(dll, state)
        finally:
            dll.lua_close(state)
        animation = ET.parse(mod / 'resources/gfx/ui/isaac_console_cards.anm2')
        cards = animation.find('Animations/Animation[@Name="Cards"]')
        assert int(cards.get('FrameNum')) == 97
        layers = cards.findall('LayerAnimations/LayerAnimation')
        assert len(layers) == 2 and all(len(layer) == 97 for layer in layers)
        for frame in range(97):
            assert sum(layer[frame].get('Visible') == 'true' for layer in layers) == 1
        # 独立预期：CardFronts 使用卡牌 ID，打包动画使用 ID-1。
        ordinary = layers[0]
        assert ordinary[0].get('XCrop') == '0' and ordinary[0].get('YCrop') == '0'
        assert ordinary[78].get('XCrop') == '112' and ordinary[78].get('YCrop') == '48'
        assert ordinary[79].get('XCrop') == '112' and ordinary[79].get('YCrop') == '72'
        special = layers[1]
        for id_, crop in {32:(128,64),36:(128,96),41:(192,64),55:(0,128),78:(96,128),
                          81:(256,0),97:(256,64)}.items():
            frame = special[id_ - 1]
            assert frame.get('Visible') == 'true'
            assert (int(frame.get('XCrop')), int(frame.get('YCrop'))) == crop, id_
        print(f'ANIMATION PASS {folder}; 97 IDs, 2 layers, special-frame boundaries')
    for relative in ('scripts/item_icons.lua', 'resources/gfx/ui/isaac_console_item.anm2',
                     'resources/gfx/ui/isaac_console_cards.anm2'):
        assert (ROOT/'workshop-mod'/relative).read_bytes() == (ROOT/'workshop-mod-en'/relative).read_bytes()
    for folder, name, version in (('workshop-mod','Isaac Chinese Console','2.5.28'),
                                  ('workshop-mod-en','Console UI','2.5.4-en.23')):
        game.MOD_ROOT = ROOT / folder
        for plus, repentogon in ((False, False), (True, False), (False, True), (True, True)):
            for width, height, hd in ((451,257,False),(480,270,False),(553,300,False),(960,540,True)):
                game.run_scenario(dll, dict(scenario='item_icons', repPlus=plus, repentogon=repentogon,
                    screenWidth=width,screenHeight=height,hdFonts=hd,eid=hd,
                    language='zh' if folder=='workshop-mod' else 'en',
                    expectedModName=name,expectedVersion=version,
                    label=f'icons {folder} plus={plus} repentogon={repentogon} {width}x{height} hd={hd}'))
    print(f'PASS bilingual icon gate; Lua runtime={runtime}; liveGame=NOT_RUN')

if __name__ == '__main__':
    main()
