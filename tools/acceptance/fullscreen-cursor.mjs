/** 已校准场景的批量实机验收。由 Codex node_repl 注入 sky，不依赖模型逐帧判断。 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import crypto from 'node:crypto';

const execute = promisify(execFile);
const directory = path.dirname(fileURLToPath(import.meta.url));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const fail = message => { throw new Error(message); };

function cursorValue(data) {
  const text = data.toString('utf8');
  const values = [...text.matchAll(/^fullscreenCursorEnabled=([^\r\n]*)/gm)];
  if (values.length === 0) return true; // 旧存档与生产代码一致，缺省开启。
  if (values.length !== 1 || !['0', '1'].includes(values[0][1])) fail('存档须包含唯一有效光标字段');
  return values[0][1] === '1';
}

function withoutCursor(data) {
  return data.toString('utf8').replace(/^(?:fullscreenCursorEnabled|version)=[^\r\n]*\r?\n?/gm, '');
}

export async function runCursorAcceptance({sky, config, onProgress = () => {}, inspectFrame}) {
  const result = {status: 'BLOCKED', runtime: 'NOT_VERIFIED', expectedRuntime: 'Repentance+ v1.9.7.17', language: 'zh',
    mode: 'borderless-fullscreen', checks: [], screenshots: [], restoration: 'not-needed',
    limitations: ['仅支持已校准的中文设置第二页和 2561×1440 Steam 截图',
      '不判断系统光标、独占全屏、真实手柄或其他运行时']};
  let window, originalSave, originalOptions, mutated = false, lastFrame, originalValue, loadedVersion;
  const assert = (value, message) => { if (!value) fail(message); };
  const check = label => { result.checks.push(label); onProgress(label); };
  const timeoutMs = config.timeoutMs ?? 8000;
  const settleMs = config.settleMs ?? 400;
  const inspect = inspectFrame ?? (async file => {
    const {stdout} = await execute(config.pythonPath, [path.join(directory, 'inspect_cursor_frame.py'), file],
      {timeout: 10000, windowsHide: true});
    return JSON.parse(stdout);
  });
  // 不复用任何先前运行的输出目录，防止旧图片被当作本次通过证据。
  await fs.mkdir(config.outputDir, {recursive: false});
  const refresh = async () => {
    const state = await sky.get_window_state({window, include_screenshot: false, include_text: true});
    window = state.window;
  };
  const key = async value => { await sky.press_key({window, key: value}); await refresh(); };
  const screenshotFiles = async () => {
    const entries = await fs.readdir(config.screenshotDir, {withFileTypes: true});
    return new Map(await Promise.all(entries.filter(e => e.isFile() && /\.jpg$/i.test(e.name)).map(async e => {
      const file = path.join(config.screenshotDir, e.name), stat = await fs.stat(file);
      return [file, `${stat.mtimeMs}:${stat.size}`];
    })));
  };
  const capture = async label => {
    // Steam 的文件名只有秒精度，跨采样至少留出一秒，且必须观察到新文件/新时间戳。
    await sleep(config.captureIntervalMs ?? 1100);
    const before = await screenshotFiles();
    await key(config.screenshotKey ?? 'F12');
    const deadline = Date.now() + timeoutMs;
    let stable;
    while (Date.now() < deadline) {
      const after = await screenshotFiles();
      const changed = [...after].filter(([file, stamp]) => before.get(file) !== stamp);
      assert(changed.length <= 1, '截图来源不唯一；停止，避免使用其他窗口或并发截图');
      if (changed.length === 1) {
        const [file, stamp] = changed[0];
        if (stable === `${file}:${stamp}`) {
          const target = path.join(config.outputDir, `${result.screenshots.length}-${label}.jpg`);
          await fs.copyFile(file, target);
          const observation = await inspect(target);
          lastFrame = observation;
          result.screenshots.push({file: path.basename(target), observation});
          return observation;
        }
        stable = `${file}:${stamp}`;
      }
      await sleep(150);
    }
    fail('Steam 截图超时；未读取到本次新画面');
  };
  const verifySave = async expected => {
    const data = await fs.readFile(config.savePath);
    assert(cursorValue(data) === expected, '开关持久化值与预期不一致');
    assert(withoutCursor(data) === withoutCursor(originalSave), '光标切换改动了其他存档字段');
    assert(hash(await fs.readFile(config.optionsPath)) === hash(originalOptions), '游戏配置发生变化');
  };
  const verifyRestored = async () => {
    await verifySave(originalValue);
    const data = await fs.readFile(config.savePath);
    if (data.equals(originalSave)) return 'restored-through-ui';
    assert(data.toString().includes(`version=${loadedVersion}\n`), '恢复后版本字段不符合当前 Mod');
    assert(/^fullscreenCursorEnabled=[01]\r?$/m.test(data.toString()), '恢复后缺少光标字段');
    return 'restored-with-save-migration';
  };
  const toggle = async expected => {
    assert(lastFrame?.settingsPage, '当前位置不是已校准的设置页，禁止点击');
    // 坐标源自已校准页面的空白卡片区域；每次点击后都重新采集并验证。
    mutated = true;
    await sky.click({window, x: 900, y: 420});
    await refresh();
    await sleep(settleMs);
    await verifySave(expected);
    const frame = await capture(expected ? 'enabled' : 'disabled');
    assert(frame.settingsPage, '切换后离开了设置页');
    assert(expected ? frame.cursorVisible : frame.cursorAbsent, '保存成功但实际光标画面不符合预期');
    check(expected ? '开启：保存、白色填充和黑色描边通过' : '关闭：保存及无补画光标通过');
  };
  try {
    const root = path.resolve(directory, '../..');
    const source = await fs.readFile(path.join(root, 'workshop-mod/main.lua'));
    assert(hash(await fs.readFile(config.installedMain)) === hash(source),
      '实机加载副本与当前中文源码不一致，请先安装已验证候选');
    const log = await fs.readFile(config.logPath, 'utf8');
    assert(/1\.9\.7\.17/.test(log) && /Repentance\+/.test(log), '日志与已校准运行时不符');
    const version = source.toString().match(/local VERSION = "([^"]+)"/)[1];
    loadedVersion = version;
    assert(log.includes(`[Isaac Chinese Console] v${version};`), '游戏日志未证明当前源码版本已加载');
    const slots = [...log.matchAll(/Loading PersistentGameData[^\n]*persistentgamedata([123])\.dat/g)];
    assert(slots.length > 0 && path.basename(config.savePath) === `save${slots.at(-1)[1]}.dat`,
      '提供的 Mod 存档槽与当前游戏日志不一致');
    result.runtime = result.expectedRuntime;
    assert(!/Error in "|attempt to index|Unterminated JSON/.test(log), '游戏日志已有回调错误，先排查再验收');
    const candidates = (await sky.list_windows()).filter(w =>
      w.app.toLowerCase().replaceAll('\\', '/').includes(config.gameExe.toLowerCase().replaceAll('\\', '/')));
    assert(candidates.length === 1, `游戏窗口应恰有一个，实际 ${candidates.length}`);
    window = candidates[0];
    await refresh();
    originalSave = await fs.readFile(config.savePath);
    originalOptions = await fs.readFile(config.optionsPath);
    originalValue = cursorValue(originalSave);
    assert(/^Fullscreen=1\r?$/m.test(originalOptions.toString()), '请先切换到全屏');
    assert(/^UseExclusiveFullscreen=0\r?$/m.test(originalOptions.toString()), '本场景未校准独占全屏');
    await fs.writeFile(path.join(config.outputDir, 'original-save.bin'), originalSave, {flag: 'wx'});
    await fs.writeFile(path.join(config.outputDir, 'original-options.bin'), originalOptions, {flag: 'wx'});
    const preflight = await capture('preflight');
    assert(preflight.settingsPage, '起始页面不符：请打开中文控制台 → 设置 → 第 2 页');
    check('窗口、版本、副本、配置和起始页面检查通过');
    result.status = 'FAIL';
    await toggle(!originalValue);
    await toggle(originalValue);
    result.restoration = await verifyRestored();
    check(result.restoration === 'restored-through-ui' ? '原开关值、完整存档字节和游戏配置恢复通过'
      : '原开关值及其他存档字段恢复；仅允许版本更新和缺省光标字段迁移');
    const finalLog = await fs.readFile(config.logPath, 'utf8');
    assert(!/Error in "|attempt to index|Unterminated JSON/.test(finalLog), '验收中出现游戏回调错误');
    await fs.writeFile(path.join(config.outputDir, 'game.log'), finalLog);
    result.status = 'PASS';
  } catch (error) {
    result.error = String(error.message ?? error);
    if (mutated) {
      result.status = 'FAIL';
      try {
        // 出错后重新观测；仅在页面仍正确、其余数据未变时通过 UI 恢复。
        const data = await fs.readFile(config.savePath);
        assert(withoutCursor(data) === withoutCursor(originalSave), '存在额外数据变化，停止自动恢复');
        if (cursorValue(data) !== originalValue) {
          const frame = await capture('before-recovery');
          assert(frame.settingsPage, '页面未知，停止自动恢复');
          await toggle(originalValue);
        }
        result.restoration = await verifyRestored();
      } catch (restoreError) {
        result.restoration = 'NEEDS_RECOVERY';
        result.restorationError = String(restoreError.message ?? restoreError);
      }
    }
  } finally {
    result.finishedAt = new Date().toISOString();
    await fs.writeFile(path.join(config.outputDir, 'result.json'), JSON.stringify(result, null, 2));
  }
  return result;
}
