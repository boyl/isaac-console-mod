# Nexus Mods 上传说明 · 2.5.24（中文） / 2.5.4.19（英文）

本文件记录把 `Isaac Chinese Console`（中文）与 `Console UI`（英文）发布到 Nexus Mods 所需的**页面字段、可复制文案、内容与授权检查、发布顺序和上传后核验**。发布包只能由本仓库脚本从已推送的提交生成；本文件不构成上传授权。

## 0. 结论与边界

- **一个页面、两种语言、两个 Main File。** 同一个 Mod 只是语言不同；分两页会重复说明、拆分 endorse、并让同一份字体/脚本维护两份页面。单页只要在正文开头给出"只装其中一个"的醒目提示，观感是清晰的。
- 仍希望更干净的中文/英文独立发现路径时，把两个 Main File 拆成两页即可：页面字段和文案可直接沿用本文件的两段语言内容，不需要改包。
- **Nexus 没有面向普通作者的上传 API**：公开 API 只读，无法程序化建页或提交文件。仓库侧能自动化的是"打包 + 校验 + 页面文案 + 证据"，网页操作由 `tools/nexus/` 在用户已登录的浏览器里执行（CDP），失败时退回人工操作，步骤见第 7 节。

## 1. 上传前的仓库侧状态

在仓库根目录执行（PowerShell 7）：

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File .\tools\verify-nexus-packages.ps1 `
    -PythonPath 'C:\Users\lw\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
```

该入口依次做：双语源码回归测试 → 构建两个 Workshop 候选 → 用 `validate_workshop_mod_zh.py` / `validate_workshop_mod.py` 校验候选 → `build-nexus-mod.ps1` 生成 Nexus 包（zip 顶层只有一个 Mod 文件夹）→ 解包后逐文件 SHA-256 复核并**再用同一组校验器校验解包结果**。成功后打印 `BILINGUAL_WORKSHOP_GATE=OK` 与 `NEXUS_PACKAGE_GATE=OK`，证据写入 `dist/nexus-packages/logs/verify-<时间戳>.log` 与 `dist/nexus-packages/NEXUS-GATE-<时间戳>.json`。

发布包与证据文件（`dist/nexus-packages/`，不进入仓库版本控制）：

| 文件 | 内容 |
| --- | --- |
| `IsaacChineseConsole-2.5.24-Nexus.zip` | 中文包，顶层 `isaac_chinese_console_workshop/`，52 个文件 |
| `ConsoleUI-2.5.4.19-Nexus.zip` | 英文包，顶层 `console_ui_workshop/`，42 个文件 |
| `<Slug>-<版本>-BUILD-INFO.json` | 来源提交、来源仓库、语言变体、Mod 注册名、目录、版本、Workshop ID、包 SHA-256、逐文件 SHA-256 |
| `<Slug>-<版本>.sha256` | 包文件的校验行 |

`build-nexus-mod.ps1` 在打包前强制要求：已跟踪文件无未提交改动、`origin/main` 与本地 HEAD 完全一致；只有显式传 `-AllowUnpushedHead` 才允许从尚未推送的提交打包（并在 BUILD-INFO 中记录 `SourceCommitPushedToOriginMain=false`）。上传时使用的包必须来自第 6 节推送后的那一次构建。

## 2. 页面设置（逐个字段）

| 字段 | 取值 |
| --- | --- |
| 游戏分区 | The Binding of Isaac（`thebindingofisaacrebirth`） |
| Mod name / 页面标题 | `Isaac Chinese Console + Console UI (中文 / English) 2.5.24` |
| Version | `2.5.24`（英文包为 `2.5.4.19`，在 File 条目里写） |
| Summary（英文为主） | 见第 3 节 |
| Category | 优先 `User Interface`；该游戏分区若没有界面类目则选 `Miscellaneous`（按站点实际类目名选择，不要自造） |
| Tags | 语言：`English`、`Chinese`（简体）；玩法：`User Interface` / `Gameplay` / `Utility` / `Singleplayer`；若站点提供 `AI-Generated Content` 标签则必须勾选（本 Mod 代码与中英文文案由 AI 辅助生成，见第 5 节） |
| Requirements | **无强制前置**。不要添加任何 Required Mods |
| Permissions | 见第 5 节末；由作者本人决定 |
| Images | 主图 `workshop-mod/preview.png`（1233×643）；第二张 `workshop-mod-en/preview.png`（2262×1289）；可加 `tools/acceptance/fixtures/zh-settings-page2.jpg` 等实机截图 |
| Language | English、Chinese |
| Mirrors | 可留空；作者更新入口保持 GitHub（`https://github.com/boyl/isaac-console-mod`） |

