# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架的服务端配置。仓库保留 Rework 的对抗配置，并新增了 AstMod 药役，以及在 AstMod 基础上开发的 AstRedux 药役。

## 设计取舍

### AstRedux 与 AstMod 的关系

AstMod 是海洋维护的原版Config，最新版本为2.8.1；AstRedux 是轨迹目前正在更新维护的改版插件，目前侧重于简化功能、优化结构，处于早期快速迭代中。计划中的 AstFlex 为 AstRedux 的低压力版预设，供新手朋友使用。

### Redux 用声明式人数 profile 表达基线

旧 Mod 使用的 DAS 通过人数切换整份难度 cfg：数值、插件加载、脚本重载和临时运行行为会一起变动，维护一个规则时往往要追踪多层间接关系。Redux 将 1–4 人的最终基线直接写入 `astredux_profiles.cfg`；Profile Controller 只负责选择和下发，Tank、波次和 AutoWipe 等组件各自负责自己的运行规则。具体数值及当前生效项以 `addons/sourcemod/configs/astredux_profiles.cfg` 为准。

### 尽量复用 Rework，共享能力不复制

Competitive Rework 负责模式生命周期、通用修复、基础管理、投票与对抗规则等共享能力。

服务器没有 matchmode 时，首个客户端进入会由 `cfg/server.cfg` 自动触发 `public_coop`；空服时保持该模式。加载 `campaign_switcher` 的模式在空服倒计时后，会切换到配置的 `campaign_empty_matchmode`（当前为 `public_coop`）并随机选择一张官方战役首图。管理员使用 `sm_forcechangematch <mode> [map]` 手动切换。

`public_coop` 只提供基础管理、依赖、崩溃/过场保护与换图管理，保持普通 Coop 战役参数；它不加载玩法插件、Stripper、VScript、profile、玩家队伍管理、准备/暂停流程或 match_vote。

插件按实际运行生态归类：`optional/` 根目录是跨 Competitive/Coop 通用组件，`optional/competitive/` 是PVP药抗专用插件，`optional/coop/` 是PVE药役专用插件，`optional/astmod/` 是AstMod专用的遗留实现；未加载二进制分别放在 `optional/astmod/disabled/` 与 `plugins/disabled/`。AstRedux 的模式身份留在其 matchmode、cfg、VScript、显示名等模式入口，通用组件保持中性命名。

### 服务器功能与 Ast 配置分开

服务器自己的娱乐和便利功能——例如地图切换、终章下一图投票、公告与管理员维护入口——服务于整台服务器，不属于 Ast 的玩法规则。它们应使用 Rework 的共享入口或独立服务器配置，并在各模式间保持一致。

AstMod/AstRedux 只定义进入 Ast 模式后如何游玩。某项功能是否归入 Ast，取决于它是否改变 Ast 的规则本身，而不是它最早在哪个模式里实现。

### 关于命名

运行时主线使用 `astredux` matchmode、mutation、cfg、VScript 和显示名；`amethyst` 仅用于说明上游历史。

## 入口与维护

- `!match` / `!chmatch` / `!rmatch`：由 Rework 统一进入、切换或重置模式。
- `!ast`：Ast 玩法调整菜单；`!tz` 仅保留为兼容短命令。
- `!si <时间> <数量>`：调整当前地图的波次参数；多人时走投票。
- `!vote`、`!mapvote`、`!nextmap`、`!chaptervote`：服务器通用投票入口。
- `tools/validate_astmod_integration.ps1`：检查必要资产、模式加载链和关键配置结构的静态校验。

配置本身是具体行为的唯一准则；有改动时查看对应 cfg、SourcePawn 源码和 Git 提交历史，而不是在 README 维护第二份规则表或变更日志。

## 相关文档

- [PLUGIN_SOURCE_INVENTORY.md](PLUGIN_SOURCE_INVENTORY.md)：仅列源码关系或可重建状态尚不确定的插件。
- [author/CONFIG_GUIDE.md](author/CONFIG_GUIDE.md)：模式配置的读取入口和分层关系。
- [author/SERVER_OPERATIONS.md](author/SERVER_OPERATIONS.md)：Ubuntu L4D2 服务器的运行维护笔记。

## 上游与致谢

框架和大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)；AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件继续保留各自源码与二进制中的作者信息；许可见 [LICENSE](LICENSE)。
