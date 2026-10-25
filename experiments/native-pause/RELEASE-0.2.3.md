# 原生暂停 0.2.3：未知哈希兼容检测与诊断日志

Rep／Rep+ 的游戏 EXE 哈希不在已知列表时，现在会自动检查实际依赖；兼容则启用暂停，不再仅因哈希不同直接停用。无需手动添加哈希或开启实验开关。

- 安装脚本同步允许未知哈希。
- 日志新增完整 EXE 哈希、文件信息、逐项兼容检查、挂钩结果与具体失败原因。
- 关键代码或字段不兼容时仅停用原生暂停，控制台其他功能继续可用。
- 保留现有暂停与恢复逻辑；新版 REPENTOGON 使用配套 Mod 的暂停回调，无需本原生组件。

## 下载与安装

配套控制台二选一，订阅并启用：[Isaac Chinese Console（中文）](https://steamcommunity.com/sharedfiles/filedetails/?id=3776882944) / [Console UI（英文）](https://steamcommunity.com/sharedfiles/filedetails/?id=3779128726)。本组件包已包含加载器，无需另行下载依赖。Workshop 订阅不会安装原生组件。

1. 完全退出游戏，下载本页附件 **native-pause-0.2.3.zip**，不要选 Source code。
2. Steam → 游戏属性／管理 → 浏览本地文件，定位实际运行的 `isaac-ng.exe`。
3. 将包内 `game-files` **里面的内容**复制到该目录，保留 `scripts` 层级：

```text
游戏目录/
├── isaac-ng.exe                       游戏原有文件
├── winmm.dll                          包内加载器
├── winmm.ini                          包内配置
└── scripts/
    └── IsaacConsoleNativePause.asi    原生暂停组件
```

不要覆盖其他 Mod 的同名加载器。手动安装不需要 PowerShell；可选安装脚本需要 PowerShell 7。

**升级：** 旧版手动安装的，退出游戏后只替换本组件的 `.asi` 文件；旧版使用脚本安装的，先用旧包卸载，再用新包安装。卸载仅移除本组件自己的三个文件，保留其他插件、Mod 和存档。

## 问题反馈

正常启动后查看游戏目录 `scripts/native-pause.log`。目录无法写入时，日志自动回退到 `%TEMP%/IsaacConsoleNativePause-<进程号>.log`。

反馈时发送最近一次 `START` 到结尾的完整日志，无需再手动计算哈希。`UNKNOWN_HASH compatibility_probe` 表示正在检测；`LOADED native-pause 0.2.3` 表示加载成功。检测不通过时查看 `CHECK ... result=FAIL` 和后续 `DISABLED` 原因。

## 验证范围

原生契约、兼容检测、自加载、日志回退、安装和双语回归均已通过；本机安装文件已逐项验证。真实 Rep+ EXE 映像通过未知哈希与无关字节修改检测，该检查未执行游戏。

本次未完成玩家联机补丁环境及未知 Rep EXE 的实机验收。仍使用已验证的固定地址布局，重大布局变化可能需要后续适配，不承诺所有补丁和未来版本均兼容。
