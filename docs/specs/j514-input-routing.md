# J514 输入设备路由排查与修复

状态：验收完成，已发布中文 2.5.35、英文 2.5.4-en.30（metadata 2.5.4.30）至创意工坊与 Nexus，并下载复核。自动与物理对照分别记录；原生组件无改动，保留 0.2.5。

## 范围与兼容约束

- 中英文保持同一输入行为；保留 F6、L3 长按阈值、自定义绑定、确认/返回/收藏及肩键语义。
- 仅在输入边界转换玩家设备索引；不修改全局 Input，不依赖原生暂停组件。
- 保留 Repentance、旧 Rep+ / J510、REPENTOGON 的既有路由。
- 使用真实程序与运行时探针确定契约；模拟测试不能替代物理手柄或实机键鼠。

## 已定位事实

- J514 EXE SHA256：C8337B957B7805AEE1EAC0C49CC7A8EA7BA2E195C7F84A0AB41051406DF9426A。
- EntityPlayer.ControllerIndex getter RVA 0x246f0 直接返回内部索引；实际日志首个手柄为 0。
- Input IsButtonPressed / GetButtonValue / IsActionPressed 等包装把 0 转为键盘 -2，正数减一；玩家索引与查询索引不再相同。
- 新接口 Input.GetKeyboardDeviceId（RVA 0x479b50）返回 -2；保留的 J510 安装器映像未包含该接口。
- Lua 实际返回无符号值 4294967294，因此同时识别 -2 和 4294967294。修复前只读探针抓到玩家索引 1 的 L3 出现在查询索引 2（raw button 10），旧代码查询 1 收不到。
- 用户配置为 openKey=295、controllerOpenFallbackButton=auto，排除自定义按键覆盖默认 L3。

## 任务与验收

- [x] 核对唯一仓库、所有权、版本、安装副本及当前配置。
- [x] 只读实机探针确认 Lua 玩家索引、查询索引与新接口。
- [x] 建立失败回归；最小修复集中路由并同步双语。
- [x] 新旧路由、首个/非零/多玩家、长按与释放、设备隔离回归。
- [x] 实机键盘：F6 往返、数字搜索、Ctrl+A/退格、Enter/Esc；物理 ↓ 由用户确认。
- [ ] 完整键盘自动导航、PageUp/PageDown、斜杠搜索快捷键：脚本已运行但输入未生效，不标通过。
- [x] 对上述自动输入限制完成物理对照：用户确认 ↑/←/→、PageDown/PageUp、/ 与 Esc 正常；保留自动失败记录。
- [x] 实机鼠标：定位、分类/翻页点击、搜索焦点与键盘接管、关闭按钮；无新增滚轮功能。
- [x] 实机手柄：L3 打开/保持/释放/关闭，由物理操作、运行日志和用户回复“正常”共同确认；日志另见手柄导航/分页/收藏。
- [x] 手柄基础确认/返回实机对照：用户确认方向/肩键导航分页、确认进入分类、返回退回均正常；其他输入模式由既有 Mock 覆盖。
- [x] 双语源码和候选门禁、安装哈希核对，移除诊断副本并恢复测试配置。

## 验证记录

