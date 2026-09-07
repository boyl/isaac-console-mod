"""对已知实机布局执行页面与光标断言，不将系统光标纳入结论。"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parent


def inspect(path, reference, origin=(900, 420)):
    frame = Image.open(path).convert('RGB')
    baseline = Image.open(reference).convert('RGB')
    if frame.size != baseline.size:
        raise ValueError(f'未经校准的截图尺寸：{frame.size}；预期 {baseline.size}')
    # 设置分类、第二页首位数字及总项数；状态标题会随开关改变，不作为固定模板。
    boxes = [(485, 390, 610, 465), (1945, 215, 2015, 295), (2110, 214, 2300, 296)]
    errors = []
    for box in boxes:
        # 只比较亮色文字，忽略卡片未选择/选择后的合法背景颜色变化。
        actual = frame.crop(box).convert('L').point(lambda value: 255 if value > 160 else 0)
        expected = baseline.crop(box).convert('L').point(lambda value: 255 if value > 160 else 0)
        diff = ImageStat.Stat(ImageChops.difference(actual, expected)).sum[0]
        union = ImageStat.Stat(ImageChops.lighter(actual, expected)).sum[0]
        errors.append(diff / max(union, 1))
    settings_page = max(errors) < 0.08
    # 指针位于卡片中不含文字的空白区；与游戏画布尺寸绑定。
    x, y = origin
    black = [frame.getpixel((x + dx, y + dy)) for dx, dy in [(2, 3), (1, 35)]]
    white = [frame.getpixel((x + dx, y + dy)) for dx, dy in [(10, 25), (20, 45)]]
    visible = all(max(c) < 40 for c in black) and all(min(c) > 220 for c in white)
    # 无指针时四个采样点均为同一张卡片的背景色，避免把错误坐标算作关闭成功。
    samples = black + white
    absent = all(70 < c[0] < 160 and 15 < c[1] < 80 and 25 < c[2] < 100 for c in samples)
    return dict(settingsPage=settings_page, pageErrors=errors, cursorVisible=visible,
                cursorAbsent=absent, size=frame.size, sampleOrigin=[x, y])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--reference', type=Path, default=ROOT / 'fixtures/zh-settings-page2.jpg')
    args = parser.parse_args()
    print(json.dumps(inspect(args.image, args.reference), ensure_ascii=True))


if __name__ == '__main__':
    main()
