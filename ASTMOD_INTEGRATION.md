# AstMod 集成说明

本仓库是在 L4D2 Competitive Rework 基础上维护的一份独立集成版本。

## 命名

- Competitive Rework matchmode ID：`astmod`
- 面向玩家的名称：`AstMod - 药役`
- L4D2 mutation 与共享资产 namespace：`astmod`
- AstRedux matchmode / mutation / VScript ID：`astredux`

运行时命名现已统一为 `astmod`：VPK、VScript、Stripper、插件目录和主配置不再使用旧 `amethyst` 。旧名称只保留在上游历史和版本来源说明中。

## 集成决策

- SourceMod、MetaMod、Confogl、Left4DHooks、扩展、全局修复 和基础管理插件由 Competitive Rework 提供并负责维护。
- 原先位于 AstMod plugins 根目录的专属插件已移动到 `addons/sourcemod/plugins/optional/astmod/`，避免它们自动加载。
- 没有复制 `confogl_autoloader.smx`。模式启动、退出、切换统一交给 Competitive Rework，通过 `!match`、`!chmatch` 和 `!rmatch` 完成。
- `confoglcompmod.smx` 和 `match_vote.smx` 使用 Competitive Rework 的版本，并在 AstMod plugin 配置末尾加载，与其他药抗模式保持一致。
- 模式关闭使用 `pred_unload_plugins`；AstMod 配置文件不自行管理插件加载锁，也不直接调用 `unload_all`。
- `optional/l4d2_skill_detect.smx` 使用 Rework 版本，而不是较旧的 AstMod 副本。两者对 translations 文件格式的约定不同，在模式切换过程中混用 AstMod 二进制和 Rework translations 存在风险。
- AstMod `cfgs.txt` 中旧有的模式切换部分已删除。原包内的 Wingman / Hunter等模式未作迁移。
- ACS 和 `!vote` 读取 `cfgs.txt` 时，会自动忽略服务器端不存在的地图。但目前 `cfgs.txt` 仍需手动维护。

## 玩法变体

### `astmod`

AstMod 是当前可用且持续维护的 Baseline。它保留原版的自定义刷特、默认开启的 Hard SI AI、资源控制和借用 Versus 行为的 `versus_coop_mode.smx`；章节过程中使用 Versus，回合结束时切回 Coop 以继续战役流程。

- 现有 `/tz` 菜单也可以通过 `!settings` 打开，第二页提供 `ai_hardsi_enable` 总开关投票；每次加载 `astmod` 时默认重新开启 Hard SI AI。
- Uzi、消音微冲、木喷、铁喷和确定性霰弹散布已与 Zonemod 同步；AstMod 自己的武器替换规则、栓狙路线和 PVE 备弹限制仍然保留。
- 当前加载 Zonemod 的 `optional/l4d2_weapon_attributes.smx` 和 `optional/l4d2_static_shotgun_spread.smx`。旧 AstMod weapon-attributes binary 不支持 `reloadduration`，因此不再使用；`l4d2_smg_reload_tweak.smx` 也保持停用，避免覆盖同步后的换弹行为。
- AstMod 旧有的 `sm_melee ... damageflags` 命令已经停用，因为当前 Zonemod plugin 不再提供该接口；DAS 的近战对 Tank 倍率继续使用 `sm_weapon melee tankdamagemult`。
- `clip_removal.smx` 作为上游文件保留但不加载。它没有源码，行为无法确认，海洋也无法确定用途，Zonemod 同样不使用该插件。
- `astmod.nut` 为模式初始化期间的第二次 `update_diff` 回调增加了保护，避免直接切换 matchmode 时因 `g_ModeScript` 尚未包含该回调而短暂产生 Squirrel 异常。

### `astredux`

AstRedux 已从当前 AstMod Baseline 初始化并注册为 `AstRedux - 实验药役`。它拥有独立的 `cfg/cfgogl/astredux/`、`astredux` mutation、`astredux.nut` 和 `optional/astredux/`；未修改插件继续从 `optional/astmod/` 加载，Stripper 暂时复用 `cfg/stripper/astmod/`。这仍是 Versus-backed 并行实验容器，不代表 Coop-native 规则已经实现。

Redux 第一项大改已经落地：它不再加载旧 `difficulty_adjustment_system.smx`，而是从 `addons/sourcemod/configs/astredux_profiles.cfg` 读取 1–4 人声明式 profile。Controller 每秒统计真人生还者并在人数变化后立即应用新规则；`sm_astredux_profile_force 1..4` 可用于诊断，`0` 恢复自动选择。Profile 只描述目标状态，Controller 负责选择与编排，Tank/AutoWipe/VScript 等 adapter 负责引擎细节。

| Profile | 新 Tank 最终血量 | 固定近战伤害 | 自定义刷特 |
| --- | ---: | ---: | --- |
| 1P | 1200 | 300 | 3 特 / 7 秒 |
| 2P | 2550 | 300 | 4 特 / 12 秒 |
| 3P | 4500 | 300 | 6 特 / 22 秒 |
| 4P | 6750 | 300 | 6 特 / 17 秒 |

