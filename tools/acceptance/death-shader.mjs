/** 死亡 Shader 实机取证；复用 sky 与 Steam F12，输出待人工复核的真实图片。 */
import fs from 'node:fs/promises';
import path from 'node:path';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function* runDeathShaderAcceptance({sky, window, logPath, screenshotDir, outputDir, version}) {
  await fs.mkdir(outputDir, {recursive: false});
  const result = {status: 'FAIL', version, native: 'NOT_CHECKED', screenshots: [], checks: [], visual: 'NOT_RUN'};
  const offset = (await fs.readFile(logPath, 'utf8')).length;
  const log = async () => (await fs.readFile(logPath, 'utf8')).slice(offset);
  const key = async key => {
    await sky.press_key({window, key});
    window = (await sky.get_window_state({window, include_screenshot:false, include_text:true})).window;
    await sleep(200);
  };
  const waitLog = async needle => {
    const deadline = Date.now() + 15000;
    while(Date.now() < deadline) { if((await log()).includes(needle)) return; await sleep(150); }
    throw new Error('Missing live evidence: ' + needle);
  };
  const files = async () => {
    const entries = await fs.readdir(screenshotDir, {withFileTypes:true});
    return new Map(await Promise.all(entries.filter(e=>e.isFile() && /\.jpg$/i.test(e.name)).map(async e=>{
      const file=path.join(screenshotDir,e.name), stat=await fs.stat(file);
      return [file, `${stat.mtimeMs}:${stat.size}`];
    })));
  };
  const capture = async label => {
    await sleep(1100);
    const before=await files();
    await key('F12');
    let stable;
    const deadline=Date.now()+8000;
    while(Date.now()<deadline) {
      const changed=[...await files()].filter(([file,stamp])=>before.get(file)!==stamp);
      if(changed.length>1) throw new Error('Ambiguous concurrent screenshots');
      if(changed.length===1) {
        const [file,stamp]=changed[0];
        if(stable===`${file}:${stamp}`) {
          const name=`${result.screenshots.length}-${label}.jpg`;
          await fs.copyFile(file,path.join(outputDir,name)); result.screenshots.push(name); return;
        }
        stable=`${file}:${stamp}`;
      }
      await sleep(150);
    }
    throw new Error('No fresh Steam screenshot: '+label);
  };
  try {
    if(window.title!=='Binding of Isaac: Repentance+ v1.9.7.20') throw new Error('Uncalibrated runtime');
    if(!(await fs.readFile(logPath,'utf8')).includes(version)) throw new Error('Expected Mod version not loaded');
    await key('F9');
    await waitLog('START active=true continued=false');
    await waitLog('NATIVE pause=false death=false'); result.native='ABSENT';
    yield {phase:'seed', native:result.native};
    await key('F6'); await capture('alive-menu'); await key('F6');
    yield {phase:'alive-menu'};
    await key('F7'); await waitLog('DEATH requested via TakeDamage'); await waitLog('END gameOver=true');
    result.checks.push('real damage path reached Game Over; no spawn command');
    await sleep(2000); await capture('death');
    yield {phase:'death'};
    await key('F6'); await capture('death-menu');
    yield {phase:'death-menu'};
    await key('F6'); await capture('death-restored');
    yield {phase:'death-restored'};
    await key('F6'); await key('F9'); await sleep(1500); await capture('new-run');
    yield {phase:'new-run'};
    await key('F6'); await capture('new-run-menu'); await key('F6');
    const delta=await log();
    if((delta.match(/START active=true continued=false/g)||[]).length!==2) throw new Error('New-run boundary missing');
    if(/ERR\]|Lua Error|stack traceback/i.test(delta)) throw new Error('Lua error in live log');
    result.checks.push('two fixed-seed runs loaded without native exports or Lua error');
    result.status='AWAITING_VISUAL_REVIEW';
  } catch(error) {result.error=error.message;}
  finally {
    await fs.writeFile(path.join(outputDir,'game-delta.log'),await log());
    await fs.writeFile(path.join(outputDir,'result.json'),JSON.stringify(result,null,2));
  }
  return result;
}
