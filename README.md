# Isaac Console Mod

这是 The Binding of Isaac: Rebirth 游戏内控制台 Mod 的独立源仓库，与桌面版控制台项目分开维护。

## 可选原生暂停组件安装

[安装说明与目录结构示意](experiments/native-pause/AUTOLOAD-RELEASE.md#安装后的目录结构示意)包含原版和忏悔龙两种布局。插件必须位于实际 EXE 目录下的 scripts 子目录；请保留下载包 game-files 内的目录结构。

## 目录

- `workshop-mod/`：中文版正式源码，当前版本 `2.5.24`，Workshop ID `3776882944`。
- `workshop-mod-en/`：英文版正式源码，当前内部版本 `2.5.4-en.19`、metadata `2.5.4.19`，Workshop ID `3779128726`。
- `tests/workshop-mod/`：中英文 Lua Mock、冷启动回归和双语发布负载验证器。
- `tools/build-workshop-mod.ps1`：中英文显式允许列表构建脚本。
- `tools/build-nexus-mod.ps1`、`tools/verify-nexus-packages.ps1`：Nexus 发布包构建与整链路校验。
- `tools/nexus/`：在用户已登录的浏览器里执行 Nexus 网页上传的编排脚本（CDP）。
- `NEXUS_UPLOAD.md`：Nexus 页面字段、中英文文案、内容与授权检查、发布顺序与上传后核验清单。

两个语言版本共享功能设计和回归要求，但保持各自的 `RegisterMod`、目录、Workshop ID 和 SaveData 身份。用户只能同时启用其中一个版本。

## 构建候选

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\build-workshop-mod.ps1 -Language zh
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\build-workshop-mod.ps1 -Language en
```

输出位于 `dist/workshop-candidates/`。构建脚本仅复制允许文件，并校验预览图 SHA-256：

- 中文版：`E187031C27C032EB11DBD2943BC75A4067E2FEA250A155B8DB3B08F06CFDB7C9`
- 英文版：`D7378BB9951A72EFE3C112F30930719FB734E20D48C16A870E396326770BB26C`

开发目录中的预览图不得未经核对覆盖远端版本。

## 测试

全屏光标相关工作优先使用 `tools/run-cursor-acceptance.ps1 -PythonPath <python.exe> -NodePath <node.exe>` 批量验收；实机整组执行入口、起始条件与失败恢复见 [光标验收脚本](tools/acceptance/README.md)。该入口区分源码、执行器自测与真实游戏结果，后续不要将稳定流程默认拆成逐张截图对话。

使用 `tests/workshop-mod/run_all_tests.py` 作为中英文统一入口，两套 Lua Mock（含全屏光标矩阵） 与冷启动回归任一失败即停止。构建后再对中英文候选分别运行 `validate_workshop_mod_zh.py` 和 `validate_workshop_mod.py`。

发布前还需在 Repentance、Repentance+ 和 REPENTOGON 中分别手工验收；构建候选不等于上传授权。

## Workshop 自动发布

`tools/publish-workshop.ps1` 将固定发布流程固化为可审计状态机。默认只做双语测试、候选构建、Git HEAD/远端同步、Workshop 身份和远端预览图核验，不会启动上传器：

```powershell
pwsh -NoLogo -NoProfile -File .\tools\publish-workshop.ps1
```

人工验收完成且源码已提交、推送后，显式传入 `-Publish` 和对应语言的更新说明才会上传：

```powershell
pwsh -NoLogo -NoProfile -File .\tools\publish-workshop.ps1 `
  -Language zh,en -Publish `
  -ChineseChangeNotes '中文更新说明' `
  -EnglishChangeNotes 'English change notes'
```

自动化会在每个 GUI 操作前重新枚举并确认前台窗口，上传按钮对每个项目至多点击一次；上传后只轮询 Steam 的只读接口。证据和发布清单位于 `dist/workshop-publish/`。超时或状态不符时停止并保留截图，不会自动重复上传。

## Nexus 发布

Nexus 没有面向普通作者的上传 API，因此仓库侧只负责"打包 + 校验 + 页面文案"，网页操作由 `tools/nexus/` 在已登录的可见浏览器里完成。整条链路：

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\verify-nexus-packages.ps1 `
  -PythonPath 'C:\Users\lw\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
```

该入口先跑双语源码回归、构建两个 Workshop 候选并用现有校验器验证，再用 `tools/build-nexus-mod.ps1` 生成 Nexus 包：`dist/nexus-packages/IsaacChineseConsole-2.5.24-Nexus.zip`（中文）与 `dist/nexus-packages/ConsoleUI-2.5.4.19-Nexus.zip`（英文），zip 顶层只有一个 Mod 文件夹，并可被同一组校验器直接校验解包结果。构建脚本要求工作树无未提交的已跟踪改动且 `origin/main` 与本地 HEAD 一致（只有显式传 `-AllowUnpushedHead` 才允许例外），`*-BUILD-INFO.json` 记录来源提交、Mod 目录、版本、Workshop ID、包 SHA-256 与逐文件 SHA-256。

页面字段与可复制文案见 [NEXUS_UPLOAD.md](NEXUS_UPLOAD.md)；网页上传步骤与安全约定见 [tools/nexus/README.md](tools/nexus/README.md)。
