# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架的服务端配置。仓库保留 Rework 的对抗配置，并提供当前 Coop/PVE 主线 AstRedux 与 legacy 兼容模式 AstMod；AstFlex 暂停，仅接受避免路径断裂的机械维护。

## 设计取舍

### AstRedux 是当前 Coop/PVE 主线

AstRedux 是正式的当前玩法主线，使用 Coop/PVE 配置与组件。AstMod 保留为 legacy 兼容模式，供既有配置与资产继续工作，不再作为共享层的稳定主导。

### Redux 用声明式人数 profile 表达基线

旧 DAS 通过人数切换整份难度 cfg：数值、插件加载、脚本重载和临时运行行为会一起变动，维护一个规则时往往要追踪多层间接关系。Redux 将 1–4 人的最终基线直接写入 `astredux_profiles.cfg`；Profile Controller 只负责选择和下发，Tank、波次和 AutoWipe 等组件各自负责自己的运行规则。具体数值及当前生效项以 `addons/sourcemod/configs/astredux_profiles.cfg` 为准。

### 尽量复用 Rework，共享能力不复制

Competitive Rework 负责模式生命周期、通用修复、基础管理、投票与对抗规则等共享能力。Ast 系列优先复用这些组件，避免维护两套同类机制；所有模式都适用的调整应放在共享配置，而不是藏进 Ast 专属目录。

插件按实际运行生态归类：`optional/` 根目录是跨 Competitive/Coop 通用组件，`optional/competitive/` 是 Human Survivor-vs-Infected PVP 专属，`optional/coop/` 是 Coop/PVE 与共享 Coop 组件，`optional/astmod/` 是 AstMod legacy 特有实现；未加载二进制分别放在 `optional/astmod/disabled/` 与 `plugins/disabled/`。不要新增 `legacy/` 或 `versus/` 目录。AstRedux 的模式身份留在其 matchmode、cfg、VScript、显示名等模式入口，通用组件保持中性命名。

### 服务器功能与 Ast 配置分开

服务器自己的娱乐和便利功能——例如地图切换、终章下一图投票、公告与管理员维护入口——服务于整台服务器，不属于 Ast 的玩法规则。它们应使用 Rework 的共享入口或独立服务器配置，并在各模式间保持一致。

AstMod/AstRedux 只定义进入 Ast 模式后如何游玩。某项功能是否归入 Ast，取决于它是否改变 Ast 的规则本身，而不是它最早在哪个模式里实现。

## 模式

| 模式 | 定位 |
| --- | --- |
| **AstRedux** | 当前 Coop/PVE 玩法主线，以声明式 profile 和独立 Coop 组件运行。 |
| **AstMod** | legacy 兼容模式，保留既有 AstMod 玩法与资产入口。 |
| **AstFlex** | 暂停；仅接受避免路径断裂的机械维护。 |

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
