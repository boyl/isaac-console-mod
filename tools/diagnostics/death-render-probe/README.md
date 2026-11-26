# 死亡绘制隔离探针

F9 显式执行 `seed T1MM AY48` 进入测试局，覆盖当前运行进度，因此必须先备份运行存档。不会在加载时自动执行。

不进入发布包，不写 SaveData。仅种子 `T1MM AY48` 启用：F8 调用玩家 Kill（不代表自然伤害死亡验收），F10 注入短暂 ACTION_RESTART，F11 注入完整 ACTION_RESTART。日志必须证实引擎查询了动作，才能把它视为重开路径测试。测试前备份运行存档，结束后移除安装副本。

默认无 Shader。实验时可从历史 `d24721a:workshop-mod/content/shaders.xml` 导出独立测试资源，将 Shader 名称替换成 `DeathRenderProbe`；这只是重现历史方案，不是可发布的修复。死亡状态下的红色标记不调用原生绘制租约。

2026-11-26 J514 实测：F9/F8 可建立死亡场景；F10/F11 的 `input_queries=0`，未触发引擎重开，因此不能用于验收原生 R 渐暗。尚未进行带 Shader 的新对照，不得引用该探针声称 Shader 故障已解决。

### 无组件死亡菜单验收

F7 使用 `TakeDamage(99, 0, EntityRef(player), 0)` 触发伤害路径；只有日志出现 `END gameOver=true` 才证明进入死亡界面，不凭按键请求判断死亡成功。每次开局记录原生暂停与死亡接口是否存在。本探针不自带 Shader；正式 Mod 的 Shader 由实际候选提供，验收图片记录在独立证据目录。
