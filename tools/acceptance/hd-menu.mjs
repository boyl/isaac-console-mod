/** 用只读日志核验菜单状态；只有明确选中高清字体设置时才允许确认。 */
import fs from 'node:fs/promises';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export function parseMenuState(log, prefix) {
  const lines = log.split(/\r?\n/).filter(line => line.includes(`${prefix} menu-state `));
  if (!lines.length) throw new Error('本次日志没有菜单状态记录');
  const signature = lines.at(-1).split('menu-state ')[1];
  const [open, pause, category, focus, page, selection, entry, input, style, capacity] = signature.split('|');
  return {signature, open: open === 'open', paused: pause === 'paused', category, focus,
    page: Number(page), selection: Number(selection), entry, input, style, capacity: Number(capacity)};
}

export function menuDriver({sky, window, logPath, prefix = '[Isaac Chinese Console]'}) {
  const read = async () => {
    const log = await fs.readFile(logPath, 'utf8');
    if (/Error in "|attempt to index|Unterminated JSON/.test(log)) throw new Error('游戏日志存在回调错误');
    return parseMenuState(log, prefix);
  };
  const press = async (key, allowConfirm = false) => {
    const before = await read();
    if (before.paused) throw new Error('游戏暂停，停止自动输入');
    if (key === 'Return' && (!allowConfirm || before.entry !== 'hd_font_toggle' || before.focus !== 'entries' || before.input !== 'none')) {
      throw new Error('未选中高清字体开关，禁止执行确认');
    }
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sky.press_key({window, key});
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    for (let i = 0; i < 15; i++) {
      await sleep(100);
      const after = await read();
      if (after.signature !== before.signature) return after;
    }
    throw new Error(`按键 ${key} 后没有预期状态变化；停止而不盲目重试`);
  };
  return {read, press,
    async toggleHD() { return press('Return', true); }
  };
}

/** 鼠标路径只支持实机校准的窗口；坐标从本次字体度量日志推导。 */
export async function toggleHDWithMeasuredMouse({sky, window, logPath, prefix = '[Isaac Chinese Console]'}) {
  const driver = menuDriver({sky, window, logPath, prefix});
  const log = await fs.readFile(logPath, 'utf8');
  const line = log.split(/\r?\n/).filter(l => l.includes(`${prefix} measured layout `)).at(-1);
  if (!line) throw new Error('缺少实测布局日志');
  const [w, h, body, title, pad, sidebar] = line.split('measured layout ')[1].split(' ')[0].split(':').map(Number);
  const pixels = {'488:260': [2442, 1304], '451:257': [2258, 1286]}[`${w}:${h}`];
  if (!pixels || pad !== 5) throw new Error('窗口不是已校准尺寸，禁止使用鼠标模板');
  let state = await driver.read();
  if (!state.open || state.paused || state.input !== 'none') throw new Error('菜单不是普通浏览状态');
  const hd = state.style === 'hd';
  const rows = 6;
  const categoryTop = 8 + body * 3 + pad * 4;
  const categoryRow = body + pad;
  const navHeight = body + pad * 2;
  const click = async (x, y) => {
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sky.click({window, x: Math.round(x * pixels[0] / w), y: Math.round(y * pixels[1] / h)});
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sleep(350);
    state = await driver.read();
    if (!state.open || state.paused) throw new Error('鼠标操作后菜单状态异常');
  };
  for (let i = 0; state.category !== 'input_settings' && i < 5; i++) {
    {
      const previous = state.category;
      await click(sidebar - 2 - navHeight / 2 + pad, categoryTop + rows * categoryRow + pad + navHeight / 2);
      if (state.category === previous) throw new Error('分类翻页没有生效');
    }
  }
  if (state.category !== 'input_settings') throw new Error('没有找到设置分类');
  const targetPage = Math.floor(9 / state.capacity) + 1;
  while (state.page < targetPage) {
    const previous = state.page;
    await click(w - 13 - navHeight / 2, 8 + Math.max(title, navHeight) + pad + navHeight / 2);
    if (state.category !== 'input_settings' || state.page !== previous + 1) throw new Error('设置翻页没有生效');
  }
  if (state.page !== targetPage) throw new Error('设置页码不符');
  // 两种字体使用同一经典布局；第十项只能是高清字体开关。
  await click(400, 81);
  if (state.entry !== 'hd_font_toggle' || state.style === (hd ? 'hd' : 'classic')) throw new Error('高清开关未按预期切换');
  return state;
}

/** 已校准起点为高清设置卡片；整组往返不会执行游戏命令。 */
export async function runHDToggleAcceptance({sky, window, logPath, savePath, optionsPath, outputDir, prefix}) {
  const result = {status: 'BLOCKED', screenshots: 0, checks: [], restoration: 'not-needed'};
  await fs.mkdir(outputDir, {recursive: false});
  const driver = menuDriver({sky, window, logPath, prefix});
  const original = await fs.readFile(savePath, 'utf8');
  const originalOptions = await fs.readFile(optionsPath);
  const strip = value => value.replace(/^hdFontEnabled=[01]\r?\n?/gm, '');
  let mutated = false;
  try {
    const initial = await driver.read();
    if (initial.entry !== 'hd_font_toggle' || initial.focus !== 'entries' || !initial.open || initial.paused) {
      throw new Error('起始位置不是高清字体设置卡片');
    }
    if (!/^hdFontEnabled=[01]$/m.test(original)) throw new Error('需要已保存的明确样式偏好');
    const initialOn = /^hdFontEnabled=1$/m.test(original);
    if ((initial.style === 'hd') !== initialOn) throw new Error('当前处于自动降级，不能作为往返视觉测试起点');
    result.status = 'FAIL';
    for (const enabled of [!initialOn, initialOn]) {
      mutated = true;
      await driver.toggleHD();
      await sleep(400);
      const state = await driver.read();
      if (state.style !== (enabled ? 'hd' : 'classic') || state.entry !== 'hd_font_toggle') {
        throw new Error('切换后的样式或选中条目不符');
      }
      if (state.page !== initial.page || state.selection !== initial.selection || state.capacity !== initial.capacity) {
        throw new Error('字体切换改变了分页或选中位置');
      }
      const saved = await fs.readFile(savePath, 'utf8');
      if (!saved.includes(`hdFontEnabled=${enabled ? 1 : 0}`) || strip(saved) !== strip(original)) {
        throw new Error('保存失败或其他字段发生变化');
      }
      result.checks.push({style: state.style, page: state.page, selection: state.selection, capacity: state.capacity});
    }
    if (await fs.readFile(savePath, 'utf8') !== original) throw new Error('往返后存档字节不同');
    if (!(await fs.readFile(optionsPath)).equals(originalOptions)) throw new Error('游戏配置发生变化');
    result.status = 'PASS';
    result.restoration = 'restored-through-ui';
  } catch (error) {
    result.error = error.message;
    if (mutated) result.restoration = 'NEEDS_REVIEW';
  }
  result.finishedAt = new Date().toISOString();
  await fs.writeFile(`${outputDir}/result.json`, JSON.stringify(result, null, 2));
  return result;
}
