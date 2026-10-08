# 第三方数据接口说明

## 物品图标

图标渲染参考 EID 使用 ItemConfig.GfxFileName 与 Sprite 的资源加载机制，但不复制或捆绑 EID 图片、动画或运行时代码。道具和饰品纹理由游戏 ItemConfig 提供；卡牌、符文、碎钥匙及魂石的动画布局从本机原生 CardFronts/HUD 帧核对并生成，运行时读取游戏 `gfx/ui/ui_cardfronts.png` 和 `gfx/ui/ui_cardspills.png`。游戏原生相同外观的符文由名称区分。

药丸目录按效果排列。检索 EID、IsaacDocs 和成熟图标实现后，未发现完整且许可明确的效果专属图标集；依用户要求，没有可用图标时使用原生默认胶囊 HUD，不声称对应本局药丸颜色。游戏资源归原作者所有，发布包不附带上述游戏 PNG。

本 Mod 不捆绑 External Item Descriptions（EID）的效果说明数据库或运行时代码。

如果玩家已经安装并启用 EID，本 Mod 会在游戏运行时通过 EID 的公开 Lua API 读取 `zh_cn` 道具名称和说明，并转换为适合控制台底栏显示的纯文本。EID 缺失、未启用、版本不兼容或数据不可用时会自动回退，不影响控制台的核心功能。

发布包中的 `scripts/pinyin_aliases.lua` 与 `scripts/object_pinyin_aliases.lua` 是构建时根据 EID `zh_cn` 官方名称列表机械生成的 ASCII 全拼/首字母搜索别名。`scripts/official_objects.lua` 仅保留本 Mod 新目录需要的饰品、卡牌/符文和基础胶囊效果中英文名称，不包含 EID 效果说明、图标、代码或特殊变体数据。生成器使用 Windows Microsoft 中文输入法完成转写；游戏运行时不依赖 Windows 输入法，也不依赖 EID。少量多音字与混合文本纠正位于 `scripts/search_aliases.lua`。

- 项目：External Item Descriptions
- 作者：Wofsauge 及贡献者
- 项目地址：https://github.com/wofsauge/External-Item-Descriptions
- Steam 创意工坊：https://steamcommunity.com/sharedfiles/filedetails/?id=836319872
- API 文档：https://github.com/wofsauge/External-Item-Descriptions/wiki
