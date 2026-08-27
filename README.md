# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架、以 AstMod 2.7.1 为 PVE 基础的完整服务端配置。仓库保留 Rework 原有的对抗配置，并把 AstMod 系列做成可以通过 `!match` / `!rmatch` 进入、切换和退出的独立模式。

AstMod 的价值不只是提高数值，而是自定义刷特、Hard SI、资源控制、武器节奏、地图修正和难度投票共同形成的多人药役体验。本项目希望保留这种辨识度，同时逐步解决旧插件、Versus 底层和第三方战役机制之间的冲突。

## 模式

| 模式 | 状态 | 定位 |
| --- | --- | --- |
| **AstMod** | 可用 Baseline | 维护后的个人基线，保留高压药役、自定义刷特和默认开启的 Hard SI；不是未经修改的 2.7.1 历史镜像。 |
| **AstRedux** | 当前开发主线 | 已用声明式人数 profile 替换旧 DAS，并开始把波次、Tank 和 AutoWipe 等规则拆成可维护组件；当前仍借用 Versus，后续目标是可靠的 Coop-native 底层。 |
| **AstFlex** | 暂停开发 | 前期减压玩法的 preview。等 Coop-native 底层可行后，再作为 Redux ruleset 的休闲 preset 继续开发。 |

运行时命名已统一为 `astmod`；AstRedux 使用独立的 `astredux` matchmode、mutation、cfg、VScript 和专属插件。旧名称 `amethyst` 只用于说明上游历史。

## 当前集成

- Competitive Rework 负责 Confogl、通用修复、扩展和模式切换生命周期；AstMod 专属插件隔离在 `addons/sourcemod/plugins/optional/astmod/`。
- AstMod 的 Uzi、消音微冲、木喷、铁喷和确定性霰弹散布已与当前 Zonemod 同步；57 张官图 Stripper 配置也从 Zonemod 同步，未覆盖第三方地图文件和 global filters。
- ACS 与 `!vote` 继续读取人工维护的 `cfgs.txt`，但会隐藏首图尚未安装的战役条目。
- AstRedux 已用 `astredux_profiles.cfg` 和 Profile Controller 接管 1–4 人规则，并用独立 `wave_spawner.smx` 执行新版波次刷特；AstMod Baseline 保留原来的 2.7.1 行为。
- AstFlex 目前仍依赖 AstMod 的 Versus-backed 底层，不能视为第三方战役兼容方案。

## 当前验证状态

已经完成静态集成校验、Ubuntu 22.04 Dedicated Server 冷加载、AstMod/AstRedux 模式加载与卸载、四档 Redux profile、Wave Spawner 管理命令，以及 AstMod → Zonemod 的玩家连接切换验证。

仍需真人完成完整章节与终章、`!match` / `!vote` / `!mapvote` / `/tz` / `!si` 菜单流程、Redux 自动人数切档、Tank 存量边界、固定近战伤害和多轮模式往返测试。当前属于持续开发配置，不提供稳定发布包承诺。

## 文档

- [ASTMOD_INTEGRATION.md](ASTMOD_INTEGRATION.md)：模式实现、集成边界、配置约束和 runtime 验证记录。
- [PLUGIN_SOURCE_INVENTORY.md](PLUGIN_SOURCE_INVENTORY.md)：现有 SMX 的二进制来源、源码线索和可重建边界。
- `tools/validate_astmod_integration.ps1`：必要资产、311 条启用插件加载、57 张官图 Stripper 和关键生命周期约束的静态校验。

## 上游与致谢

框架和大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)；AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件继续保留各自源码与二进制中的作者信息；许可见 [LICENSE](LICENSE)。
