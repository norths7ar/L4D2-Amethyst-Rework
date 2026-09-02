# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架、以 AstMod 2.8.1 为 PVE 基础的服务端配置。仓库保留 Rework 的对抗配置，并提供 AstMod 与 AstRedux 两套药役模式。

## 设计取舍

### 保留 AstMod Baseline，同时发展 AstRedux

AstMod Baseline 是已经能玩的维护基线：它保留 Ast 系列的玩法辨识度，也承接已经确认适合这套玩法的兼容修复和改进。AstRedux 则是独立的规则实验，用来逐项替换旧实现中职责缠绕、难以维护或对第三方战役不友好的部分。

### Redux 用声明式人数 profile 表达基线

旧 DAS 通过人数切换整份难度 cfg：数值、插件加载、脚本重载和临时运行行为会一起变动，维护一个规则时往往要追踪多层间接关系。Redux 将 1–4 人的最终基线直接写入 `astredux_profiles.cfg`；Profile Controller 只负责选择和下发，Tank、波次和 AutoWipe 等组件各自负责自己的运行规则。具体数值及当前生效项以 `addons/sourcemod/configs/astredux_profiles.cfg` 为准。

### 尽量复用 Rework，共享能力不复制

Competitive Rework 负责模式生命周期、通用修复、基础管理、投票与对抗规则等共享能力。Ast 系列优先复用这些组件，避免维护两套同类机制；所有模式都适用的调整应放在共享配置，而不是藏进 Ast 专属目录。

只有 Ast 特有的玩法规则才放在 `optional/astmod/` 或 `optional/astredux/`：例如 Ast 的波次、资源、Tank、AI 和玩法调整。这样 Ast 的规则可以独立演进，同时不会把 Rework 的公共层改成只能服务 Ast。

### 服务器功能与 Ast 配置分开

服务器自己的娱乐和便利功能——例如地图切换、终章下一图投票、公告与管理员维护入口——服务于整台服务器，不属于 Ast 的玩法规则。它们应使用 Rework 的共享入口或独立服务器配置，并在各模式间保持一致。

AstMod/AstRedux 只定义进入 Ast 模式后如何游玩。某项功能是否归入 Ast，取决于它是否改变 Ast 的规则本身，而不是它最早在哪个模式里实现。

## 模式

| 模式 | 定位 |
| --- | --- |
| **AstMod** | 可玩的维护 Baseline，保留高压药役、自定义刷特和 Hard SI。 |
| **AstRedux** | 当前开发主线，以声明式 profile 和独立玩法组件逐步重建规则。 |
| **AstFlex** | 暂停的休闲 preset 预览，等待 Redux 的 Coop-native 底层成熟后再继续。 |

运行时 Baseline 使用 `astmod`，Redux 使用独立的 `astredux` matchmode、mutation、cfg、VScript 和插件；`amethyst` 仅用于说明上游历史。

## 待定决策（AstFlex，暂停开发）

AstFlex 当前只保留预览配置，不为它继续拆分插件或扩展菜单。恢复开发时再统一决定：

- 是否允许玩家按房间情况投票开关 Hunter deadstop，以及默认值。
- 是否允许玩家投票开关 Hard SI，以及默认值。
- AstFlex 的玩法菜单应使用独立编译产物，还是由共享插件在运行时识别模式。
- AstMod、AstRedux、AstFlex 之间哪些玩法插件继续复用，哪些应由各模式独立持有。

这些问题不影响当前支持模式：AstMod 与 AstRedux 固定启用 Hunter no-deadstop 和 Hard SI，`!ast` 不提供对应开关。

## 入口与维护

- `!match` / `!chmatch` / `!rmatch`：由 Rework 统一进入、切换或重置模式。
- `!ast`：Ast 玩法调整菜单；`!tz` 仅保留为兼容短命令。
- `!si <时间> <数量>`：调整 AstRedux 当前地图的波次参数；多人时走投票。
- `!vote`、`!mapvote`、`!nextmap`、`!chaptervote`：服务器通用投票入口。
- `tools/validate_astmod_integration.ps1`：检查必要资产、模式加载链和关键配置结构的静态校验。

配置本身是具体行为的唯一准则；有改动时查看对应 cfg、SourcePawn 源码和 Git 提交历史，而不是在 README 维护第二份规则表或变更日志。

## 相关文档

- [PLUGIN_SOURCE_INVENTORY.md](PLUGIN_SOURCE_INVENTORY.md)：仅列源码关系或可重建状态尚不确定的插件。
- [author/CONFIG_GUIDE.md](author/CONFIG_GUIDE.md)：模式配置的读取入口和分层关系。
- [author/SERVER_OPERATIONS.md](author/SERVER_OPERATIONS.md)：Ubuntu L4D2 服务器的运行维护笔记。

## 上游与致谢

框架和大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)；AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件继续保留各自源码与二进制中的作者信息；许可见 [LICENSE](LICENSE)。
