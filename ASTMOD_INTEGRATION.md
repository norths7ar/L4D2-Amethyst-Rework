# AstMod 集成说明

本文是 AstMod 系列模式在 Competitive Rework 中的实现与验证依据。项目定位和当前开发方向见 `README.md`；SMX 与源码关系见 `PLUGIN_SOURCE_INVENTORY.md`。

## 命名

| 对象 | 当前名称 |
| --- | --- |
| Baseline matchmode / mutation / VScript / Stripper / plugin namespace | `astmod` |
| 玩家菜单名称 | `AstMod - 药役` |
| Redux matchmode / mutation / VScript | `astredux` |

运行时不再使用旧 `amethyst` namespace；该词只保留在上游历史与版本来源说明中。

## 框架边界

- SourceMod、MetaMod、Confogl、Left4DHooks、扩展、通用修复和基础管理插件由 Competitive Rework 提供。
- AstMod 专属插件统一放在 `addons/sourcemod/plugins/optional/astmod/`，避免服务器启动时自动加载；Redux 专属替代件放在 `optional/astredux/`。
- 不复制 `confogl_autoloader.smx`。模式启动、切换和退出统一使用 Rework 的 `!match`、`!chmatch` 和 `!rmatch`。
- `confoglcompmod.smx`、`match_vote.smx`、`l4d2_skill_detect.smx` 以及当前武器属性插件使用 Rework 版本，不混用 AstMod 的旧副本。
- 模式关闭使用 `pred_unload_plugins`。模式 cfg 不自行调用 `load_unlock`、`unload_all` 或 `load_lock`。
- 100 多条插件加载命令拆分为 `plugins_1.cfg`、`plugins_2.cfg` 和 `plugins_3.cfg`，避免 Source engine command buffer 截断后半段命令。AstMod/AstFlex 的旧 difficulty manager 和 AstRedux 的 Profile Controller 都在依赖插件之后加载。
- `cfgs.txt` 中旧模式切换条目已删除；Wingman / Hunter 等历史模式没有迁移。ACS 与 `!vote` 会过滤首图未安装的战役，但目录本身仍需人工维护。

## 模式实现

### AstMod

AstMod 是持续维护的 Baseline。它保留 2.7.1 的自定义刷特、资源控制和 `versus_coop_mode.smx`：章节过程中借用 Versus 行为，回合结束时切回 Coop 以继续战役。

- `/tz` 也可通过 `!settings` 打开；第二页提供 `ai_hardsi_enable` 投票，每次加载 AstMod 时默认重新开启 Hard SI。
- Uzi、消音微冲、木喷、铁喷及确定性霰弹散布已与 Zonemod 同步。旧 weapon-attributes binary 不支持 `reloadduration`，`l4d2_smg_reload_tweak.smx` 会覆盖同步后的换弹参数，因此二者不再使用。
- 旧 `sm_melee ... damageflags` 接口已停用；DAS 的近战对 Tank 倍率继续使用 `sm_weapon melee tankdamagemult`。
- `clip_removal.smx` 仅作为上游文件保留，不加载。它没有源码、用途无法确认，Zonemod 也不使用。
- `astmod.nut` 对模式初始化时的第二次 `update_diff` 增加保护，避免直接切换 matchmode 时出现瞬时 Squirrel 异常。

### AstRedux

AstRedux 是与 Baseline 并列的实验 ruleset，拥有独立 cfg、mutation、VScript 和专属插件；未修改插件与 Stripper 暂时复用 AstMod 版本。它目前仍是 Versus-backed，Coop-native 底层尚未实现。

Redux 不再加载 `difficulty_adjustment_system.smx`。Profile Controller 从 `addons/sourcemod/configs/astredux_profiles.cfg` 读取 1–4 人最终规则，每秒统计真人生还者并在人数变化后应用新 profile；`sm_astredux_profile_force 1..4` 用于诊断，`0` 恢复自动选择。

| Profile | Tank 最终血量 | 固定近战伤害 | 新版波次 |
| --- | ---: | ---: | --- |
| 1P | 1200 | 300 | 3 特 / 7 秒 |
| 2P | 2550 | 300 | 4 特 / 12 秒 |
| 3P | 4500 | 300 | 6 特 / 22 秒 |
| 4P | 6750 | 300 | 6 特 / 17 秒 |

Controller 把最终 Tank 血量换算为当前 mutation 所需的底层 `z_tank_health`，并只校正之后生成的 Tank；人数变化不追溯修改场上已有 Tank。近战 hook 识别通用 `weapon_melee` 并固定为 300，电锯和不基于该实体类的自定义武器不在此范围。1P No-Witch 与 2P AutoWipe 由 profile CVar 控制常驻 adapter，不靠动态 load/unload。

