# 原生暂停组件

当前正式化实现见 pause.c、inject.c，构建入口为 build-release.ps1。使用已安装 MSVC x86 和 Windows SDK，静态链接 CRT，用户运行不需要安装编译器。旧原型文件名保留以便追溯，分发时映射为 start.ps1、restore.ps1。

领域逻辑仍由 Lua 菜单管理；DLL 只适配 J460 的暂停状态与原生控制台挂钩，加载器只处理 Unicode DLL 加载及显式初始化。构建和安装脚本分别负责验证、允许列表打包及带备份的安装恢复，不引入新的 UI 架构。

接口 IsaacConsoleNativePausePrototype(op) 为内部版本化桥接名称，保留已验收菜单的兼容性：1 获取自身暂停，0 只释放自身，2 查询当前画面是否归自身。无 DLL 时 Lua 保持原行为。桥接只在游戏线程内调用，Lua 栈净变化为零。

DLL 的 DllMain 仅保存模块句柄并禁用线程通知。NativePauseInitialize 在加载器锁之外执行；MinHook 批量安装输入和绘制挂钩，IAT 以原子比较交换发布。模块运行中不提供卸载入口；失败时 owned 为零，可能存活的跳板和模块保留至进程退出。所有运行时偏移只支持 manifest 中的完整 EXE 哈希。

build-native.ps1 构建原生代码及测试；test.c 验证业务契约和四线程/100轮挂钩启停；test-loader.ps1 验证真正跨进程加载、中文路径、显式初始化和拒绝非游戏目标；run-integration.py 验证中英文真实菜单源码；build-release.ps1 运行这些检查及完整既有回归，生成自包含配套包和源码 HEAD 清单。最终正式包要求 sourceDirty=false。

MinHook 1.3.4 的原始源码位于 vendor/minhook，来源 https://github.com/TsudaKageyu/minhook/tree/v1.3.4，按其许可证保留版权声明。未改写第三方实现。

历史原型输出保留独立证据与构建源码；本仓库使用 build-release.ps1 作为当前唯一发布构建入口。历史原型证据只能证明对应二进制，不能取代新版本实机验证。
