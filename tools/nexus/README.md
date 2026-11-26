# tools/nexus

Nexus 已开放官方 Upload API，现有项目与文件更新优先使用该 API，参考 https://api-docs.nexusmods.com/ 和 https://github.com/Nexus-Mods/upload-action。项目与文件链 ID 见根目录 NEXUS_UPLOAD.md。

本目录的旧网页编排脚本仅作 API 无法覆盖操作的后备，在**用户已登录**的可见浏览器里执行。

`publish-files.ps1` 是既有官方 API 发布流程的可复用入口。必须先通过 `verify-nexus-packages.ps1`，再提供 `Language`、从 API 核对的 `PreviousVersionId`、已推送的 `ExpectedCommit`、本次专用 `OutputDirectory` 和不超过 255 字的 `ChangeNotes`。默认只读预检；已获发布授权后传入 `-Publish`。密钥从仓库父目录约定文件直接读入内存，不放入参数或输出。

脚本检查源码提交、包哈希、Nexus 门禁、Mod 身份和文件链，沿用原文件链创建版本并归档旧版本。每个上传阶段写入语言回执；存在回执或目标版本时停止，必须先读取远端状态，不能盲目重传。API 返回新版本后仍须复核安全扫描、公开文件列表以及下载包内容。

## 前置条件

- 发布包已由 `tools/build-nexus-mod.ps1` 从**已推送**的提交生成（`dist/nexus-packages/*.zip` 与 `*-BUILD-INFO.json`）。
- Node 22 或更高版本（`node --version`）。脚本只用内置的 `fetch` 与全局 `WebSocket`，不需要安装任何依赖。
- Chrome 或 Edge。为了不动用户日常配置，脚本默认使用独立配置目录 `%LOCALAPPDATA%\dsh\nexus-browser-profile`，**首次运行时需要在该窗口里登录一次 Nexus**（会话会保留在这个配置目录里）。
- 必须提权运行：沙箱内 Chrome 会因 crashpad `OpenProcess: 拒绝访问 (0x5)` 立即退出。

## 用法

```powershell
# 1) 打开游戏分区页面，确认登录状态，并导出上传表单的控件快照
pwsh -NoLogo -NoProfile -File .\tools\nexus\invoke-nexus-upload.ps1 -Step inspect

# 2) 打开上传表单并填写标题/摘要/正文（正文取自 NEXUS_UPLOAD.md 第 4 节）
pwsh -NoLogo -NoProfile -File .\tools\nexus\invoke-nexus-upload.ps1 -Step fill

# 3) 上传两个 zip（Main Files）
pwsh -NoLogo -NoProfile -File .\tools\nexus\invoke-nexus-upload.ps1 -Step files

# 4) 上传页面图片
pwsh -NoLogo -NoProfile -File .\tools\nexus\invoke-nexus-upload.ps1 -Step images

# 5) 只有在人工确认无误后才点击发布（不传 -ConfirmPublish 时只做一次发布前截图）
pwsh -NoLogo -NoProfile -File .\tools\nexus\invoke-nexus-upload.ps1 -Step publish -ConfirmPublish
```

常用参数：`-PackageRoot`、`-ProfileRoot`、`-BrowserPath`、`-NodePath`、`-Port`（默认 9222）、`-CloseBrowser`。

## 行为约定

- 每个步骤都在 `dist/nexus-packages/browser-evidence/<时间戳>/` 写入截图、控件快照 JSON 和 `report.json`；控制台输出 `PAGE`、`FILLED`、`MISSING`、`MANUAL_REQUIRED`、`STEP_RESULT` 等行，便于回溯"到底填了什么、传了什么"。
- 页面结构变化、Cloudflare 挑战、二次验证、无法程序化设置的文件框，都会以 `MANUAL_REQUIRED` 停在原地并保持浏览器打开；已完成的部分不会被撤销，人工补完后可继续下一步。
- 端口上已有 CDP 实例时直接复用，不会另起浏览器；不会点击任何删除、移除或取消按钮；不传 `-ConfirmPublish` 时不会点击发布。
- 脚本不保存密码，也不读取浏览器 Cookie；登录完全由用户在窗口里完成。

## 页面文案来源

`nexus-upload.mjs` 从仓库根的 `NEXUS_UPLOAD.md` 解析摘要与正文（按固定小标题后的围栏代码块），因此页面文案只有一份来源，改文档即改上传内容。若标题小标题被改名，脚本会以"找不到段落"报错而不是静默跳过。
