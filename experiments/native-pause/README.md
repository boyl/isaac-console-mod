# 原生暂停组件

当前发布构建入口为 build-release.ps1，转交 build-autoload-release.ps1。用户只需将 game-files 中的 winmm.dll、winmm.ini 与 scripts/IsaacConsoleNativePause.asi 按目录结构复制到游戏目录一次，之后从 Steam 正常启动。详细安装、冲突处理与卸载说明见 AUTOLOAD-RELEASE.md。

Lua 菜单管理暂停生命周期；原生组件优先识别已知 EXE 哈希，未知哈希自动检测 Repentance 与 Repentance+ 的固定 RVA 适配器。恰好一个候选通过函数特征、字段引用、游戏指针引用和 Lua IAT 检查后启用；不需要手动加哈希或开启试验开关。缺少组件时 Lua 保持原有功能。内部桥接 IsaacConsoleNativePausePrototype(op) 保留兼容名称，1 获取自身暂停，0 只释放自身，2 查询暂停归属；只在游戏线程调用，Lua 栈净变化为零。

`compatibility.h` 负责只读识别与诊断，`pause.c` 保留挂钩和暂停归属。固定 RVA 布局发生变化仍可能检测失败，本轮不做全模块目标重定位。Rep+ 特征来自已知 J460 EXE；Rep 的指令模式参考 https://github.com/TeamREPENTOGON/REPENTOGON/blob/1.0.12/libzhl/functions/Console.zhl 及同版本 Game.zhl，配合控制台字段引用和游戏全局引用进行验证。不能把这些模式等同于任意新构建兼容承诺。

日志位于插件旁 `native-pause.log`，包含 UTC 时间、进程号、EXE 路径／大小／SHA-256、每项兼容检查、失败字节、挂钩阶段、启用结果和暂停归属。主路径无法写入时回退到 `%TEMP%/IsaacConsoleNativePause-<PID>.log`，并发送 OutputDebugString。日志中的地址是相对 EXE 的 RVA。

ASI 使用 Ultimate ASI Loader 的 winmm 代理加载。DllMain 仅保存句柄并创建不等待的初始化工作线程；日志、哈希核对与挂钩在加载器锁之外执行。MinHook 批量安装输入与绘制挂钩，Lua IAT 用原子比较交换发布。失败时暂停归属为零，可能存活的跳板与模块保留至进程退出。不支持运行中卸载。

build-native.ps1 构建原生组件和测试；test.c 覆盖三个运行时契约及四线程挂钩启停；test-compatibility.c 覆盖未知哈希成功、依赖损坏、歧义和真实 Rep+ 映像（不执行游戏）；run-integration.py 覆盖双语言、双运行时菜单；test-autoload.ps1 验证自动加载、兼容检测失败诊断；test-autoload-installer.ps1 验证未知哈希安装、重复安装、冲突拒绝与仅移除自有文件。发布构建还运行完整 Mod 回归，要求源码工作树干净，记录 HEAD 和全部包文件哈希。未提交开发验证可使用 build-autoload-release.ps1 -Candidate，制品明确标注 candidate、sourceDirty 和相关源码哈希，不视为正式发布。实际游戏验收单独取证。

vendor/minhook 保留 MinHook 1.3.4 原始源码与许可证；vendor/asi-loader 保留固定版本 Ultimate ASI Loader、来源与哈希。inject.c 和旧手动加载脚本仅保留作诊断与历史追溯，不进入当前发布包。

REPENTOGON+ 使用独立 EXE 时须在该目录安装相同组件。其控制台会自行重置状态，因此适配器在其更新链安装完成后，通过 Game::Update 挂钩阻止菜单期间的战斗更新，并用 Game::IsPaused 合并菜单暂停归属，不写控制台状态，也不挂钩其输入与绘制。原生 bool 返回按 AL 读取，避免 EAX 高位导致外部暂停误判。支持清单仅声明已匹配完整 EXE 哈希的变体。
