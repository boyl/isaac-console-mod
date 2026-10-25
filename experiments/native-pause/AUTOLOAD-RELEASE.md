# 原生暂停 0.2.3：随游戏自动加载

安装一次，以后从 Steam 正常启动游戏即可使用暂停；没有每次启动的命令窗口。卸载后，原版 Rep/Rep+ 的控制台功能继续工作，只是不自动暂停。新版忏悔龙菜单通过 MC_PRE_UPDATE 自动暂停，无需本组件。

配套控制台二选一：[Isaac Chinese Console（中文）](https://steamcommunity.com/sharedfiles/filedetails/?id=3776882944) 或 [Console UI（英文）](https://steamcommunity.com/sharedfiles/filedetails/?id=3779128726)。先订阅并在游戏 Mods 菜单启用其中一个。原生组件下载 [GitHub Release](https://github.com/boyl/isaac-console-mod/releases/tag/native-pause-v0.2.3) 的 `native-pause-0.2.3.zip`，不要下载 Source code。加载器已包含，无需另行下载；手动安装不需要 PowerShell。

## 手动安装（不需要PowerShell）

1. 正常退出游戏，更新“以撒中文控制台”到2.5.25或“Console UI”到2.5.4-en.20，并启用其中一个语言版本。
2. 将 `game-files` 内的内容按目录结构复制到 `isaac-ng.exe` 所在目录：根目录新增 `winmm.dll`、`winmm.ini`，`scripts` 目录新增 `IsaacConsoleNativePause.asi`。
3. 若目标已有同名文件，不要覆盖其他加载器或插件，应先处理冲突。
4. 从 Steam 正常启动。菜单打开时暂停，关闭时恢复。无需再运行 start.cmd 或加载器。

REPENTOGON 启动器使用独立 EXE 时，须将相同三项文件复制到该 EXE 的目录（例如游戏下的 `Repentogon` 子目录）。只复制到原版根目录不会自动加载到独立进程。可选脚本安装须用 `./install.ps1 -GameDirectory "实际 Repentogon 目录"`，卸载也指定相同目录。旧版 REPENTOGON 原生后端仍保留已知哈希适配，本轮新增的未知哈希兼容检测面向普通 Rep／Rep+。

`.asi` 是原生DLL插件的扩展名；需要自动加载器和插件一起复制，单独复制暂停插件不会生效。

### 安装后的目录结构示意

复制的是压缩包 `game-files` **里面的内容**，保留 `scripts` 文件夹结构。不要把三个文件全部放在同一层，也不要把整个 `game-files` 文件夹放进游戏目录。

**原版 Rep / Rep+：**

```text
The Binding of Isaac Rebirth/
├── isaac-ng.exe                         ← 游戏原有文件
├── winmm.dll                            ← 复制到这里
├── winmm.ini                            ← 复制到这里
└── scripts/                             ← 没有此文件夹就创建
    └── IsaacConsoleNativePause.asi      ← 插件必须放在这一层
```

**旧版忏悔龙原生组件安装示意（新版菜单已无需此组件）：**

```text
The Binding of Isaac Rebirth/
└── Repentogon/
    ├── isaac-ng.exe                     ← 实际运行的独立 EXE
    ├── winmm.dll                        ← 复制到这里
    ├── winmm.ini                        ← 复制到这里
    └── scripts/
        └── IsaacConsoleNativePause.asi  ← 插件必须放在这一层
```

以实际运行的 `isaac-ng.exe` 所在目录为准。如果分别使用原版和独立的忏悔龙 EXE，旧版组件需要两处按上述结构安装；新版忏悔龙菜单无需安装原生组件。

**常见错误：** `IsaacConsoleNativePause.asi` 与 `winmm.dll` 放在同一层，或多套了一层 `game-files/scripts`。这两种结构不会被当前加载器配置发现。

安装完成后完全退出并重新启动游戏，无需每次运行安装脚本。`scripts/native-pause.log` 是启动后尝试生成的日志，不是安装文件，下载包中没有它是正常的；资源管理器隐藏扩展名时可能显示为 `native-pause`。

## 一次性安装与卸载脚本

可选：安装PowerShell 7后双击 `install.cmd`，脚本记录EXE哈希、校验包文件、检查冲突后安装。未知EXE哈希允许安装，实际兼容性由游戏启动后的组件检查。自定义目录传 `./install.ps1 -GameDirectory "实际目录"`。脚本只安装原生组件，不替换Mod、游戏EXE或存档。出现实际权限拒绝时请求UAC。

使用脚本安装的，游戏退出后双击 `uninstall.cmd`。手动安装的，游戏退出后只移除上述三个自己复制的文件；保留scripts目录内其他文件。

## 支持范围

优先识别 Steam Repentance 1.7.9b/x86 与 Repentance+ v1.9.7.17/J460/x86。EXE 哈希不在清单时自动检测两个适配器，恰好一个通过则启用，无需手动放行。仅哈希变化不再直接禁用；关键函数或字段布局变化、Lua 入口不匹配、结果有歧义时会停用原生暂停并说明原因，控制台其他功能继续工作。

`scripts/native-pause.log` 记录完整 EXE 哈希、版本、UTC 时间、进程、逐项检测和挂钩结果，以及获取／释放暂停。主目录无法写日志时，查找 `%TEMP%/IsaacConsoleNativePause-<进程号>.log`。

- `UNKNOWN_HASH compatibility_probe`：哈希未知，正在自动检测，不表示拒绝。
- `CHECK ... result=FAIL`：具体失败项和 RVA；函数不匹配时还有实际字节。
- `COMPATIBLE_UNKNOWN_HASH`：未知哈希已通过兼容检测。
- `LOADED native-pause 0.2.3`：组件已加载。
- `DISABLED no_compatible_runtime`：没有适配器通过，查看前面的 FAIL。
- `DISABLED ambiguous_compatible_runtime`：多个候选同时通过，无法可靠选择。

反馈时请发送本次启动的完整日志，从 `START` 到最后一行，不必再手动计算哈希。

升级旧组件时先正常退出游戏。手动安装的只替换属于本组件的 `scripts/IsaacConsoleNativePause.asi`；使用脚本安装的先用旧包卸载，再用新包安装，避免安装回执与实际文件不一致。不要覆盖其他加载器。

## 实现与第三方组件

使用固定版本Ultimate ASI Loader的WINMM代理入口，转发原有系统接口并自动载入插件；配置不启用文件覆盖功能。插件初始化在工作线程执行，避免在DllMain加载器锁中安装挂钩；MinHook管理挂钩与线程指令位置，Lua IAT原子交换。模块保留到游戏退出，不支持运行中卸载。

许可证见LICENSE-ASI-LOADER.txt和LICENSE-MINHOOK.txt。来源、运行时与校验和见manifest.json。真实游戏验收记录与自动测试分别保存；不把自动模拟视为所有语言和设备的实机验证。
