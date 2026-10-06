#!/usr/bin/env node
// Nexus Mods upload assistant.
//
// It never logs in, never solves a challenge and never clicks "publish" on its own: it drives an
// already-signed-in browser over CDP, fills what it can prove, and reports what still needs a
// human. Page copy is read from NEXUS_UPLOAD.md so the Markdown stays the single source of truth.
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { Cdp, findPageTarget } from './nexus-cdp.mjs';

const GAME_URL = 'https://www.nexusmods.com/games/thebindingofisaacrebirth';
const NEXT_UPLOAD_URL = 'https://next.nexusmods.com/games/thebindingofisaacrebirth?uploadMod=true';
const CLOUDFLARE_TITLES = /请稍候|Just a moment|Attention Required|Checking your browser/i;

const args = parseArgs(process.argv.slice(2));
const step = args.step || 'inspect';
const port = Number(args.port || 9222);
const repoRoot = resolve(args.repo || process.cwd());
const packageRoot = resolve(args.packages || join(repoRoot, 'dist', 'nexus-packages'));
const stamp = new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '');
const evidenceRoot = resolve(args.evidence || join(packageRoot, 'browser-evidence', stamp));
mkdirSync(evidenceRoot, { recursive: true });

const report = { step, startedAt: new Date().toISOString(), evidenceRoot, events: [] };
function note(line) {
  report.events.push(line);
  console.log(line);
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith('--')) parsed[key] = true;
    else { parsed[key] = next; index += 1; }
  }
  return parsed;
}

function sectionCopy(markdown, heading) {
  const index = markdown.indexOf(heading);
  if (index < 0) throw new Error(`NEXUS_UPLOAD.md is missing the section: ${heading}`);
  const match = markdown.slice(index).match(/```[a-z]*\r?\n([\s\S]*?)```/);
  if (!match) throw new Error(`NEXUS_UPLOAD.md has no fenced copy block after: ${heading}`);
  return match[1].replace(/\r\n/g, '\n').trimEnd();
}

function loadCopy() {
  const uploadDoc = join(repoRoot, 'NEXUS_UPLOAD.md');
  if (!existsSync(uploadDoc)) throw new Error(`Missing ${uploadDoc}`);
  const markdown = readFileSync(uploadDoc, 'utf8');
  return {
    summaryEn: sectionCopy(markdown, '**英文（Summary，单行）**'),
    summaryZh: sectionCopy(markdown, '**中文（可选第二行）**'),
    bodyEn: sectionCopy(markdown, '### 4.1 英文正文'),
    bodyZh: sectionCopy(markdown, '### 4.2 中文正文'),
  };
}

function loadPackages() {
  const files = [];
  for (const name of readdirSync(packageRoot)) {
    if (!name.endsWith('-BUILD-INFO.json')) continue;
    const info = JSON.parse(readFileSync(join(packageRoot, name), 'utf8'));
    files.push({
      variant: info.Language,
      slug: name.replace(/-BUILD-INFO\.json$/, ''),
      version: info.Version,
      registerName: info.RegisterName,
      directory: info.Directory,
      archivePath: info.Archive.Path,
      archiveName: info.Archive.Name,
      sha256: info.Archive.Sha256,
      fileCount: info.CandidateFileCount,
      sourceCommit: info.SourceCommit,
    });
  }
  files.sort((left, right) => (left.variant === 'zh' ? -1 : 1));
  if (files.length === 0) throw new Error(`No *-BUILD-INFO.json found in ${packageRoot}`);
  return files;
}

async function saveScreenshot(cdp, name) {
  const target = join(evidenceRoot, name);
  const { bytes } = await cdp.screenshot(target);
  writeFileSync(target, bytes);
  note(`SCREENSHOT=${target} bytes=${bytes.length}`);
  return target;
}