Tank 血量在 profile 中写最终可读值，Controller 再把当前 mutation 的 1.5 倍引擎系数换算为 `z_tank_health`，并只在后续 `tank_spawn` 时校正实体最大/当前血量；人数变化不会追溯扣改场上已有 Tank。近战不枚举脚本武器名，而是在伤害 hook 中识别通用 `weapon_melee` 并固定为 300；电锯和不基于该实体类的自定义武器不在此范围。1P No-Witch 和 2P AutoWipe 也不再通过动态 load/unload 切换：Redux Controller 负责开关，常驻 adapter 执行行为。

Redux 专用 `challenge.smx` 继续提供 `/tz`，读取 `astredux_profile_current` 而不是旧 `das_fakedifficulty`，VScript 的新旧刷特路径也都改读 Redux cvar。当前尚未实现正式的“profile 基线 + `/tz` override layer”：投票修改可保持到下一次 profile 变化，恢复默认会重新应用当前 profile；这部分要在后续单独设计，避免 Controller 和投票互相覆盖。

下一阶段会继续逐项审计并重建真正需要的 Versus 特性。目标仍是建立可用于第三方战役的 Coop-native 底层，重点包括不支持 Versus 的第三方地图、自制剧情与 Boss、地图自己的 Director/VScript，以及章节和终章推进。

### `astflex`

现有 AstFlex 配置来自前期关于减压玩法的讨论：固定 Advanced、保留 AstMod 自定义刷特、默认关闭 Hard SI AI 和部分高压伤害/自动修正、使用 `_lite` 人数 profile，并允许第三方地图显示路线和机关提示。这些修改作为实验记录继续保留，但 AstFlex 当前仍复用 AstMod 的 Versus-backed mutation、VScript 和插件集合，因此没有解决第三方地图不支持 Versus 或脚本被接管的问题。

AstFlex 现已暂停开发。当前方向是先完成 AstRedux 或找到其他可行的 Coop-native 方案；只有底层能够可靠进入并尊重第三方战役后，才会重新启动 AstFlex，并把它设计成该 Coop ruleset 上的减压 preset，而不是第三套重复实现。

## Stripper 同步

Zonemod 中符合 `cXmY*.cfg` 命名规则的 57 份官图文件已同步到 `cfg/stripper/astmod/maps/`。global filters 和第三方地图文件没有被覆盖。校验脚本会比较这些官图文件的哈希，避免后续 Zonemod 更新后 AstMod 副本在无人察觉的情况下发生偏离。

## 从 AstMod 2.7.1 引入的文件

- 模式 cfg，集成到 `cfg/cfgogl/astmod/`
- `cfg/stripper/astmod/`
- `cfg/sourcemod/difficulty_adjustment_system/`
- `scripts/vscripts/astmod.nut`
- `addons/astmod.vpk`，解包源文件保存在 `assets/astmod_vpk/`
- `addons/sourcemod/plugins/optional/astmod/`
- `vote.smx`、`all4dead2.smx`、`server.smx`、`hostname.smx` 和 `sceneprocessor.smx`，统一迁移到 `optional/astmod/`
- `addons/sourcemod/configs/cfgs.txt`
- `addons/sourcemod/configs/hostname/`
- 已包含插件所需的 AstMod 专用 data、gamedata 和 translations 文件
- 本项目修改过的 `ACS`、`vote`、`challenge` 和 `AI_HardSI` 的集成源码，以及本地编译依赖

AstMod 自带的 SourceMod/MetaMod core files 和扩展没有复制，同名的 Competitive Rework core files 也没有被旧版 AstMod 文件覆盖。

## 待解决问题

### `astmod.vpk`

`astmod.vpk` 在 `scripts/gamemodes.txt` 中提供 `astmod`、`astredux` 和历史 `hunter` 条目。VPK 已拆出可审阅源文件，并可通过 `tools/build_astmod_vpk.ps1` 重建。2026-08-16 从本机 App 222860 的 `update/pak01_dir.vpk` 提取现行官方文件后逐行比较，AstMod 副本只在文件末尾追加自定义模式，没有修改任何内置模式；`astmod` 与 `astredux` mutation 及各自 VScript 均已在 WSL2 实际加载。当前剩余风险包括游戏未来更新后副本可能落后，以及其他同样携带 `scripts/gamemodes.txt` 的 addon 可能产生加载顺序冲突。历史 `hunter` 条目目前未使用，可在后续清理。

### 缺失的 `wave_spawner.smx`

AstMod 2.7.1 plugin 配置引用了 `optional/astmod/wave_spawner.smx`，但 runtime 包和提供的源码归档中都没有该文件。在找到缺失组件或确认预期替代品之前，对应加载行会以禁用注释的形式保留。

### 尚未完成的 runtime 验证