- 生产改动仅中英文 main.lua：在 7 个手柄 Input 调用点统一转换查询索引；玩家、长按和设备归属状态仍使用原索引。J514 不再把未分配的第一手柄误作为键盘重开候选。键盘模块、鼠标模块和原生 ASI 未改。
- 红：新增 J514 独立引擎契约先复现翻页失败；设备隔离用例再复现未分配手柄泄漏到重开查询。绿：92 个 J514 场景、418 个既有 Mock、12 个冷启动/生命周期场景通过；双语允许列表、身份和预览图门禁通过。
- 实机 J514 / Rep+ 1.9.7.20 中文：用户确认 ↓ 移动、F6 关闭、L3 长按打开及松开后短按关闭正常。旧运行时及英文的本轮验证仅为离线回归，未重新启动实测。
- j510-keyboard.mjs 完整脚本在 Down 断言失败；仅跳过导航后的尝试在 slash 断言失败。探针没有收到自动 Down，物理 Down 则能移动。保留 FAIL 原记录；不能据此声称游戏键盘功能失败，也不能声称全键盘自动通过。
- 新增 j514-mouse-keyboard.mjs 回写本次校准的稳定键鼠流程。首次连跑阶段触发工具 10 MRTR rounds 上限；重置工具并恢复现场后，每次仅推进一个阶段，13 项断言 PASS，存档和 options.ini 字节不变。
- 两种候选与安装副本逐文件 SHA256 一致：中文 58、英文 48 文件。诊断安装副本已移出，游戏已重新加载正式候选。用户物理测试新增的收藏已保留。
- 原生 0.2.5 未修改，SHA256：6E23B507A3288CFA928191865228C82BFB77AFCA0B74E12644FDAA05C08E1F91。
- 本机证据目录：C:/Users/lw/Documents/Codex/2026-11-21/yi/work/j514-input-audit/。主要记录为 red.log、isolation-red.log、final-gate.log、physical-before-fix.log、physical-after-fix.log、keyboard-live/result.json、keyboard-remaining-live/result.json、mouse-keyboard-live-segmented/result.json、final-install-audit.json、final-live.log。
- 此前 144 组影响审计只覆盖 Mod 更新的模拟契约，不作为 J514 实机支持证据。
- 发布阶段补验：用户对剩余物理键盘和手柄项目回复“可以”，运行日志出现分类进入/返回及选择移动。证据保存在 work/j514-input-release/physical-final.log。正常退出游戏后更新版本，双语发布候选门禁再次通过（release-gate.log）。
- 发布流程复用 tools/publish-workshop.ps1；此前成功使用的 Nexus 官方 API 文件更新流程整理为 tools/nexus/publish-files.ps1，使用已验证提交、既有文件链、前一版本 ID 和持久化回执，默认仅预检。

## 发布结果（2026-11-26）

- 发布源码提交：eb341a58145e2213496de9da2589eb902f9daaaf，推送后核对 origin/main 一致。发布候选及 Nexus 包均绑定此提交。
- 完整发布门禁再次通过：92 个 J514 场景、418 个既有 Mock、12 个启动/生命周期场景，双语候选与 Nexus 解包校验全部通过。
- 创意工坊使用现有发布脚本和项目锁定的 GameModdingToolkit 0.2.0；默认选中的 0.3.2 因锁不匹配被预检阻止，未上传。正式脚本于北京时间 22:18:20 完成双语上传。项目 3776882944 / 3779128726 均公开，预览图哈希未变。
- 经 Steam 客户端重新下载两个订阅包，中文 58、英文 48 个文件全部匹配；仅 metadata.xml 的换行格式经归一化后比较。对应 Steam 内容清单为 6195713157252767146 / 7275172531519722935。
- Nexus Mod 140 的中文 2.5.35（文件 666，全局版本 5553392714394）、英文 2.5.4.30（文件 667，全局版本 5553392714395）已发布为 Main Files，扫描均 cleared，沿用原文件链并归档旧版本。页面版本文案及双语更新日志已通过官方 API 写入并读回核对。
- 实际下载 Nexus 两个 ZIP，SHA256 与门禁制品完全一致：中文 9960D9693A8CFD161A15A27941902336AE64FEB03C43F5A6A40BD5A3DD6106D9；英文 D16D6D299AC44DBDDC7B79CC14A6A5E487A311254750623E8D7639DF67933224。网页抓取工具对 Nexus 返回 403，本轮远端证据为官方 API 与实际下载内容。
- 上传后从正式源码重建干净候选，更新本机两个安装副本并逐文件核对。J514 实际重启加载中文 2.5.35，继续原有游戏后 F6 正常打开菜单；原生日志仍为 0.2.5，ASI 哈希不变。
- 发布证据位于 work/j514-input-release/，主要包括 nexus-gate.log、workshop-pinned-publish.log、workshop-remote-after.json、workshop-downloaded-verification.json、nexus-download-verification.json、release-runtime.log 和 release-result.json。上传器截图与清单位于 dist/workshop-publish/20261126-221724/。
