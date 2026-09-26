# Rep+ 重开渐暗修复

中文 2.5.23、英文 2.5.4-en.18 移除死亡结算置顶使用的自定义直通 Shader，
死亡结算菜单回到普通绘制通道，可能被原生遗书遮挡。两个 Workshop 项目均支持
多个运行时，因此统一移除会被引擎预先加载的 Shader；Lua 运行时开关不能阻止
资源加载。R 输入逻辑、存档格式、身份和预览图保持不变。

用户于 2026-09-26 确认中文无 Shader 试验包恢复正常；英文应用相同改动并进行
双语自动回归。不得把英文自动验证或用户反馈扩写为全部运行时实机验收。

一手最小复现来自 Planetarium Chance 作者：
https://www.reddit.com/r/bindingofisaac/comments/1st4hw4/custom_shader_rendering_bug_in_patch_19716/

此前将 ACTION_RESTART 主动轮询认定为根因证据不足。此次修复依据用户对无
Shader 试验包的确认，不修改 R 轮询。其他 Mod 加载自定义 Shader 仍可能触发
同类问题。更新应完整替换 Mod 文件夹，避免旧 content/shaders.xml 残留。

标准 tools/build-workshop-mod.ps1 生成无 Shader 候选；包验证器拒绝残留的
shaders.xml。模拟覆盖菜单、光标和重开生命周期，但不模拟 GPU 原生淡出曲线。
