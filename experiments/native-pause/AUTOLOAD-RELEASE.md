# 原生暂停 0.2.0：随游戏自动加载

安装一次，以后从 Steam 正常启动游戏即可使用暂停；没有每次启动的命令窗口。卸载后，控制台 Mod 的原有功能继续工作，只是不自动暂停。

## 手动安装（不需要PowerShell）

1. 正常退出游戏，更新“以撒中文控制台”到2.5.24或“Console UI”到2.5.4-en.19，并启用其中一个语言版本。
2. 将 `game-files` 内的内容按目录结构复制到 `isaac-ng.exe` 所在目录：根目录新增 `winmm.dll`、`winmm.ini`，`scripts` 目录新增 `IsaacConsoleNativePause.asi`。
3. 若目标已有同名文件，不要覆盖其他加载器或插件，应先处理冲突。
4. 从 Steam 正常启动。菜单打开时暂停，关闭时恢复。无需再运行 start.cmd 或加载器。

`.asi` 是原生DLL插件的扩展名；需要自动加载器和插件一起复制，单独复制暂停插件不会生效。

## 一次性安装与卸载脚本

可选：安装PowerShell 7后双击 `install.cmd`，脚本校验支持的EXE与文件哈希、检查冲突后安装。自定义目录传 `./install.ps1 -GameDirectory "实际目录"`。脚本只安装原生组件，不替换Mod、游戏EXE或存档。出现实际权限拒绝时请求UAC。

使用脚本安装的，游戏退出后双击 `uninstall.cmd`。手动安装的，游戏退出后只移除上述三个自己复制的文件；保留scripts目录内其他文件。

## 支持范围

支持明确哈希清单中的Steam Repentance 1.7.9b/x86与Repentance+ v1.9.7.17/J460/x86。插件自行核验EXE，未知版本拒绝挂钩并写诊断日志。Steam更新可能使组件停止启用，需对应版本更新。控制台Lua Mod的其他运行时兼容性与此原生组件的支持范围分别判断。

`scripts/native-pause.log` 记录加载、获取和释放暂停；初始化与未知版本拒绝可在这里检查。

## 实现与第三方组件

使用固定版本Ultimate ASI Loader的WINMM代理入口，转发原有系统接口并自动载入插件；配置不启用文件覆盖功能。插件初始化在工作线程执行，避免在DllMain加载器锁中安装挂钩；MinHook管理挂钩与线程指令位置，Lua IAT原子交换。模块保留到游戏退出，不支持运行中卸载。

许可证见LICENSE-ASI-LOADER.txt和LICENSE-MINHOOK.txt。来源、运行时与校验和见manifest.json。真实游戏验收记录与自动测试分别保存；不把自动模拟视为所有语言和设备的实机验证。