AstMod 提供的源码归档没有覆盖大部分当前启用的插件。Linux 核心插件加载、模式切换、战役过滤、Hard SI AI 开关和资源限制已经实际测试；游戏内投票菜单、正常完成章节以及终章后的战役切换，仍需要有玩家连接的实机测试。

### `server.smx`

这个 AstMod plugin 已隔离在模式内部，但它可以在服务器变为空服时换图，并暴露一个通过 `sv_crash` 实现的管理员重启命令。是否需要这些行为，应在实机运行测试后决定。

## 静态校验

在本目录运行：

```powershell
pwsh -File tools/validate_astmod_integration.ps1
```

校验脚本会检查必要资产、三种模式合计 310 条有效插件加载项、Redux 专属 plugin/source/profile、旧 DAS 隔离、禁止使用的生命周期命令、matchmode 注册、地图过滤、Hard SI AI 开关链路、57 份官图 Stripper 哈希，以及基本的 KeyValues 花括号平衡。

## 验证与测试环境

下面的 runtime checklist 不绑定具体环境。目前真正执行过的是 WSL2 desktop 部署；Ubuntu VPS 仍在计划中，尚未部署或验证。没有实际运行过的环境，不应被标记为已验证。

AstMod 的 100 多条插件加载命令被拆分到 `plugins_1.cfg`、`plugins_2.cfg` 和 `plugins_3.cfg`：单个 cfg 在 `generalfixes.cfg` 之后超过了 Source engine command buffer，导致后续框架插件在没有明显报错的情况下停止加载。AstMod/AstFlex 的旧 difficulty manager 继续最后加载；AstRedux 在同一位置改为最后加载 Profile Controller，确保它应用 profile 时其他插件拥有的 cvar 已经存在。

### Runtime checklist（与环境无关）

1. [x] 在没有已激活 matchmode 的情况下冷启动。
2. [ ] 通过游戏内 `!match` 菜单加载 AstMod。（WSL2 desktop 环境已验证控制台命令 `sm_forcematch astmod`。）
3. [x] 检查 `sm plugins list`、SourceMod errors、missing natives 和 gamedata failures。
4. [x] 检查 AstMod 与 AstFlex 的核心 cvar 和插件状态；AstRedux 已在 WSL2 冷加载，确认 `mp_gamemode astredux`、`astredux.nut`、Baseline Stripper 路径、三份 Redux 专属插件和旧 DAS 未加载，并逐档验证 1P–4P profile cvar。
5. [ ] 正常完成一个章节和一个终章。
6. [ ] 在有玩家连接的环境下验证 ACS `!mapvote`、`!vote`、`/tz` 和战役切换。
7. [ ] 通过 `!rmatch` 退出，确认所有 AstMod 专属插件都已卸载。
8. [x] 在有客户端连接的情况下从 AstMod 直接切换到 Zonemod；该流程已在 WSL2 验证，并确认 `versus_coop_mode.smx`、ACS、AstMod AI 和 AstMod 投票插件均已卸载。
9. [ ] 切回 AstMod。
10. [ ] 至少重复三次切换流程，并检查残留 cvar、重复命令、插件加载失败和崩溃。
11. [ ] 有真人连接时验证 AstRedux 自动人数切档、现有/新生 Tank 边界和固定近战伤害。

标记为 `[x]` 的项目都在下面记录的已执行环境中实际验证过。未勾选项目仍需要有玩家连接的测试；最终先在哪个环境完成并不预设。

### 已执行环境：WSL2 desktop

这只是一个实际测试环境，不是项目规格：

- WSL 发行版：`Ubuntu-22.04`
- 服务账号：`l4d2`（密码已锁定）
- SteamCMD：`/home/l4d2/steamcmd`
- Dedicated server：`/home/l4d2/server`
- 可审阅的集成快照：`/home/l4d2/integration`
- 本地测试覆盖配置：`cfg/astmod_test.cfg`

### 计划环境：Ubuntu VPS

计划在租用的 Ubuntu VPS 上部署 Dedicated Server。目前尚未完成 VPS 安装、服务配置、端口配置或 runtime 验证，本文任何内容都不应被理解为已经通过 VPS 验证。在它仍处于计划阶段时，不要把 WSL2 特有的 host path 照搬到这里；VPS 上线后，应对它执行同一份 checklist 并在此记录结果，无需改变 checklist 本身的表述。

### SteamCMD anonymous download 说明

截至 2026-07-29，在全新环境中匿名下载 App 222860 的 Linux 版本会返回 `Invalid platform`。这看起来是 SteamCMD 的匿名下载行为，而不是 WSL2 特有的问题。已经验证的 workaround 是：先设置 `@sSteamCmdForcePlatformType windows` 并执行 `app_update 222860 validate`，随后针对同一安装目录改为 `@sSteamCmdForcePlatformType linux` 再执行一次；第一遍安装共享内容，第二遍补齐 Linux platform layer。如果以后干净的 Ubuntu VPS 不再遇到这个问题，应在这里记录实际情况，而不是假设该 workaround 永远必需。
