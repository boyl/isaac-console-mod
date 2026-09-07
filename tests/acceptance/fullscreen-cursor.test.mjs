import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {runCursorAcceptance} from '../../tools/acceptance/fullscreen-cursor.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
async function session({enabled = true, fault = '', legacy = false} = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'isaac-cursor-runner-'));
  const screenshotDir = path.join(root, 'screenshots');
  await fs.mkdir(screenshotDir);
  const config = {outputDir: path.join(root, 'result'), screenshotDir,
    savePath: path.join(root, fault === 'wrong-slot' ? 'save2.dat' : 'save1.dat'), optionsPath: path.join(root, 'options.ini'),
    logPath: path.join(root, 'game.log'), installedMain: path.join(repo, 'workshop-mod/main.lua'),
    gameExe: 'C:/game/isaac-ng.exe', timeoutMs: 600, settleMs: 0, captureIntervalMs: 0};
  const original = legacy ? 'version=2.5.20\nfavorites=c:182\n'
    : `version=2.5.21\nfullscreenCursorEnabled=${enabled ? 1 : 0}\nfavorites=c:182\n`;
  await fs.writeFile(config.savePath, original);
  await fs.writeFile(config.optionsPath, 'Fullscreen=1\nUseExclusiveFullscreen=0\nMouseControl=0\n');
  const source = await fs.readFile(config.installedMain, 'utf8');
  const version = source.match(/local VERSION = "([^"]+)"/)[1];
  await fs.writeFile(config.logPath, `Binding of Isaac: Repentance+ v1.9.7.17\n[Isaac Chinese Console] v${version};\nLoading PersistentGameData from Steam Cloud: rep+persistentgamedata1.dat.`);
  let clicks = 0, captures = 0, value = enabled;
  const window = {id: 1, app: config.gameExe, title: 'Isaac'};
  const sky = {
    list_windows: async () => fault === 'ambiguous' ? [window, window] : [window],
    get_window_state: async () => ({window}),
    press_key: async ({key}) => {
      assert.equal(key, 'F12');
      captures++;
      if (fault === 'stale') return;
      const observation = {settingsPage: fault !== 'wrong-page', cursorVisible: value, cursorAbsent: !value};
      if (fault === 'render' && clicks === 1) observation.cursorVisible = observation.cursorAbsent = false;
      await fs.writeFile(path.join(screenshotDir, `${captures}.jpg`), JSON.stringify(observation));
    },
    click: async ({x, y}) => {
      assert.equal(x, 900); assert.equal(y, 420);
      clicks++;
      if (fault === 'lost-click') return;
      value = !value;
      const data = await fs.readFile(config.savePath, 'utf8');
      const next = data.includes('fullscreenCursorEnabled=')
        ? data.replace(/fullscreenCursorEnabled=[01]/, `fullscreenCursorEnabled=${value ? 1 : 0}`)
        : data.replace('\n', `\nfullscreenCursorEnabled=${value ? 1 : 0}\n`);
      await fs.writeFile(config.savePath, next.replace(/^version=[^\n]*/, `version=${version}`));
      if (fault === 'unrelated') await fs.appendFile(config.savePath, 'unexpected=data\n');
      if (fault === 'options') await fs.appendFile(config.optionsPath, 'MouseControl=1\n');
    },
  };
  try {
    const result = await runCursorAcceptance({sky, config, inspectFrame: async file => JSON.parse(await fs.readFile(file, 'utf8'))});
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(config.outputDir, 'result.json'), 'utf8')), result);
    return {result, clicks, save: await fs.readFile(config.savePath, 'utf8'), original};
  } finally {
    // mkdtemp 创建的专属目录，先核验解析后的目标仍在系统临时目录内。
    assert(path.resolve(root).startsWith(path.resolve(os.tmpdir()) + path.sep));
    await fs.rm(root, {recursive: true});
  }
}
for (const enabled of [true, false]) {
  test(`批量开关并恢复初值 ${enabled}`, async () => {
    const s = await session({enabled});
    assert.equal(s.result.status, 'PASS'); assert.equal(s.clicks, 2);
    assert.equal(s.save, s.original); assert.equal(s.result.restoration, 'restored-through-ui');
  });
}
test('旧存档缺省开启并保留迁移之外的全部字段', async () => {
  const s = await session({legacy: true});
  assert.equal(s.result.status, 'PASS'); assert.equal(s.clicks, 2);
  assert.equal(s.result.restoration, 'restored-with-save-migration');
  assert.equal(s.save, 'version=2.5.21\nfullscreenCursorEnabled=1\nfavorites=c:182\n');
});
for (const fault of ['wrong-page', 'stale', 'ambiguous', 'wrong-slot']) {
  test(`前置失败不点击：${fault}`, async () => {
    const s = await session({fault});
    assert.equal(s.result.status, 'BLOCKED'); assert.equal(s.clicks, 0); assert.equal(s.save, s.original);
  });
}
for (const fault of ['render', 'lost-click']) {
  test(`故障失败并保留原数据：${fault}`, async () => {
    const s = await session({fault});
    assert.equal(s.result.status, 'FAIL'); assert.equal(s.save, s.original);
    assert.equal(s.result.restoration, 'restored-through-ui');
  });
}
for (const fault of ['unrelated', 'options']) {
  test(`额外变化不可被恢复操作掩盖：${fault}`, async () => {
    const s = await session({fault});
    assert.equal(s.result.status, 'FAIL'); assert.equal(s.result.restoration, 'NEEDS_RECOVERY');
  });
}