Files 区块两个 **Main Files**：

| File name | File version | File category | File description |
| --- | --- | --- | --- |
| `Isaac Chinese Console 2.5.24 (Chinese)` | `2.5.24` | Main Files | 中文界面。解压后把顶层文件夹 `isaac_chinese_console_workshop` 放进 Mods 目录；与英文包同时只启用一个。 |
| `Console UI 2.5.4.19 (English)` | `2.5.4.19` | Main Files | English interface. Extract the top-level `console_ui_workshop` folder into your Mods folder. Enable only one language build at a time. |

## 3. 可复制的摘要

**英文（Summary，单行）**

```
A self-contained in-game console menu for Repentance, Repentance+ and REPENTOGON: 1162 searchable items and commands, pinyin/English search, favorites, custom commands and batch spawns. No required Mods, no external tools, no native debug console.
```

**中文（可选第二行）**

```
游戏内自包含的控制台菜单：1162 条可搜索的物品与命令、拼音搜索、收藏、自定义命令与批量生成；支持 Repentance / Repentance+ / REPENTOGON，无强制前置 Mod。
```

## 4. 可复制的正文

Nexus 说明编辑器右上角的 `[ ]` 按钮可切到 BBCode 源码，粘完再切回所见即所得。以下正文只用最保守的 BBCode（`[b]`、`[list][*]`、`[url=]`），避免类目不支持的标签显示成字面文本。

### 4.1 英文正文

```
[b]Isaac Chinese Console[/b] adds a self-contained, controller-friendly command console to [b]The Binding of Isaac: Repentance, Repentance+ and REPENTOGON[/b]. Chinese (or English) item names, pinyin search, favorites, custom commands and batch spawns are all available in game, without the native debug console, without simulated keystrokes and without any required Mod.

[b]Two language builds are included - install only one of them[/b]
[list]
[*][b]IsaacChineseConsole-2.5.24-Nexus.zip[/b] - Chinese interface (mod folder: isaac_chinese_console_workshop)
[*][b]ConsoleUI-2.5.4.19-Nexus.zip[/b] - English interface (mod folder: console_ui_workshop)
[/list]
Both builds use the same F6 / L3 open shortcut and the same save data layout, but each keeps its own folder and register name. Enabling both at once makes them compete for the same shortcut, so pick one.

[b]Open the menu[/b]
Start a run and press [b]F6[/b], or hold the left stick button ([b]L3[/b]) for about 0.5 seconds. If your controller does not report L3, the built-in Input Settings category can calibrate a compatibility button.

[b]Features[/b]
[list]
[*]Chinese categories: 19 categories covering 721 collectibles, 188 trinkets, 97 cards/runes, 50 pill effects and 106 official commands or reference entries
[*]All 1162 built-in entries can be favorited; "Favorites" is ordered by most recent, and favoriting never changes command permission
[*]1056 official objects with stable IDs plus Chinese, English, full-pinyin and initial-letter search across categories
[*]Custom commands: optional display name, add, search, favorite, edit, delete and history recall; no artificial entry limit, protected by a 64 KiB SaveData safety gate
[*]Floor whitelists: 45 entries in normal mode, 7 in Greed/Greedier; lifecycle commands run through a separate safe channel
[*]Batch execution of 1-99 for collectibles and safe supplies; entries that cannot be batched are limited to one
[*]Keyboard, mouse and gamepad support with focus navigation, favorites, removal, count adjustment, list paging and multi-page descriptions
[*]Built-in Settings category with the full configuration set, plus optional Mod Config Menu mirroring
[*]Optional high-resolution font (off by default) that keeps the original font size, two-column layout and 8 entries per page
[*]The menu hides the game HUD while it is open, yields to the native pause menu, and can still be opened after Game Over
[*]No key simulation, no native console window, no leftover backtick input
[/list]

[b]Controls[/b]
[list]
[*]Arrow keys, mouse or d-pad: navigate
[*]Enter, left mouse button or gamepad A: run the focused entry
[*]Right mouse button or hold gamepad A for about 0.5 seconds: remove the item itself
[*]F, gamepad X or the on-screen star: toggle favorite
[*]LT/RT: page the list; LB/RB: adjust the batch count
[*]D, click the description or gamepad Y: read multi-page descriptions
[*]C: edit the full command; Up/Down inside the editor recall command history
[/list]
[b]Removing an item is not a full undo.[/b] Coins, keys, bombs, health, spawns, room state and scripted effects that were already granted can persist.

[b]Installation[/b]
1. Download the archive for the language you want.
2. Close the game.
3. Extract the single top-level folder ([b]isaac_chinese_console_workshop[/b] or [b]console_ui_workshop[/b]) into your Mods folder:
   - Repentance: the [b]mods[/b] folder inside the game installation, next to isaac-ng.exe
   - Repentance+: [b]Documents\My Games\Binding of Isaac Repentance+\mods[/b]
4. If you already subscribed to a Steam Workshop copy, unsubscribe it (or delete the old folder) first, so only one copy is installed.
5. Start the game, enable the Mod in the Mods menu, start a run and press F6.
No installer, no PowerShell and no external tool is required.

[b]Optional integrations (none are required)[/b]
[list]
[*][b]External Item Descriptions (EID)[/b] - adds names and effect text for extra objects; this Mod never copies or edits EID files
[*][b]Mod Config Menu (MCM)[/b] - optional mirror of the built-in Settings, writing the same values
[*][b]Native pause component[/b] - a separate, optional download from the project's GitHub releases that pauses the game while the menu is open. A Workshop subscription or this Nexus download does not install it.
[/list]

[b]Compatibility[/b]
One download supports Repentance, Repentance+, and REPENTOGON. Verified on Repentance 1.7.9b and Repentance+ v1.9.7.17/J460. To avoid the instant black screen when restarting Repentance+ with the hold-R shortcut, the Mod ships no custom shader; the death summary menu is drawn with ordinary rendering and may be covered by the native death note. Other Mods that install their own shaders can still cause related issues.

[b]Limits[/b]
This is a local debug and entertainment tool that changes the current run. Do not use it in daily challenges or online co-op, and back up important saves first. It does not access the network and does not launch external programs. For bug reports, include the game version, DLC/runtime, enabled Mod list and the relevant lines from log.txt.

[b]Credits[/b]
[list]
[*]Fusion Pixel Font (缝合像素) by TakWolf and contributors - SIL Open Font License 1.1, bundled as 10px/12px BMFont atlases
[*]HD font atlases derived from Source Han Sans (Adobe, SIL Open Font License 1.1), generated from the pinned revision a4f7cf94edfb9d7ffbdfc4841de276358bd7e0f2
[*]External Item Descriptions (Wofsauge and contributors) - optional runtime integration only; no EID data, icons or code are redistributed. Pinyin and English search aliases were generated from EID's official name lists.
[/list]
```

