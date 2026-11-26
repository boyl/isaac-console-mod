/** J514 中文经典布局的鼠标/搜索往返；只使用本次实机校准的尺寸。 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseMenuState} from './hd-menu.mjs';
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export async function* runJ514MouseKeyboardAcceptance({sky, config}) {
  const result = {status: 'BLOCKED', checks: [], limitations: [
    '仅中文 J514、2214×1232 窗口、经典布局；不覆盖方向键、键盘翻页、斜杠快捷键或手柄'
  ]};
  await fs.mkdir(config.outputDir, {recursive: false});
  const assert = (ok, message) => { if (!ok) throw new Error(message); };
  const readLog = () => fs.readFile(config.logPath, 'utf8');
  const read = async () => parseMenuState(await readLog(), '[Isaac Chinese Console]');
  let window;
  const refresh = async () => {
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sleep(160);
  };
  const key = async value => { await sky.press_key({window, key: value}); await refresh(); };
  const click = async (x, y) => {
    const frame = await sky.get_window_state({window, include_screenshot: true, include_text: true});
    window = frame.window;
    assert(frame.screenshots.length === 1 && frame.screenshots[0].width === 2214
      && frame.screenshots[0].height === 1232, '窗口尺寸变化，停止使用已校准坐标');
    await sky.click({window, x, y, screenshotId: frame.screenshots[0].id}); await refresh();
  };
  const check = async (label, predicate) => {
    for (let n = 0; n < 20; n++) {
      const state = await read();
      if (predicate(state)) { result.checks.push({label, state}); return state; }
      await sleep(100);
    }
    throw new Error(`${label}: ${JSON.stringify(await read())}`);
  };
  try {
    const windows = (await sky.list_windows()).filter(w => w.title === 'Binding of Isaac: Repentance+ v1.9.7.20');
    assert(windows.length === 1, '目标窗口须唯一'); window = windows[0];
    assert(hash(await fs.readFile(config.installedMain)) === hash(await fs.readFile(config.sourceMain)), '安装源码不一致');
    const logBefore = await readLog();
    assert(logBefore.includes(config.version) && logBefore.includes('measured layout 553.0:300.0:16:20:5:125:62:73:196:32'), '版本或布局不符');
    const initial = await read();
    assert(initial.open && initial.paused && initial.category === 'featured' && initial.page === 1
      && initial.input === 'none' && initial.style === 'classic', '起点须为已打开的经典精选第一页');
    const saveBefore = await fs.readFile(config.savePath);
    const optionsBefore = await fs.readFile(config.optionsPath);
    result.status = 'FAIL'; yield {phase: 'preconditions'};
    await click(300, 455);
    const catalog = await check('鼠标切换分类', s => s.category === 'all_items' && s.page === 1 && s.paused);
    yield {phase: 'category'};
    await click(2110, 240); await check('鼠标下一页', s => s.page === 2 && s.category === 'all_items');
    yield {phase: 'next-page'};
    await click(1607, 240); await check('鼠标上一页', s => s.page === 1 && s.entry === catalog.entry);
    yield {phase: 'previous-page'};
    await click(1790, 130); await check('鼠标聚焦搜索', s => s.input === 'search');
    yield {phase: 'search-focus'};
    for (const value of ['1', '8', '2']) await key(value);
    await check('键盘数字搜索', s => s.entry === '182' && s.input === 'search');
    yield {phase: 'numeric-search'};
    await key('Return'); await check('Enter 完成编辑', s => s.entry === '182' && s.input === 'none' && s.paused);
    yield {phase: 'search-confirm'};
    await click(1790, 130); await check('重新聚焦搜索', s => s.input === 'search');
    yield {phase: 'search-refocus'};
    await key('Control_L+a'); await key('BackSpace');
    await check('Ctrl+A 和退格清空', s => s.entry === catalog.entry && s.input === 'search');
    await key('Escape'); await check('Esc 退出编辑', s => s.open && s.input === 'none' && s.paused);
    yield {phase: 'search-clear'};
    await click(300, 375); await check('返回精选', s => s.category === 'featured' && s.entry === initial.entry);
    yield {phase: 'restore-category'};
    await click(2108, 130); await check('鼠标关闭并释放暂停', s => !s.open && !s.paused);
    await key('F6'); await check('F6 重开并暂停', s => s.open && s.paused && s.entry === initial.entry);
    yield {phase: 'close-reopen'};
    const delta = (await readLog()).slice(logBefore.length);
    assert(!/Error in "|attempt to index|Unterminated JSON|Game Over\./.test(delta), '新增错误或死亡');
    assert((await fs.readFile(config.savePath)).equals(saveBefore), 'Mod 存档发生变化');
    assert((await fs.readFile(config.optionsPath)).equals(optionsBefore), '游戏配置发生变化');
    await fs.writeFile(path.join(config.outputDir, 'game-log-delta.txt'), delta);
    result.checks.push({label: '存档和配置字节不变，无新增回调错误'});
    result.status = 'PASS';
  } catch (error) { result.error = error.message; }
  result.finishedAt = new Date().toISOString();
  await fs.writeFile(path.join(config.outputDir, 'result.json'), JSON.stringify(result, null, 2));
  return result;
}
