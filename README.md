# Isaac Console Mod

这是 The Binding of Isaac: Rebirth 游戏内控制台 Mod 的独立源仓库，与桌面版控制台项目分开维护。

## 目录

- `workshop-mod/`：中文版正式源码，当前版本 `2.5.14`，Workshop ID `3776882944`。
- `workshop-mod-en/`：英文版正式源码，当前内部版本 `2.5.4-en.9`、metadata `2.5.4.9`，Workshop ID `3779128726`。
- `tests/workshop-mod/`：中英文 Lua Mock、冷启动回归和双语发布负载验证器。
- `tools/build-workshop-mod.ps1`：中英文显式允许列表构建脚本。

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

使用 `tests/workshop-mod/run_all_tests.py` 作为中英文统一入口，两套 88 项 Lua Mock 与冷启动回归任一失败即停止。构建后再对中英文候选分别运行 `validate_workshop_mod_zh.py` 和 `validate_workshop_mod.py`。

发布前还需在 Repentance、Repentance+ 和 REPENTOGON 中分别手工验收；构建候选不等于上传授权。
