"""从已提取原生资源生成图标动画描述，不打包游戏图片。

用法：python generate-item-icon-animations.py <已提取的 resources 或 resources-dlc3 目录>
资源归 Nicalis/Edmund McMillen 所有；本工具生成布局描述，运行时读取玩家游戏贴图。
"""
from pathlib import Path
import argparse
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FRAME = dict(XPosition='0', YPosition='0', XScale='100', YScale='100', Delay='1',
             Visible='true', RedTint='255', GreenTint='255', BlueTint='255', AlphaTint='255',
             RedOffset='0', GreenOffset='0', BlueOffset='0', Rotation='0', Interpolated='false')

def actor(sheets, animation, count):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='Isaac Console', Version='31', Fps='30')
    content = ET.SubElement(root, 'Content')
    paths = ET.SubElement(content, 'Spritesheets')
    layers = ET.SubElement(content, 'Layers')
    for id_, name in enumerate(sheets):
        ET.SubElement(paths, 'Spritesheet', Path='isaac_console_pixel.png', Id=str(id_))
        ET.SubElement(layers, 'Layer', Name=name, Id=str(id_), SpritesheetId=str(id_))
    ET.SubElement(content, 'Nulls')
    ET.SubElement(content, 'Events')
    animations = ET.SubElement(root, 'Animations', DefaultAnimation=animation)
    anim = ET.SubElement(animations, 'Animation', Name=animation, FrameNum=str(count), Loop='false')
    root_animation = ET.SubElement(anim, 'RootAnimation')
    ET.SubElement(root_animation, 'Frame', **(FRAME | {'Delay':str(count)}))
    frames = ET.SubElement(anim, 'LayerAnimations')
    result = [ET.SubElement(frames, 'LayerAnimation', LayerId=str(i), Visible='true') for i in range(len(sheets))]
    ET.SubElement(anim, 'NullAnimations')
    ET.SubElement(anim, 'Triggers')
    return root, result

def write(root, name):
    ET.indent(root, space='  ')
    data = ET.tostring(root, encoding='utf-8') + b'\n'
    for folder in ('workshop-mod', 'workshop-mod-en'):
        (ROOT / folder / 'resources/gfx/ui' / name).write_bytes(data)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('resources', type=Path)
    args = parser.parse_args()
    native = args.resources
    hud = ET.parse(native / 'gfx/ui/ui_cardspills.anm2')
    fronts = hud.find('Animations/Animation[@Name="CardFronts"]/LayerAnimations/LayerAnimation[@LayerId="0"]')
    # 不使用原文件陈旧 FrameNum=78；实际有 98 帧，含隐藏索引 0。
    assert len(fronts) == 98
    pickup_files = {}
    for path in (native/'gfx').glob('005.3*.anm2'):
        prefix = path.name.split('_', 1)[0]
        if not re.fullmatch(r'005\.(?:30[1-9]|31[0-3]|300\.[0-9]+)', prefix):
            continue
        pickup_id = int(prefix.split('.')[-1]) if prefix.startswith('005.300.') else int(prefix[4:]) - 300
        pickup_files[pickup_id] = path
    cards = {int(card.get('id')):card for card in ET.parse(native/'pocketitems.xml').getroot()
             if card.tag in ('card', 'rune')}
    root, layers = actor(['CardFronts', 'PocketHUD'], 'Cards', 97)
    for id_ in range(1, 98):
        frame = fronts[id_]
        layer_id = 0
        if frame.get('Visible') != 'true':
            path = pickup_files[int(cards[id_].get('pickup'))]
            pickup = ET.parse(path)
            candidates = [f for f in pickup.findall('Animations/Animation[@Name="HUD"]/LayerAnimations/LayerAnimation/Frame')
                          if f.get('Visible') == 'true']
            assert len(candidates) == 1, (id_, path)
            frame = candidates[0]
            layer_id = 1
        # 居中、原色、固定帧，不包含闪烁或拾取事件。
        geometry = {key:frame.get(key) for key in ('XCrop','YCrop','Width','Height')}
        geometry |= {'XPivot':str(int(geometry['Width'])//2), 'YPivot':str(int(geometry['Height'])//2)}
        for i, layer in enumerate(layers):
            ET.SubElement(layer, 'Frame', **(FRAME | geometry | {'Visible':'true' if i == layer_id else 'false'}))
    write(root, 'isaac_console_cards.anm2')
    root, layers = actor(['Item'], 'Icon', 1)
    ET.SubElement(layers[0], 'Frame', **(FRAME | {'XCrop':'0','YCrop':'0','Width':'32','Height':'32','XPivot':'16','YPivot':'16'}))
    write(root, 'isaac_console_item.anm2')
    print('GENERATED: 97 card/rune IDs + centered 32x32 item template; no PNG copied')

if __name__ == '__main__':
    main()
