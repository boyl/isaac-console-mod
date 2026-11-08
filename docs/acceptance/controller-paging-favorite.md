# 手柄语义、翻页去重与额外 2P 修复验收

日期：2026-11-08。分类：Bug；沿用输入适配层、现有布局与存档格式。

## 问题和实机证据

- 原反馈：忏悔+手柄一次翻两页、Y 翻说明变成收藏；忏悔无此问题。用户补充：自己的手柄不能复现重复翻页，但能复现 Y 收藏；额外角色确认为 2P。
- 正式源码：`isaac-console-mod`，`main`，基线 HEAD `0474d52773541b54c1368d8a3ca168f0eac8df82`。仓库与 `.git` 均由交互式用户持有；保留原有 `AGENTS.md` 未提交修改。
- 基线中文 2.5.31、Workshop ID 3776882944。安装与源码 `main.lua` 原哈希一致：`1065599B99755A34C782622DEB1D89F96CA8D1C2E70707A17F738BF3485D2F53`。
- 实际运行时为 Repentance+ v1.9.7.17 / J460，XInput 1.4，原生暂停组件 0.2.3。
- 用户校准发现 Y 的 raw 值为 6，但旧 Controller 表将 Y 声明为 7。用户明确要求通用语义匹配，拒绝新增按 DLC 固定 Y=6；这项尝试已撤回。
- 实机只读探针记录：物理 X → `ACTION_MENUEX=29`，物理 Y → `ACTION_MENUTAB=28`。因此根因是旧代码把所有运行时的 MENUTAB 都当成收藏，且说明仅读取旧 raw Y 声明。
- 额外 2P 的具体出现时点未捕获；已确认独立输入漏洞：控制台持有原生暂停时，旧 `onInput` 因 `Game():IsPaused()` 而放行 JOIN 等游戏动作。不能将代码漏洞自动等同于每次额外角色的已证实根因。

实机原始输入示例（日志原文）：

```text
[Console Input Probe] index=1; raw=6; actions=ACTION_MENUTAB=28,ACTION_SHOOTUP=6; paused=true
[Console Input Probe] index=1; raw=4; actions=ACTION_MENUEX=29,ACTION_SHOOTLEFT=4; paused=true
```