### 4.2 中文正文

```
[b]以撒中文控制台[/b] 是一个游戏内自包含的控制台菜单，支持 [b]Repentance、Repentance+ 与 REPENTOGON[/b]：中文物品名、拼音搜索、收藏、自定义命令与批量生成全部在游戏内完成，不弹出原生控制台、不模拟按键、也不强制安装任何前置 Mod。

[b]本页包含中英两个语言包，只安装其中一个[/b]
[list]
[*][b]IsaacChineseConsole-2.5.24-Nexus.zip[/b] - 中文界面（Mod 文件夹：isaac_chinese_console_workshop）
[*][b]ConsoleUI-2.5.4.19-Nexus.zip[/b] - 英文界面（Mod 文件夹：console_ui_workshop）
[/list]
两个包使用相同的 F6 / L3 呼出方式与相同的存档结构，但各自保留独立的文件夹与注册名。同时启用会互相抢占呼出键，请只启用一个。

[b]呼出方式[/b]
开始一局后按 [b]F6[/b]，或长按手柄左摇杆（[b]L3[/b]）约 0.5 秒。手柄无法识别 L3 时，可在内置“输入设置”分类校准兼容呼出键。

[b]核心功能[/b]
[list]
[*]19 个中文分类，覆盖 721 个收藏品、188 个饰品、97 个卡牌/符文、50 个胶囊效果、106 个官方命令或参考条目
[*]全部 1162 个内置条目均可收藏；“常用精选”按最近收藏优先显示，收藏不会改变命令权限
[*]全部 1056 个有效官方对象内置稳定 ID，支持中文、英文、全拼和首字母跨分类搜索
[*]自定义命令支持可选名称、新增、搜索、收藏、编辑、删除和历史召回；没有人为条目数量限制，完整 SaveData 受 64 KiB 安全门禁保护
[*]正常模式提供 45 项楼层白名单，贪婪/更贪婪模式提供 7 项；生命周期命令使用独立安全通道
[*]收藏品与安全补给可批量执行 1-99 次；不适合批量的条目自动限制为单次
[*]支持键盘、鼠标和手柄，包含焦点导航、收藏、移除、次数调整、列表翻页和多页说明
[*]内置“设置”提供完整配置，并可选与 Mod Config Menu 同步读写同一份设置
[*]可选高清字体，默认关闭；保留原字号、两列布局与每页 8 项
[*]菜单打开时隐藏游戏 HUD，原生暂停菜单出现时暂时隐藏，Game Over 后仍可呼出
[*]不模拟按键，不弹出原生控制台，不会残留反引号
[/list]

[b]操作方式[/b]
[list]
[*]方向键、鼠标或十字键：导航
[*]Enter、鼠标左键或手柄 A：执行焦点条目
[*]鼠标右键或长按手柄 A 约 0.5 秒：移除物品本体
[*]F、手柄 X 或点击星标：切换收藏
[*]LT/RT：列表翻页；LB/RB：调整次数
[*]D、点击说明或手柄 Y：翻阅多页说明
[*]C：编辑完整命令；输入框内 ↑/↓ 召回命令历史
[/list]
[b]移除物品不等于完整撤销。[/b] 已经获得的硬币、钥匙、炸弹、生命、生成物、房间状态和脚本效果可能继续保留。

[b]安装方法[/b]
1. 下载需要的语言包。
2. 关闭游戏。
3. 解压后把唯一的顶层文件夹（[b]isaac_chinese_console_workshop[/b] 或 [b]console_ui_workshop[/b]）放进 Mods 目录：
   - Repentance：游戏安装目录里与 isaac-ng.exe 同级的 [b]mods[/b]
   - Repentance+：[b]文档\My Games\Binding of Isaac Repentance+\mods[/b]
4. 如果已经订阅 Steam 创意工坊版本，请先取消订阅或删除旧文件夹，只保留一份。
5. 启动游戏，在 Mods 菜单启用本 Mod，开始一局后按 F6。
不需要安装程序、不需要 PowerShell，也不需要任何外部工具。

[b]可选集成（均非前置）[/b]
[list]
[*][b]External Item Descriptions（EID）[/b]：可补全部分额外对象的中文名称与效果；本 Mod 不复制或修改 EID 文件
[*][b]Mod Config Menu（MCM）[/b]：可选镜像，与内置“设置”读写相同配置
[*][b]原生暂停组件[/b]：另行从项目 GitHub releases 下载的可选组件，可在菜单打开时暂停游戏；订阅创意工坊或下载 Nexus 包都不会自动安装
[/list]

[b]兼容性[/b]
同一份下载支持 Repentance、Repentance+ 与 REPENTOGON，已验证 Repentance 1.7.9b 与 Repentance+ v1.9.7.17/J460。为避免 Repentance+ 按住 R 重开时瞬间黑屏，本 Mod 不加载自定义 Shader；死亡结算菜单改用普通绘制，可能被原生遗书遮挡。其他 Mod 自带 Shader 仍可能造成同类问题。

[b]安全及使用限制[/b]
这是用于本地娱乐、构筑测试和截图录制的调试工具，会改变当前局面。请勿用于每日挑战或在线联机，重要存档建议提前备份。本 Mod 不联网、不启动外部程序。反馈问题时，请提供游戏版本、DLC/运行时、已启用 Mod 列表和 log.txt 相关内容。

[b]致谢[/b]
[list]
[*]缝合像素 Fusion Pixel Font（TakWolf 及贡献者）：SIL Open Font License 1.1，随包分发 10px/12px BMFont 字形
[*]高清字体图集派生自思源黑体 Source Han Sans（Adobe，SIL Open Font License 1.1），基于固定提交 a4f7cf94edfb9d7ffbdfc4841de276358bd7e0f2 生成
[*]External Item Descriptions（Wofsauge 及贡献者）：仅做运行时可选集成，不重新分发其数据、图标或代码；拼音与英文搜索别名按 EID 官方名称列表机械生成
[/list]
```

