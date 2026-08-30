# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架、以 AstMod 2.8.1 为 PVE 基础的完整服务端配置。仓库保留 Rework 原有的对抗配置，并把 AstMod 系列做成可以通过 `!match` / `!rmatch` 进入、切换和退出的独立模式。

AstMod 的价值不只是提高数值，而是自定义刷特、Hard SI、资源控制、武器节奏、地图修正和难度投票共同形成的多人药役体验。本项目希望保留这种辨识度，同时逐步解决旧插件、Versus 底层和第三方战役机制之间的冲突。

## 模式

| 模式 | 状态 | 定位 |
| --- | --- | --- |
| **AstMod** | 可用 Baseline | 以 2.8.1 更新后的运行规则为基础，保留高压药役、自定义刷特和默认开启的 Hard SI；不是未经修改的历史镜像。 |
| **AstRedux** | 当前开发主线 | 已用声明式人数 profile 替换旧 DAS，并开始把波次、Tank 和 AutoWipe 等规则拆成可维护组件；当前仍借用 Versus，后续目标是可靠的 Coop-native 底层。 |
| **AstFlex** | 暂停开发 | 前期减压玩法的 preview。等 Coop-native 底层可行后，再作为 Redux ruleset 的休闲 preset 继续开发。 |

运行时命名已统一为 `astmod`；AstRedux 使用独立的 `astredux` matchmode、mutation、cfg、VScript 和专属插件。旧名称 `amethyst` 只用于说明上游历史。

## AstMod 与 AstRedux

AstMod 是可玩的维护基线，接入 Competitive Rework 所必需的兼容修改以及已经确认适合 Baseline 的改进仍可继续合入；它不是冻结的 2.7.1 副本。AstRedux 则是与 Baseline 隔离的规则实验：先复用未改动的 AstMod 资产，再逐项替换难以理解、难以维护或妨碍第三方战役兼容的底层规则。Redux 的实验不会自动回写 AstMod。

| 方面 | AstMod Baseline | AstRedux 当前实验 |
| --- | --- | --- |
| 人数规则 | `difficulty_adjustment_system.smx` 按人数选择 Easy / Normal / Hard / Impossible cfg | Profile Controller 读取 `astredux_profiles.cfg`，直接选择 1P–4P profile |
| 人数语义 | 以仍在生还者队伍中的真人数量为准 | 保留同一语义：玩家退出会降档，玩家死亡但没有退出不会降档 |
| 规则表达 | 每个难度 cfg 同时修改 Tank、特感、尸潮、互动时长、药品和插件状态 | 每个 profile 声明该人数档的最终规则，由常驻 Controller 和 adapter 执行 |
| Tank 与近战 | Tank 基础血量、mutation 倍率、引擎百分比伤害和 `tankdamagemult` 共同决定结果 | Profile 直接声明 Tank 最终血量和固定近战伤害；当前均为每刀 300，电锯除外 |
| 已生成的 Tank | 沿用旧 DAS 行为 | 人数变化立即覆盖新规则，但不追溯修改场上已经生成的 Tank |
| 刷特 | 使用海洋源码仓库提交 `c0d829f` 的 `wave_spawner.sp`，保留 Challenge 中的新旧机制投票；旧机制仍由 VScript 执行 | 复用同一 Wave Spawner，由声明式 profile 提供当前人数档的波次数量与间隔 |
| 长期方向 | 维持可玩的 Versus-backed 药役基线 | 审查波次、Tank、AutoWipe 等规则，并寻找可靠的 Coop-native 底层 |

### 为什么替换旧 DAS

旧 DAS 的人数识别本身不是主要问题：它统计真人生还者而不要求仍然存活，所以“有人退出才降档，游戏内死亡不降档”符合本项目的预期。问题主要在于规则的表达和执行方式。

- DAS 把 1–4 人映射成 Easy、Normal、Hard、Impossible，再执行一整份 cfg。一个人数变化会同时改变数十个 CVar、加载或卸载插件、重载伤害播报并执行 `sm_reloadscript`，不同职责被绑在同一次切档中。
- Tank 近战伤害不能从任何一个数值直接读出。例如 1P cfg 设置 `z_tank_health 800`，经过当前 mutation 的 1.5 倍得到 1200 最终血量；引擎近战以最大血量的 5% 计算为 60，再由 `tankdamagemult 5.0` 乘回约 300。4P 则是 4500 × 1.5 得到 6750，再以 5% × 0.9 得到约 304。维护者必须同时理解 cfg、mutation、引擎规则和武器属性插件，才能知道最终结果。
- `tankdamagemult` 依赖武器属性插件的具体接口和二进制行为；更换插件版本后，即使 cfg 没变，伤害链路也可能失效或改变。插件动态 load/unload 与 Rework 负责的模式生命周期也存在职责重叠。
- 一份 cfg 同时承担“数值表”和“执行脚本”，难以区分哪些是人数基线、哪些是运行时开关，也不利于以后让 `/tz` 投票作为临时 override 覆盖 profile。

