"""用真实历史截图验证识别器；此处 PASS 不代表本轮游戏已运行。"""
import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'tools/acceptance'
spec = importlib.util.spec_from_file_location('frames', DIRECTORY / 'inspect_cursor_frame.py')
frames = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frames)
REFERENCE = DIRECTORY / 'fixtures/zh-settings-page2.jpg'


class FrameTests(unittest.TestCase):
    def test_real_unselected_settings_card(self):
        result = frames.inspect(DIRECTORY / 'fixtures/zh-settings-page2-unselected.jpg', REFERENCE)
        self.assertTrue(result['settingsPage'])

    def test_real_disabled_frame(self):
        result = frames.inspect(REFERENCE, REFERENCE)
        self.assertTrue(result['settingsPage'])
        self.assertTrue(result['cursorAbsent'])
        self.assertFalse(result['cursorVisible'])

    def test_real_enabled_frame_at_recorded_click(self):
        result = frames.inspect(DIRECTORY / 'fixtures/zh-settings-cursor-on.jpg', REFERENCE, (1150, 425))
        self.assertTrue(result['settingsPage'])
        self.assertTrue(result['cursorVisible'])
        self.assertFalse(result['cursorAbsent'])

    def test_unknown_page_is_not_a_match(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'unknown.png'
            Image.new('RGB', (2561, 1440), 'black').save(file)
            self.assertFalse(frames.inspect(file, REFERENCE)['settingsPage'])

    def test_uncalibrated_size_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'small.png'
            Image.new('RGB', (960, 540)).save(file)
            with self.assertRaisesRegex(ValueError, '截图尺寸'):
                frames.inspect(file, REFERENCE)


if __name__ == '__main__':
    unittest.main(verbosity=2)