## 5. 权限与内容检查

- **第三方资源**：包内只含自研 Lua/界面资源，加上按 OFL 1.1 分发的 Fusion Pixel Font 字形与派生自 Source Han Sans 的高清图集；两份 OFL 许可全文已随包分发（`FONT-LICENSE-OFL.txt`、`resources/font/hd/LICENSE-OFL.txt`），署名与许可不得移除。
- **不含**：游戏原始资源、其他 Mod 的文件、EID 的说明数据库/图标/代码、第三方 DLL、账号信息、存档或诊断 JSON。
- **生成式 AI 披露**：本 Mod 的 Lua 代码、中文/英文说明与文案均由 AI 辅助生成，经自动回归与用户实机验收；Nexus 若提供 `AI-Generated Content` 标签必须勾选，正文 Credits 段落已列出第三方署名。
- **再分发/改模许可**：由作者本人在页面上选择。建议允许"在署名并链接本页的前提下分发未修改的副本"，要求"修改版或再上传前先联系作者"。
- **Nexus 规则**：提交前对照站点现行规则自查（文件命名与版本、不得包含他人内容、说明与截图须与文件一致）：`https://help.nexusmods.com/article/28-file-submission-guidelines`、`https://help.nexusmods.com/article/136-best-practices-for-mod-authors`。

