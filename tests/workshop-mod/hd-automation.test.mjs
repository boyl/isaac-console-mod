import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {parseMenuState, menuDriver, runHDToggleAcceptance} from '../../tools/acceptance/hd-menu.mjs';

test('状态解析与错误起点禁止确认', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'isaac-hd-automation-'));
  try {
    const logPath = path.join(directory, 'log.txt');
    const log = '[Isaac Chinese Console] menu-state open|active|featured|entries|1|1|object|none|classic|8';
    assert.equal(parseMenuState(log, '[Isaac Chinese Console]').capacity, 8);
    await fs.writeFile(logPath, log);
    let calls = 0;
    const driver = menuDriver({sky: {press_key: async () => calls++}, window: {}, logPath});
    await assert.rejects(driver.toggleHD(), /未选中高清字体/);
    assert.equal(calls, 0);
  } finally { await fs.rm(directory, {recursive: true, force: true}); }
});

for (const corrupt of [false, true]) test(`往返核验：其他字段被改动=${corrupt}`, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'isaac-hd-automation-'));
  try {
    const logPath = path.join(directory, 'log.txt'), savePath = path.join(directory, 'save.dat');
    const optionsPath = path.join(directory, 'options.ini');
    let hd = true;
    const save = () => `hdFontEnabled=${hd ? 1 : 0}\nfavorites=keep\n`;
    const state = () => `[Isaac Chinese Console] menu-state open|active|input_settings|entries|2|2|hd_font_toggle|none|${hd ? 'hd' : 'classic'}|8`;
    await fs.writeFile(logPath, state()); await fs.writeFile(savePath, save()); await fs.writeFile(optionsPath, 'unchanged');
    const sky = {get_window_state: async ({window}) => ({window}), press_key: async ({key}) => {
      assert.equal(key, 'Return'); hd = !hd;
      await fs.writeFile(savePath, save().replace('keep', corrupt ? 'changed' : 'keep'));
      await fs.writeFile(logPath, state());
    }};
    const result = await runHDToggleAcceptance({sky, window: {}, logPath, savePath, optionsPath,
      outputDir: path.join(directory, 'result')});
    assert.equal(result.status, corrupt ? 'FAIL' : 'PASS');
    assert.equal(result.screenshots, 0);
    if (!corrupt) assert.equal(await fs.readFile(savePath, 'utf8'), 'hdFontEnabled=1\nfavorites=keep\n');
  } finally { await fs.rm(directory, {recursive: true, force: true}); }
});
