# 全屏控制台光标验收脚本

后续优先运行脚本。稳定场景由程序判断并输出摘要，不需要模型逐张查看截图；只有校准和失败诊断才进行交互式操作。

## 批量源码与执行器验收

在仓库根目录用 PowerShell 7 运行，传入真实 Python 与 Node 可执行文件（不要使用 WindowsApps 的 Python 别名）：

```powershell
./tools/run-cursor-acceptance.ps1 -PythonPath '<python.exe>' -NodePath '<node.exe>'
```

自动运行现有双语回归、构建与候选包校验、执行器故障/恢复测试。默认输出 `dist/acceptance/<时间>/result.json` 和分项日志；也可以用 `-OutputDirectory` 指定一个尚不存在的目录。控制台只返回摘要，失败时查看日志。

此命令的 `liveGame=NOT_RUN` 明确表示尚未执行真实游戏，不能把执行器自测算成实机通过。

## 实机批量场景

`fullscreen-cursor.mjs` 使用 Codex 的 `@oai/sky` 注入真实鼠标操作和 Steam F12 截图；图片分析由 Python/Pillow 完成。它是可重复的 Codex 实机执行入口，不是从 Steam 启动游戏的独立无人值守程序。

本轮校准范围是 **中文 2.5.21、Repentance+ v1.9.7.17、无边框全屏、2561×1440 Steam 截图、设置第 2 页**。固定坐标只在页面模板和截图尺寸都匹配后使用，其他语言、布局或运行时必须先重新校准。

前置条件：

1. 已从验证候选安装中文 Mod；脚本核对安装的 `main.lua` 与当前中文源码字节一致。
2. 游戏处于安全房间，打开控制台“设置”第 2 页。不要在验收过程中同时操作游戏。
3. `Fullscreen=1`、`UseExclusiveFullscreen=0`；Steam F12 本地截图可用；当前游戏日志没有回调错误。
4. 提供准确的当前存档槽 `savePath`、运行时配置与日志、Steam 截图目录。旧存档缺少光标字段时按默认开启验收；已有字段必须唯一有效。

在 Codex `node_repl` 中导入并整组运行（修改示例中的绝对路径；配置中不保存账户信息）：

```javascript
var {sky} = await import('@oai/sky');
var {runCursorAcceptance} = await import('file:///<仓库绝对路径>/tools/acceptance/fullscreen-cursor.mjs');
var result = await runCursorAcceptance({
  sky,
  config: {
    gameExe: '<游戏目录>/isaac-ng.exe',
    installedMain: '<当前安装的中文 Mod>/main.lua',
    savePath: '<游戏目录>/data/isaac_chinese_console_workshop/save1.dat',
    optionsPath: '<Repentance+ 用户目录>/options.ini',
    logPath: '<Repentance+ 用户目录>/log.txt',
    screenshotDir: '<Steam>/userdata/<账户>/760/remote/250900/screenshots',
    pythonPath: '<实际 python.exe>',
    outputDir: '<已有父目录>/<本次新目录>'
  }
});
nodeRepl.write(JSON.stringify(result));
```

一次调用自动完成：唯一窗口/版本/安装副本检查 → 新截图确认起始页面 → 切换到相反值 → 存档及画面断言 → 恢复原值 → 存档字节及游戏配置哈希检查 → 日志检查 → 写入 `result.json`。正常情况下约十余秒，无需模型介入每个动作。开关原本为关时同样有效。

每次操作后刷新窗口状态；截图必须是本轮 F12 新产生且文件稳定的图片。旧截图、截图超时、页面不符、点击未生效、保存与画面不一致都不能判为通过。脚本不会盲目重试点击。

## 失败、恢复与证据边界

- `BLOCKED`：窗口、版本、副本、日志或起始页不满足条件，没有执行开关点击。
- `FAIL`：已开始验收但断言失败；保留图片与错误原因。
- `PASS`：本场景全部断言完成。
- `restoration=restored-through-ui`：原开关和完整存档已通过 UI 恢复并复核。
- `restoration=restored-with-save-migration`：旧存档已按当前版本保存；原开关和其他数据保持，仅允许版本更新与新增默认光标字段。
- `restoration=NEEDS_RECOVERY`：界面未知、额外数据变化或恢复失败。停止输入，先检查现场；不要在运行中的游戏外直接覆盖 SaveData。初始 `original-save.bin` 与 `original-options.bin` 仅作为本地恢复备份。

执行器不安装/卸载 Mod、不切换游戏运行时、不改 Options、不处理 Steam 云同步，也不会自动停用 GoodTrip 等其他 Mod。安装与测试环境准备仍遵循仓库已有候选、备份与恢复规则。这可避免每次验收自动修改用户整个游戏环境。

截图只能证明游戏内补画指针，不能证明系统光标是否可见或是否出现系统双光标。暂停、重开、Game Over 和手柄焦点由现有 Mock 覆盖，本脚本不把它们记录为实机通过。

输出包含本地存档备份，分享证据时只分享 `result.json`、必要截图和检查后的日志，不要打包恢复备份。历史模板是本项目实测设置页，仅用于页面校准，不包含玩家收藏/自定义命令。

## 维护约定

执行器只负责场景调度与副作用，`inspect_cursor_frame.py` 负责图像判断，现有 Mod 和输入架构不变。执行器测试用替身注入截图、丢失点击、画面故障与数据变化，防止错误页面点击、假阳性和恢复掩盖失败。

页面识别比较文字形状，兼容设置卡片选中与未选中的背景变化。`json-trace-probe.lua` 是独立临时 JSON 异常定位探针，只记录长度和调用栈、不吞异常；不得放入发布包，诊断后必须移除。

新增语言、布局或实机场景时，先采集实际参考画面并验证识别器，再新增明确断言；不能只扩大版本正则或缩放坐标后宣称支持。项目 `AGENTS.md` 已记录以后优先使用本入口。

高清字体启动与零截图往返验收入口：参见 ../../HD-FONT-VALIDATION.md。当前实机校准窗口为 2442×1304；错误状态停止，不复用光标场景的固定坐标。
