/** 配合只读 j510-acceptance-probe，测量真实游戏帧和渲染帧。 */
import fs from 'node:fs/promises';
import path from 'node:path';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function runJ510PauseAcceptance({sky, window, logPath, outputDir, expectedTitle = 'Binding of Isaac: Repentance+ v1.9.7.19'}) {
  await fs.mkdir(outputDir, {recursive: false});
  const result = {status: 'FAIL', phases: []};
  const sample = async owned => {
    const before = (await fs.readFile(logPath, 'utf8')).length;
    await sleep(2300);
    const delta = (await fs.readFile(logPath, 'utf8')).slice(before);
    const samples = [...delta.matchAll(/\[J510Acceptance\] render=(\d+) game=(\d+) paused=(true|false) owned=(true|false)/g)]
      .map(m => ({render: Number(m[1]), game: Number(m[2]), paused: m[3] === 'true', owned: m[4] === 'true'}));
    result.phases.push({owned, samples});
    if (samples.length < 2 || samples.some(s => s.owned !== owned || s.paused !== owned)) throw new Error('采样数量或暂停所有权不符');
    if (samples.at(-1).render <= samples[0].render) throw new Error('渲染帧没有继续');
    if (owned ? samples.some(s => s.game !== samples[0].game) : samples.at(-1).game <= samples[0].game) {
      throw new Error(owned ? '暂停时游戏帧仍在推进' : '关闭后游戏帧未恢复');
    }
  };
  const toggle = async () => {
    await sky.press_key({window, key: 'F6'});
    window = (await sky.get_window_state({window, include_screenshot: false, include_text: true})).window;
    await sleep(250);
  };
  try {
    if (window.title !== expectedTitle) throw new Error('运行时不符');
    await sample(true);
    await toggle(); await sample(false);
    await toggle(); await sample(true);
    result.status = 'PASS';
  } catch(error) { result.error = error.message; }
  result.finishedAt = new Date().toISOString();
  await fs.writeFile(path.join(outputDir, 'result.json'), JSON.stringify(result, null, 2));
  return result;
}
