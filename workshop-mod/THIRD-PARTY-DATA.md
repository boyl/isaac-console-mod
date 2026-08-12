# 第三方数据接口说明

本 Mod 不捆绑 External Item Descriptions（EID）的效果说明数据库或运行时代码。

如果玩家已经安装并启用 EID，本 Mod 会在游戏运行时通过 EID 的公开 Lua API 读取 `zh_cn` 道具名称和说明，并转换为适合控制台底栏显示的纯文本。EID 缺失、未启用、版本不兼容或数据不可用时会自动回退，不影响控制台的核心功能。

发布包中的 `scripts/pinyin_aliases.lua` 与 `scripts/object_pinyin_aliases.lua` 是构建时根据 EID `zh_cn` 官方名称列表机械生成的 ASCII 全拼/首字母搜索别名。`scripts/official_objects.lua` 仅保留本 Mod 新目录需要的饰品、卡牌/符文和基础胶囊效果中英文名称，不包含 EID 效果说明、图标、代码或特殊变体数据。生成器使用 Windows Microsoft 中文输入法完成转写；游戏运行时不依赖 Windows 输入法，也不依赖 EID。少量多音字与混合文本纠正位于 `scripts/search_aliases.lua`。

- 项目：External Item Descriptions
- 作者：Wofsauge 及贡献者
- 项目地址：https://github.com/wofsauge/External-Item-Descriptions
- Steam 创意工坊：https://steamcommunity.com/sharedfiles/filedetails/?id=836319872
- API 文档：https://github.com/wofsauge/External-Item-Descriptions/wiki
