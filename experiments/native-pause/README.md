# 原生暂停组件

当前发布构建入口为 build-release.ps1，转交 build-autoload-release.ps1。用户只需将 game-files 中的 winmm.dll、winmm.ini 与 scripts/IsaacConsoleNativePause.asi 按目录结构复制到游戏目录一次，之后从 Steam 正常启动。详细安装、冲突处理与卸载说明见 AUTOLOAD-RELEASE.md。

Lua 菜单管理暂停生命周期；原生组件适配经过完整 EXE 哈希确认的 Repentance 与 Repentance+。缺少组件时 Lua 保持原有功能。内部桥接 IsaacConsoleNativePausePrototype(op) 保留兼容名称，1 获取自身暂停，0 只释放自身，2 查询暂停归属；只在游戏线程调用，Lua 栈净变化为零。

ASI 使用 Ultimate ASI Loader 的 winmm 代理加载。DllMain 仅保存句柄并创建不等待的初始化工作线程；日志、哈希核对与挂钩在加载器锁之外执行。MinHook 批量安装输入与绘制挂钩，Lua IAT 用原子比较交换发布。失败时暂停归属为零，可能存活的跳板与模块保留至进程退出。不支持运行中卸载。

build-native.ps1 构建原生组件和测试；test.c 覆盖两个运行时契约及四线程挂钩启停；run-integration.py 覆盖双语言、双运行时菜单；test-autoload.ps1 验证普通进程启动自动加载及拒绝未知 EXE；test-autoload-installer.ps1 验证安装、重复安装、冲突拒绝与仅移除自有文件。发布构建还运行完整 Mod 回归，要求源码工作树干净，记录 HEAD 和全部包文件哈希。实际游戏验收单独取证。

vendor/minhook 保留 MinHook 1.3.4 原始源码与许可证；vendor/asi-loader 保留固定版本 Ultimate ASI Loader、来源与哈希。inject.c 和旧手动加载脚本仅保留作诊断与历史追溯，不进入当前发布包。

REPENTOGON+ 使用独立 EXE 时须在该目录安装相同组件。其控制台会自行重置状态，因此适配器通过独立的 Game::IsPaused 挂钩合并菜单暂停归属，不写控制台状态，也不挂钩其输入与绘制。原生 bool 返回按 AL 读取，避免 EAX 高位导致外部暂停误判。支持清单仅声明已匹配完整 EXE 哈希的变体。