Redux 因此把人数档改为声明式 profile：配置直接写最终 Tank 血量、固定近战伤害、刷特参数和各项 CVar。当前 Controller 负责选择 profile、下发 CVar以及执行 Tank 与 No-Witch 规则，AutoWipe 等独立 adapter 常驻加载并由 profile CVar 控制。当前数值如下，完整配置以 [`addons/sourcemod/configs/astredux_profiles.cfg`](addons/sourcemod/configs/astredux_profiles.cfg) 为准。

| Profile | Tank 最终血量 | 固定近战伤害 | 当前波次参数 |
| --- | ---: | ---: | --- |
| 1P | 1200 | 300 | 3 特 / 10 秒 |
| 2P | 2550 | 300 | 3 特 / 15 秒 |
| 3P | 4500 | 300 | 5 特 / 26 秒 |
| 4P | 6750 | 300 | 6 特 / 22 秒 |

Profile Controller 每秒检查人数，并在 `player_team` 后补做一次检查；管理员可用 `sm_astredux_profile_force 1..4` 强制诊断，使用 `0` 恢复自动选择。AstRedux 已形成“profile 基线 + 临时 override”分层：玩家死亡不降档，玩家退出后新 profile 立即成为后续规则来源，但不追溯修改场上已经生成的 Tank。临时玩法调整会跨地图保留；最后一名真人离开后延迟恢复当前人数档默认值，管理员也可用 `!astreset` 立即恢复。

## 当前集成

- Competitive Rework 负责 Confogl、通用修复、扩展和模式切换生命周期；AstMod 专属插件隔离在 `addons/sourcemod/plugins/optional/astmod/`。
- `cfg/generalfixes.cfg` 保留所有模式都适用的修复与通用体验调整；竞技规则位于 `cfg/competitive_shared.cfg`，Ast 系列只加载 `jointeam.smx`，不会同时加载 `playermanagement.smx`。
- `pause.smx` 以 Competitive Rework 6.9 为主体，合入 `!p`、`!pausepanel` 和 0.1 秒延迟暂停；换位、插值、旁观速率、开位和 Boss 投票统一使用 Rework 的共享版本。
- AstMod 的 Uzi、消音微冲、木喷、铁喷和确定性霰弹散布已与当前 Zonemod 同步；57 张官图 Stripper 配置也从 Zonemod 同步，未覆盖第三方地图文件和 global filters。
- ACS 与 `!vote` 继续读取人工维护的 `cfgs.txt`，但会隐藏首图尚未安装的战役条目。
- `!vote` 中的 Ast 玩法入口改为 `!ast`；`!tz` 保留为短兼容命令，`!settings` 继续可用。天气和激光已从玩法菜单移除；单人生还者直接调整并广播，多人生还者必须投票。
- AstRedux 与 Baseline 的差异、旧 DAS 的问题和当前 profile 记录在上节；AstMod Baseline 仍保留 DAS，但已同步 2.8.1 的波次参数和功能更新。
- AstFlex 目前仍依赖 AstMod 的 Versus-backed 底层，不能视为第三方战役兼容方案。

## 当前验证状态

旧版整合已经完成 Ubuntu 22.04 Dedicated Server 冷加载、AstMod/AstRedux 模式加载与卸载、四档 Redux profile，以及 AstMod → Zonemod 的玩家连接切换验证。本轮 2.8.1 升级已经完成源码编译和静态集成校验，但尚未重新进行 Dedicated Server 运行测试。

仍需真人完成完整章节与终章、`!match` / `!vote` / `!mapvote` / `!ast` / `!si` 菜单流程、新旧刷特切换、临时 override 跨图与空服重置、Redux 自动人数切档、Tank 存量边界、固定近战伤害和多轮模式往返测试。当前属于持续开发配置，不提供稳定发布包承诺。

## 文档

- [ASTMOD_INTEGRATION.md](ASTMOD_INTEGRATION.md)：AstMod 接入 Competitive Rework 的文件、生命周期、资产与验证说明。
- [PLUGIN_SOURCE_INVENTORY.md](PLUGIN_SOURCE_INVENTORY.md)：现有 SMX 的二进制来源、源码线索和可重建边界。
- `tools/validate_astmod_integration.ps1`：必要资产、启用插件加载、57 张官图 Stripper 和关键生命周期约束的静态校验。

## 上游与致谢

框架和大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)；AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件继续保留各自源码与二进制中的作者信息；许可见 [LICENSE](LICENSE)。