## 6. 发布顺序

1. 在仓库中完成改动，跑第 1 节的门禁并保存日志。
2. 提交到 `main` 并推送到 `origin/main`（本轮已获用户授权）；确认 `git rev-list --left-right --count origin/main...HEAD` 输出 `0	0`。
3. 用**该提交**重新构建发布包：`pwsh -File .\tools\build-nexus-mod.ps1`，记下两个包的 SHA-256 与 `SourceCommit`。
4. 用 `tools/nexus/invoke-nexus-upload.ps1` 在用户已登录的浏览器里创建页面、填文案、上传文件与图片；或在浏览器中按第 2-4 节手动完成。
5. 上传后按第 8 节核验，并把页面地址与证据（截图、文件页字段）记入 `dist/nexus-packages/`。

## 7. 浏览器上传（自动化与兜底）

```powershell
# 1) 启动一个带 CDP 的可见 Chrome（独立配置目录，避免动到日常配置）
& .\tools\nexus\invoke-nexus-upload.ps1 -Packages dist\nexus-packages -Step inspect

# 2) 按输出提示在打开的窗口里登录 Nexus（会话会保留在该配置目录里），然后执行填充
& .\tools\nexus\invoke-nexus-upload.ps1 -Packages dist\nexus-packages -Step fill

# 3) 上传两个包与图片
& .\tools\nexus\invoke-nexus-upload.ps1 -Packages dist\nexus-packages -Step files -StepImages

# 4) 只在确认无误后发布（默认不点发布按钮）
& .\tools\nexus\invoke-nexus-upload.ps1 -Packages dist\nexus-packages -Step publish
```

- 浏览器通道必须提权运行（沙箱内 Chrome 会因 crashpad `OpenProcess: 拒绝访问 (0x5)` 立即退出）；编排脚本会检查 9222 端口是否已被占用，不会抢占已有实例。
- 每一步都在 `dist/nexus-packages/browser-evidence/<时间戳>/` 留下截图与 DOM 字段快照，作为"填了什么、传了什么"的证据。
- 页面结构变化、Cloudflare 挑战、二次验证、文件选择框无法程序化设置等情况下，脚本会停下并打印"需要人工完成的具体动作"，已填字段保持不变；人工完成后可从下一步继续。
- 发布按钮与文件删除按钮默认不点击；只有显式传 `-Step publish` 才会触发。

## 8. 上传后核验清单

- [ ] 页面名称、Summary、Version 与两个 File 条目的名称/版本/类目一致
- [ ] Main Files 的文件名、大小与本地 `BUILD-INFO.json` 一致（可下载自己核对 SHA-256）
- [ ] Requirements 为空、Permissions 与 Credits 已填写、`AI-Generated Content` 标签已勾选
- [ ] 主图与画廊图片正常显示，没有把开发用占位图传上去
- [ ] 正文 BBCode 没有原样显示标签，两个安装路径说明完整
- [ ] 两个语言包各下载一次，解压后顶层只有 `isaac_chinese_console_workshop` / `console_ui_workshop`，逐文件 SHA-256 与 BUILD-INFO 一致
- [ ] 至少在一台实际游戏里用 Nexus 包（而不是创意工坊副本）启动一次并呼出菜单；创意工坊订阅副本与 Nexus 副本不要同时启用
- [ ] 页面地址、发布时间、证据截图记入 `dist/nexus-packages/`
