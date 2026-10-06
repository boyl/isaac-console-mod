# tools/nexus

在**用户已登录**的可见浏览器里执行 Nexus Mods 上传的编排脚本。Nexus 没有面向普通作者的上传 API，所以这里用 Chrome DevTools Protocol 驱动浏览器，并在无法可靠自动化的地方停下来要求人工完成。

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
