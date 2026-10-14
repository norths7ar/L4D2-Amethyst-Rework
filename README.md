# AstRedux

以 **AstRedux 药役**为主要维护方向的求生之路 2 服务端配置，基于 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)，同时保留 Zone 系列药抗模式。

AstRedux 基于海洋空气开发的 AstMod（Amethyst）继续开发，支持 1–4 人游玩，难度随人数调整。

除 AstRedux 外，当前提供 ZoneMod 与 ZoneHunters 的 1v1～4v4，以及 ZoneRetro 4v4。

## 常用入口

- `!match` / `!chmatch` / `!rmatch`：进入、切换或重置模式。
- `!ast`：玩法调整菜单。
- `!mset`：管理员地图规则菜单，保存本图路程 Boss、支持的救援轮次与开场动画设置。
- `!si <时间> <数量>`：调整当前地图的特感波次。
- `!mapvote` / `!nextmap` / `!chaptervote`：地图与章节投票。

## 项目文档

- [服务器运维](docs/server-operations.md)
- [框架配置架构](docs/architecture.md)
- [更新日志](docs/CHANGELOG.md)
- [开发计划](docs/ROADMAP.md)
- [AstRedux 设计决策](docs/astredux-design.md)

### 详细配置文档

- [地图规则配置](docs/configuration/map-rules.md)
- [资源规则配置](docs/configuration/resource-rules.md)

## 来源与致谢

本项目此前维护的 AstMod 已归档至 `archive/astmod-legacy` 分支（`v1.3.0`），主线不再提供或维护。

框架与大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)。AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件保留各自作者信息；许可见 [LICENSE](LICENSE)。
