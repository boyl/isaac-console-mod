/** 启动或复用以撒窗口。正常流程零截图、不重复启动、不自动开始新一局。 */
import fs from 'node:fs/promises';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export async function openIsaac({sky, gameExe, timeoutMs = 25000}) {
  await fs.access(gameExe);
  if (!/[/\\]isaac-ng\.exe$/i.test(gameExe)) throw new Error('目标不是 isaac-ng.exe');
  const normalized = gameExe.replaceAll('\\', '/').toLowerCase();
  const find = async () => (await sky.list_windows()).filter(window =>
    window.app.replaceAll('\\', '/').toLowerCase() === `process:${normalized}`);
  let windows = await find();
  if (windows.length > 1) throw new Error('发现多个以撒窗口，停止自动操作');
  const launched = windows.length === 0;
  if (launched) {
    await sky.launch_app({app: gameExe});
    const deadline = Date.now() + timeoutMs;
    do {
      windows = await find();
      if (windows.length) break;
      await sleep(500);
    } while (Date.now() < deadline);
  }
  if (windows.length !== 1) throw new Error(`未获得唯一以撒窗口：${windows.length}`);
  const state = await sky.get_window_state({window: windows[0], include_screenshot: false, include_text: true});
  await sky.activate_window({window: state.window});
  return {status: 'PASS', action: launched ? 'launched' : 'reused', title: state.window.title,
    window: state.window, screenshots: 0, gameStarted: 'NOT_ASSERTED'};
}

/** 仅复用已实机校准的 Rep / Rep+ 启动路径；不适用于运行中的未知菜单。 */
export async function continueCalibratedRun({sky, launch, logPath, slot = 1}) {
  if (launch.action !== 'launched' || !['Binding of Isaac: Repentance+ v1.9.7.17', 'Binding of Isaac: Repentance'].includes(launch.title) || slot !== 1) {
    throw new Error('仅支持已校准的 Rep / Rep+ 新启动路径及存档槽 1');
  }
  let window = launch.window;
  const keys = [];
  await sleep(1800);
  for (let step = 0; step < 4; step++) {
    const log = await fs.readFile(logPath, 'utf8');
    if (/Error in "|attempt to index|Unterminated JSON/.test(log)) throw new Error('启动日志存在 Lua 异常');
    if (/RNG Start Seed:.*\[Continue, 1\]/.test(log) && /Room .*\(Start Room\)/.test(log)) {
      return {status: 'PASS', keys, screenshots: 0, continued: true, window};
    }
    const state = await sky.get_window_state({window, include_screenshot: false, include_text: true});
    window = state.window;
    await sky.press_key({window, key: 'Return'});
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    keys.push('Return');
    await sleep(step === 3 ? 2400 : 1800);
  }
  const log = await fs.readFile(logPath, 'utf8');
  if (!/RNG Start Seed:.*\[Continue, 1\]/.test(log) || !/Room .*\(Start Room\)/.test(log)) {
    throw new Error('已校准的四次确认后没有继续局日志；停止输入，需检查一个失败截图');
  }
  return {status: 'PASS', keys, screenshots: 0, continued: true, window};
}
