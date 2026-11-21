/** J510 实机键盘往返；由 node_repl 注入 sky，每步刷新并断言真实日志。 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {parseMenuState} from './hd-menu.mjs';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const hash = data => crypto.createHash('sha256').update(data).digest('hex');

export async function runJ510KeyboardAcceptance({sky, config}) {
  const result = {status: 'BLOCKED', runtime: 'Repentance+ v1.9.7.19', checks: [],
    limitations: ['不覆盖手柄、按住时长、其他运行时及渲染/游戏帧测量']};
  await fs.mkdir(config.outputDir, {recursive: false});
  let window;
  const assert = (ok, message) => { if (!ok) throw new Error(message); };
  const read = async () => parseMenuState(await fs.readFile(config.logPath, 'utf8'), '[Isaac Chinese Console]');
  const check = async (label, predicate) => {
    for (let n = 0; n < 20; n++) {
      const state = await read();
      if (predicate(state)) { result.checks.push({label, state}); return state; }
      await sleep(100);
    }
    throw new Error(`${label}: 状态不符 ${JSON.stringify(await read())}`);
  };
  const key = async value => {
    await sky.press_key({window, key: value});
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sleep(160);
  };
  try {
    const windows = (await sky.list_windows()).filter(w => w.title === 'Binding of Isaac: Repentance+ v1.9.7.19');
    assert(windows.length === 1, '目标窗口须唯一');
    window = windows[0];
    assert(hash(await fs.readFile(config.installedMain)) === hash(await fs.readFile(config.sourceMain)), '安装源码不一致');
    const logBefore = await fs.readFile(config.logPath, 'utf8');
    const nativeBefore = await fs.readFile(config.nativeLogPath, 'utf8');
    assert(logBefore.includes('2.5.33'), '版本未加载');
    const initial = await read();
    assert(initial.open && initial.paused && initial.category === 'featured' && initial.page === 1
      && initial.selection === 1 && initial.focus === 'entries' && initial.input === 'none', '起点须为安全房间的精选第一页首项');
    const originalSave = await fs.readFile(config.savePath);
    const originalOptions = await fs.readFile(config.optionsPath);
    result.status = 'FAIL';
    await key('Down'); await check('向下导航', s => s.selection === 3 && s.paused);
    await key('Up'); await check('向上导航', s => s.selection === 1);
    await key('Right'); await check('向右导航', s => s.selection === 2);
    await key('Left'); await check('向左导航', s => s.selection === 1);
    await key('Next'); await check('PageDown 翻页', s => s.page === 2);
    await key('Prior'); await check('PageUp 返回', s => s.page === 1);
    await key('slash'); await check('进入搜索', s => s.input === 'search' && s.paused);
    for (const value of ['z', 'z', 'z']) await key(value);
    await check('搜索过滤为空', s => s.entry === 'none' && s.input === 'search');
    await key('Control_L+a'); await key('BackSpace');
    await check('Ctrl+A 和退格清空', s => s.entry === '1' && s.input === 'search');
    for (const value of ['1', '8', '2']) await key(value);
    await check('数字搜索圣心', s => s.entry === '182' && s.input === 'search');
    await key('BackSpace'); await check('退格更新结果', s => s.entry !== '182' && s.input === 'search');
    await key('2'); await check('重新输入恢复结果', s => s.entry === '182');
    await key('Return'); await check('Enter 结束编辑而不关闭', s => s.open && s.paused && s.input === 'none' && s.entry === '182');
    await key('slash'); await key('Control_L+a'); await key('BackSpace'); await key('Escape');
    await check('Esc 退出编辑', s => s.open && s.paused && s.input === 'none' && s.entry === '1');
    for (let cycle = 1; cycle <= 3; cycle++) {
      await key('F6'); await check(`F6 关闭并释放暂停 ${cycle}`, s => !s.open && !s.paused);
      await key('F6'); await check(`F6 重开并暂停 ${cycle}`, s => s.open && s.paused);
    }
    await key('Escape'); await check('Esc 关闭并释放暂停', s => !s.open && !s.paused);
    await key('F6'); await check('恢复起始菜单', s => s.open && s.paused && s.entry === '1');
    const delta = (await fs.readFile(config.logPath, 'utf8')).slice(logBefore.length);
    assert(!/Error in "|attempt to index|Unterminated JSON|Game Over\./.test(delta), '测试期间存在游戏错误/死亡');
    const nativeDelta = (await fs.readFile(config.nativeLogPath, 'utf8')).slice(nativeBefore.length);
    assert((nativeDelta.match(/ ACQUIRE/g) || []).length === 4 && (nativeDelta.match(/ RELEASE/g) || []).length === 4, '原生暂停获取/释放次数错误');
    assert((await fs.readFile(config.savePath)).equals(originalSave), '测试修改了 Mod 存档');
    assert((await fs.readFile(config.optionsPath)).equals(originalOptions), '测试修改了游戏配置');
    await fs.writeFile(path.join(config.outputDir, 'game-log-delta.txt'), delta);
    await fs.writeFile(path.join(config.outputDir, 'native-log-delta.txt'), nativeDelta);
    result.checks.push({label: '存档/配置不变，原生暂停往返次数一致且无新增错误'});
    result.status = 'PASS';
  } catch (error) { result.error = error.message; }
  result.finishedAt = new Date().toISOString();
  await fs.writeFile(path.join(config.outputDir, 'result.json'), JSON.stringify(result, null, 2));
  return result;
}