新版波次根据作者仓库 `c0d829f` 拆分为独立 `wave_spawner.smx`：它独占 `ast_wave_spawn`、`ast_sitimer_new`、`ast_silimit_new`、`!si` 和 Director 波次计时；Redux Challenge 只保留 `/tz` 中的新旧刷特入口，`astredux.nut` 不再重复计数或拦截生成。AstMod Baseline 继续使用 2.7.1 VScript 实现，因为 2.7.1 和 2.8.1 runtime 包都没有提供历史配置引用的 `wave_spawner.smx` 二进制。

当前尚未实现正式的“profile 基线 + `/tz` override layer”：投票修改保持到下一次 profile 变化，恢复默认会重新应用当前 profile。Coop-native 阶段还需要审计第三方地图的 Versus 支持、自制剧情/Boss、Director/VScript、章节推进和固定 Tank 来源。

### AstFlex

AstFlex 是前期减压试验留下的 preview：固定 Advanced、保留 AstMod 自定义刷特、默认关闭 Hard SI 和部分高压规则，并允许游戏提示。它仍复用 AstMod 的 Versus-backed mutation、VScript 和插件池，因此暂停开发；待 Coop-native 底层可行后再作为 Redux ruleset 的减压 preset 继续。

## 资产与来源边界

- 57 份符合 `cXmY*.cfg` 的 Zonemod 官图 Stripper 已同步到 `cfg/stripper/astmod/maps/`；global filters 和第三方地图文件没有覆盖，校验脚本会比较哈希。
- `addons/astmod.vpk` 提供 `astmod`、`astredux` 和历史 `hunter` mutation。可审阅源文件位于 `assets/astmod_vpk/`，可用 `tools/build_astmod_vpk.ps1` 重建。
- 2026-08-16 与当时 App 222860 的官方 `gamemodes.txt` 比较，当前副本只在末尾追加自定义模式。游戏更新后仍需重新比较，其他携带同名文件的 addon 也可能产生加载顺序冲突。
- AstMod 2.7.1 引入内容主要包括模式 cfg、VScript、Stripper、VPK、`optional/astmod/` 插件池、`cfgs.txt`、hostname 配置及所需 data/gamedata/translations；没有用旧版 SourceMod/MetaMod core 覆盖 Rework。
- 本项目修改并维护 ACS、vote、Challenge、AI_HardSI 和 Redux 专属插件；其余历史二进制的源码覆盖与重建能力以 `PLUGIN_SOURCE_INVENTORY.md` 为准。
- `server.smx` 仍会在空服时换图，并暴露基于 `sv_crash` 的管理员重启命令；是否保留需在实机运行后决定。

## 校验与测试

静态校验命令：

```powershell
pwsh -File tools/validate_astmod_integration.ps1
```

当前脚本检查必要资产、311 条启用插件加载、Redux 专属 source/binary/profile、旧 DAS 隔离、生命周期禁手、matchmode 注册、地图过滤、Hard SI 链路、57 份官图 Stripper 哈希和基本 KeyValues 结构。

已在 WSL2 Ubuntu 22.04 Dedicated Server 验证：

- AstMod、AstFlex 和 AstRedux 冷加载及核心 CVar/plugin 状态；
- AstRedux 四档 profile，Wave Spawner 参数、开关、管理员强制刷新及 AstRedux → AstMod → AstRedux 卸载/重载；
- 有客户端连接时从 AstMod 切换到 Zonemod，确认 `versus_coop_mode.smx`、ACS、AstMod AI 和投票插件卸载；
- 当前武器参数不再触发旧插件接口报错。

仍需真人验证：

- 完整 `!match`、`!rmatch`、`!vote`、`!mapvote`、`/tz`、`!settings` 和 `!si` 流程；
- 正常完成章节、终章与 ACS 战役切换；
- Redux 自动人数切档、Tank 存量边界、固定近战伤害、AutoWipe 混合状态和真实波次节奏；
- 至少三轮 AstMod / AstRedux / AstFlex / Zonemod 往返切换。

SteamCMD 备注：2026-07-29 的干净 Ubuntu 环境中，匿名直接下载 App 222860 Linux depot 返回 `Invalid platform`。当时可用的 workaround 是先强制 Windows platform 执行 `app_update 222860 validate`，再对同一目录强制 Linux platform 补齐 Linux layer；以后部署新环境时应重新验证，不能假设该行为永久不变。
