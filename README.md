# L4D2 AstMod Rework

基于 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 的 求生之路 2 服务端配置，保留 Rework 原药抗框架，并提供 AstRedux 药役。

AstMod (Amethyst) 为 海洋空气 开发的药役模式。Ast作为模式统一简称后，Redux后缀意为在原Mod基础上进行的二次开发修改; AstFlex 的 Flex 后缀本意是低压力休闲模式。

当前主要维护 **AstRedux**，AstFlex 暂停开发。AstMod 已归档至 `archive/astmod-legacy` 分支（`v1.3.0`），主线不再提供或维护。

## 常用入口

- `!match` / `!chmatch` / `!rmatch`：进入、切换或重置模式。
- `!ast`：玩法调整菜单。
- `!si <时间> <数量>`：调整当前地图的特感波次。
- `!mapvote` / `!nextmap` / `!chaptervote`：地图与章节投票。

## 项目文档

- [服务器运维](docs/server-operations.md)
- [更新日志](docs/CHANGELOG.md)
- [开发计划](docs/ROADMAP.md)

## 来源与致谢

框架与大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)。AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件保留各自作者信息；许可见 [LICENSE](LICENSE)。