// Nexus fronts the page with a Cookiebot banner that would swallow the first click of any step.
async function dismissConsent(cdp) {
  const clicked = await cdp.evaluate(`(() => {
    const byId = document.getElementById('CybotCookiebotDialogBodyButtonDecline');
    if (byId) { byId.click(); return 'decline'; }
    const button = [...document.querySelectorAll('button')].find((el) => /^(deny|allow all)$/i.test((el.innerText || '').trim()));
    if (button) { button.click(); return (button.innerText || '').trim(); }
    return '';
  })()`);
  if (clicked) {
    note(`CONSENT_DISMISSED=${clicked}`);
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  return clicked;
}

function writeEvidence(name, payload) {
  const path = join(evidenceRoot, name);
  writeFileSync(path, typeof payload === 'string' ? payload : `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  return path;
}

const DUMP_EXPRESSION = `(() => {
  const visible = (el) => {
    const style = getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };
  const labelFor = (el) => {
    if (el.labels && el.labels.length) return [...el.labels].map((l) => l.innerText.trim()).join(' | ');
    const aria = el.getAttribute('aria-label');
    if (aria) return aria;
    const wrapper = el.closest('label');
    return wrapper ? wrapper.innerText.trim().slice(0, 80) : '';
  };
  const nodes = [...document.querySelectorAll('input, textarea, select, button, a[href]')].filter(visible);
  return {
    url: location.href,
    title: document.title,
    controls: nodes.filter((el) => ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)).map((el) => ({
      tag: el.tagName,
      type: el.type || '',
      name: el.name || '',
      id: el.id || '',
      placeholder: el.placeholder || '',
      label: labelFor(el),
      valueLength: (el.value || '').length,
      accept: el.accept || '',
      multiple: !!el.multiple,
    })),
    buttons: nodes.filter((el) => el.tagName === 'BUTTON').map((el) => (el.innerText || el.value || '').trim().slice(0, 60)).filter(Boolean),
    links: nodes.filter((el) => el.tagName === 'A').map((el) => ({ text: (el.innerText || '').trim().slice(0, 60), href: el.href })).filter((link) => link.text || link.href),
  };
})()`;

async function readPage(cdp) {
  return cdp.evaluate(DUMP_EXPRESSION);
}

async function assertLoaded(cdp, { timeoutMs = 240000 } = {}) {
  try {
    await cdp.waitFor({ timeoutMs, description: 'a browser page that is not a Cloudflare challenge' },
      `document.readyState === 'complete' && !${CLOUDFLARE_TITLES}.test(document.title)`);
  }
  catch (error) {
    const state = await cdp.evaluate('({ title: document.title, url: location.href })');
    if (CLOUDFLARE_TITLES.test(state.title)) {
      note(`MANUAL_REQUIRED=浏览器停在 Cloudflare 验证页（title=${state.title}）。请在窗口里完成验证，然后重新运行同一步骤。`);
    }
    throw error;
  }
  const page = await readPage(cdp);
  note(`PAGE title=${page.title} url=${page.url}`);
  return page;
}

async function signedIn(cdp) {
  return cdp.evaluate(`(() => {
    const text = document.body.innerText || '';
    return {
      signIn: /(^|\\n)\\s*(log in|sign in)\\s*($|\\n)/i.test(text),
      signOut: /sign out/i.test(text),
      profileZero: !!document.querySelector('a[href$="/users/0"]'),
      myAccount: !!document.querySelector('a[href*="users/myaccount"]'),
    };
  })()`);
}

const SET_VALUE_EXPRESSION = (selectorIndex, value) => `(() => {
  const nodes = [...document.querySelectorAll('input, textarea')].filter((el) => getComputedStyle(el).display !== 'none');
  const el = nodes[${selectorIndex}];
  if (!el) return false;
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
  el.focus();
  setter.call(el, ${JSON.stringify(value)});
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'a' }));
  el.dispatchEvent(new Event('blur', { bubbles: true }));
  return (el.value || '').length;
})()`;

async function fillByHints(cdp, hints, value, label) {
  const page = await readPage(cdp);
  const controls = page.controls.filter((control) => ['INPUT', 'TEXTAREA'].includes(control.tag));
  for (const [index, control] of controls.entries()) {
    const haystack = `${control.name} ${control.id} ${control.placeholder} ${control.label}`.toLowerCase();
    if (hints.some((hint) => hint.test(haystack))) {
      const written = await cdp.evaluate(SET_VALUE_EXPRESSION(index, value));
      if (written) {
        note(`FILLED=${label} control=${control.tag.toLowerCase()}[${control.name || control.id || control.placeholder || index}] chars=${written}`);
        return true;
      }
    }
  }
  note(`MISSING=${label}（本轮未找到可安全写入的控件，需要人工填写）`);
  return false;
}

async function openUploadPage(cdp) {
  await dismissConsent(cdp);
  let page = await readPage(cdp);
  if (/uploadMod=true/i.test(page.url)) return page;
  const link = (page.links || []).find((entry) => /upload/i.test(entry.href) || /upload a mod|add a mod/i.test(entry.text));
  if (link && /^https?:/i.test(link.href)) {
    note(`UPLOAD_LINK=${link.href} text="${link.text}"`);
    await cdp.evaluate(`(() => { const a = [...document.querySelectorAll('a')].find((el) => el.href === ${JSON.stringify(link.href)}); if (a) { a.click(); return true; } return false; })()`);
    await new Promise((resolve) => setTimeout(resolve, 6000));
    page = await readPage(cdp);
    if (/upload/i.test(page.url) && page.controls.length > 0) return page;
  }
  // The 2026 upload flow lives on the next.nexusmods.com React app; the legacy
  // /mods/upload path only redirects back to the game page.
  note(`NAVIGATE_UPLOAD=${NEXT_UPLOAD_URL}`);
  await cdp.navigate(NEXT_UPLOAD_URL);
  await cdp.waitFor({ timeoutMs: 90000, intervalMs: 1000, description: 'the upload form to render' },
    `document.querySelectorAll('input, textarea, select').length > 0 || /(log in|sign in)/i.test(document.body.innerText)`);
  await new Promise((resolve) => setTimeout(resolve, 3000));
  return readPage(cdp);
}

async function clickByText(cdp, pattern, { exclude = null } = {}) {
  const clicked = await cdp.evaluate(`(() => {
    const pattern = ${pattern};
    const exclude = ${exclude ? exclude : 'null'};
    const nodes = [...document.querySelectorAll('a, button')];
    const target = nodes.find((el) => {
      const text = (el.innerText || el.value || '').trim();
      if (!text || text.length > 60) return false;
      if (!pattern.test(text)) return false;
      if (exclude && exclude.test(text)) return false;
      const style = getComputedStyle(el);
      return style.display !== 'none' && style.visibility !== 'hidden';
    });
    if (!target) return '';
    target.click();
    return (target.innerText || target.value || '').trim();
  })()`);
  if (clicked) note(`CLICKED="${clicked}"`);
  return clicked;
}

async function stepInspect(cdp) {
  await cdp.navigate(GAME_URL);
  const page = await assertLoaded(cdp);
  await dismissConsent(cdp);
  const auth = await signedIn(cdp);
  note(`LOGIN signIn=${auth.signIn} signOut=${auth.signOut} myAccount=${auth.myAccount} profileZero=${auth.profileZero}`);
  writeEvidence('inspect-dump.json', page);
  await saveScreenshot(cdp, 'inspect-game-page.png');
  const upload = await openUploadPage(cdp);
  const uploadDump = await readPage(cdp);
  writeEvidence('inspect-upload-dump.json', uploadDump);
  await saveScreenshot(cdp, 'inspect-upload-page.png');
  note(`CONTROLS=${uploadDump.controls.length} BUTTONS=${uploadDump.buttons.length}`);
  for (const control of uploadDump.controls) {
    note(`CONTROL ${control.tag}${control.type ? `[${control.type}]` : ''} name="${control.name}" id="${control.id}" label="${control.label}" placeholder="${control.placeholder}"`);
  }
  for (const button of uploadDump.buttons) note(`BUTTON "${button}"`);
  for (const link of uploadDump.links.slice(0, 40)) note(`LINK "${link.text}" ${link.href}`);
  return uploadDump;
}

async function stepFill(cdp) {
  const page = await openUploadPage(cdp);
  const auth = await signedIn(cdp);
  if (auth.signIn && !auth.account) {
    note('MANUAL_REQUIRED=请在打开的浏览器窗口里登录 Nexus，登录后重新运行 -Step fill。');
    return false;
  }
  if (!page.controls.some((control) => ['INPUT', 'TEXTAREA'].includes(control.tag))) {
    note('MANUAL_REQUIRED=当前页面没有可见表单控件；请确认已进入 “Upload a mod / Add a mod” 表单。');
    writeEvidence('fill-dump.json', page);
    await saveScreenshot(cdp, 'fill-no-form.png');
    return false;
  }
  const copy = loadCopy();
  const packages = loadPackages();
  const primary = packages[0];
  const title = `Isaac Chinese Console + Console UI (中文 / English) ${primary.version}`;

  await fillByHints(cdp, [/name$/, /^name/, /mod.?name/, /title/], title, 'mod name / title');
  await fillByHints(cdp, [/summary/, /short.?desc/, /description.?short/], copy.summaryEn, 'summary (English)');

  const toggled = await clickByText(cdp, `/^\\[\\s*\\]?\\s*$/`) || await clickByText(cdp, /bbcode|source code|switch to source/i);
  if (toggled) note('BBCODE_TOGGLE=1');
  const bodyFilled = await fillByHints(cdp, [/description/, /desc/, /body/, /text/], `${copy.bodyEn}\n\n[line]\n\n${copy.bodyZh}`, 'description body (EN + ZH)');
  if (!bodyFilled) note('MANUAL_REQUIRED=说明正文需要在编辑器里人工粘贴（NEXUS_UPLOAD.md 第 4 节）。');

  writeEvidence('fill-dump.json', await readPage(cdp));
  await saveScreenshot(cdp, 'fill-after.png');
  return true;
}

async function stepFiles(cdp) {
  let page = await openUploadPage(cdp);
  const fileInputCount = await cdp.evaluate('document.querySelectorAll("input[type=file]").length');
  if (fileInputCount === 0) {
    const opened = await clickByText(cdp, /files|manage files|upload file|file manager/i);
    if (opened) {
      await new Promise((resolve) => setTimeout(resolve, 3000));
      page = await readPage(cdp);
    }
  }
  const count = await cdp.evaluate('document.querySelectorAll("input[type=file]").length');
  const packages = loadPackages();
  const archives = packages.map((entry) => entry.archivePath);
  if (count === 0) {
    note('MANUAL_REQUIRED=页面没有 input[type=file]，请在浏览器里把两个 zip 拖入文件区：');
    for (const archive of archives) note(`  ${archive}`);
    writeEvidence('files-dump.json', page);
    await saveScreenshot(cdp, 'files-manual.png');
    return false;
  }
  await cdp.setFileInputs(0, archives);
  note(`FILES_SET=${archives.length} input[0] stage=pre-upload`);
  await new Promise((resolve) => setTimeout(resolve, 5000));
  writeEvidence('files-dump.json', await readPage(cdp));
  await saveScreenshot(cdp, 'files-after.png');
  return true;
}

async function stepImages(cdp) {
  const opened = await clickByText(cdp, /images|gallery|screenshots/i);
  if (!opened) note('NO_IMAGES_TAB=1');
  await new Promise((resolve) => setTimeout(resolve, 3000));
  const images = [
    join(repoRoot, 'workshop-mod', 'preview.png'),
    join(repoRoot, 'workshop-mod-en', 'preview.png'),
  ];
  const count = await cdp.evaluate('document.querySelectorAll("input[type=file]").length');
  if (count === 0) {
    note('MANUAL_REQUIRED=图片区没有 input[type=file]，请人工上传：');
    for (const image of images) note(`  ${image}`);
    await saveScreenshot(cdp, 'images-manual.png');
    return false;
  }
  await cdp.setFileInputs(0, images);
  note(`IMAGES_SET=${images.length}`);
  await new Promise((resolve) => setTimeout(resolve, 5000));
  writeEvidence('images-dump.json', await readPage(cdp));
  await saveScreenshot(cdp, 'images-after.png');
  return true;
}

async function stepPublish(cdp) {
  const page = await readPage(cdp);
  writeEvidence('publish-before-dump.json', page);
  await saveScreenshot(cdp, 'publish-before.png');
  if (!args['confirm-publish']) {
    note('PUBLISH_NOT_CLICKED=1（未传 -ConfirmPublish，页面保持在上传/预览状态，等待人工确认）');
    return false;
  }
  const clicked = await clickByText(cdp, /publish|submit/i, { exclude: /delete|remove|back|cancel/i });
  if (!clicked) {
    note('MANUAL_REQUIRED=没有找到发布按钮，请人工确认页面状态。');
    return false;
  }
  await new Promise((resolve) => setTimeout(resolve, 8000));
  writeEvidence('publish-after-dump.json', await readPage(cdp));
  await saveScreenshot(cdp, 'publish-after.png');
  note('PUBLISH_CLICKED=1');
  return true;
}

const STEPS = { inspect: stepInspect, fill: stepFill, files: stepFiles, images: stepImages, publish: stepPublish };

async function main() {
  const handler = STEPS[step];
  if (!handler) throw new Error(`Unknown step: ${step}`);
  const target = await findPageTarget(port);
  const cdp = await Cdp.connect(target.webSocketDebuggerUrl);
  note(`CDP_TARGET=${target.url}`);
  let ok = true;
  try {
    ok = await handler(cdp);
  }
  finally {
    report.finishedAt = new Date().toISOString();
    report.result = ok ? 'ok' : 'manual';
    writeEvidence('report.json', report);
    note(`EVIDENCE_DIR=${evidenceRoot}`);
    note(`STEP_RESULT=${report.result}`);
  }
  process.exit(ok ? 0 : 2);
}

main().catch((error) => {
  report.error = error.message;
  report.result = 'error';
  writeEvidence('report.json', report);
  console.error(`ERROR ${error.message}`);
  console.error(`EVIDENCE_DIR=${evidenceRoot}`);
  process.exit(1);
});