API 参考：[Input](https://wofsauge.github.io/IsaacDocs/rep/Input.html)、[ButtonAction](https://wofsauge.github.io/IsaacDocs/rep/enums/ButtonAction.html)。本次以真实运行时的枚举和信号为证据，未照搬在线资料中的数字。

## 修复和兼容性

1. 能力解析：存在 MENUEX 时，收藏使用 MENUEX、说明使用 MENUTAB；动作数字从运行时枚举读取，不按 DLC、设备名或 Y raw 数字选择。该路径不读取 raw Y。
2. 无 MENUEX 的旧运行时保留 MENUTAB 收藏和具名 Controller Y 后备。保留已验收的既有 raw 收藏兼容后备及用户明确自定义收藏绑定；返回、确认优先，不扩展未知数字映射。
3. LT/RT 的 raw、菜单动作、模拟量共享同次按压锁；全部释放才重新允许翻页。左右侧分别采样，LB/RB 次数调整保留。
4. 游戏原生暂停菜单继续拥有输入；控制台自己的暂停继续拦截游戏动作。关闭且无输入释放租约时不拦截；重开、断连及玩家分配边界保持原有让出规则，不在输入 Hook 内扫描物理输入。
5. 中英文同步。发布版本：中文 2.5.32、英文 2.5.4-en.27（metadata 2.5.4.27）。Workshop 身份、SaveData、预览图、游戏存档保持。

## 验收标准与结果

| 项目 | 结果 | 证据 / 限制 |
| --- | --- | --- |
| 失败回归 | PASS | 修改前重复信号导致额外翻页、Y 语义导致误收藏、控制台原生暂停时 JOIN 放行，均有失败断言。 |
| X/Y 语义契约 | PASS（模拟） | 有/无 MENUEX、不同运行时标志、索引 0/3、动作枚举整体偏移、raw 4/6/7/31 与完全无 raw；语义 X 只收藏、语义 Y 只翻说明。 |
| 翻页 | PASS（模拟） | LT/RT 三种首发来源、后续重复、模拟量抖动、释放重按；原分页焦点、边界、LB/RB 保持。实机限制集中见“待验证事项”。 |
| 暂停与 JOIN | PASS（模拟） | pressed=0、triggered=1、value=2 三类输入 Hook，控制台暂停阻断、原生暂停让出、关闭与重开边界不抢输入。 |
| 双语完整源码 | PASS | 最终源码 `run_all_tests.py`：264 Mock + 12 cold-start/lifecycle scenarios；另包含底座与图标检查，Lua 5.1 执行真实入口。 |
| 双语候选 | PASS | 允许列表构建：中文 56 文件、英文 46 文件；各自原有校验器通过，预览哈希保持。临时探针不在候选中。 |
| 中文安装 | PASS | 从验证候选安装，逐文件和严格目录审计均无差异。main.lua 更新；metadata.xml 仅统一换行，内容逐字符归一化比较一致。 |
| 运行时加载 | PASS | 重启后日志显示 `controller semantics: favorite=29; details=28; raw-details=nil`；安装 main.lua 哈希与候选相同。 |
| X/Y 实际操作 | PASS（用户实机验收） | 用户明确反馈“XY正常”。日志记录 5 次 X、10 次 Y；收藏保存跟随 X，Y 未触发收藏保存。 |
| 2P 实机 | 见待验证事项 | 探针记录玩家数为 1。 |
| 用户发布验收 | 已授权 | 用户确认“功能我已验证”，明确同意将 2P 作为盲修复一并发布；待验证事项集中披露。 |
| Git / 远端发布 | 准备中 | 最终上传和远端核验结果另存发布证据，不以授权代替发布成功。 |

版本号更新前的实机验收副本（2.5.31）主文件 SHA-256：`CE6D25814519ACE5028C43BDBC0496AC03379C3AE6CAF49AEDD6540609CB4138`。

## 待验证事项

- **翻页速度**：按压去重已通过模拟回归，但当前测试手柄未复现原先“一按翻两页”；仍需能复现的设备确认实机修复效果。
- **偶发额外 2P**：用户反馈“2p 我之前也没有问题，现在也没有出现，不确定是否解决”。已修正控制台原生暂停期间放行游戏输入的漏洞，但没有稳定异常复现步骤，不能确认与原反馈的因果关系。本次按用户授权作为盲修复发布。
- **跨运行时实机覆盖**：本次新实机证据来自 Repentance+；Repentance / REPENTOGON 的本次兼容性证据为模拟回归，不记为重新完成全部实机验收。

2P 复核使用单人临时局、同一已分配手柄，在起始房间重复菜单内给予/关闭操作；不要按 Start 或切换输入设备。没有稳定复现序列时，正常加入合作玩家不算 Mod 异常复现。

## 证据与回滚

- 本聊天 `work/`：`controller-red.log`、`controller-raw6-red.log`、`native-pause-red.log`、`input-ownership-green.log`、`all-tests-final.log`、`runtime-validation.log`、`installed-audit.json`。
- 本聊天 `outputs/`：`isaac-console-before-controller-fix.zip` 为修改前完整安装副本，逐个 ZIP 条目与原文件哈希复核；`controller-fix-installation.json` 包含基线和安装哈希、逐文件清单、备份校验和。
- 回滚包 SHA-256：`340805663318E5869FE8A04A228FE0AA15501E1418221BDF61C574E8F6789063`。回滚时先退出游戏，再还原原目录；不涉及 data 存档目录。
- 探针源码：`tools/diagnostics/controller-input-probe/`，仅在渲染阶段采样已分配控制器及玩家数量，无命令、无存档写入、无输入 Hook。日志变化去重，600 次变化或 10 分钟上限。编译和模拟行为检查已通过。
- 临时安装 `mods/console_input_probe` 已逐文件核对后移除；本进程已加载回调仍按上限自动停止，下次启动不再加载。源码与证据保留；不自动删除角色或修改存档。

旧翻页测试辅助器已加入物理点击之间的释放帧；末页使用有效选择索引继续检查边界不改变选择。此调整保留原验收约束，消除测试中不真实的连续按下与越界选择。
