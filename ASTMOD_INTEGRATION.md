# AstMod 集成说明

本文说明 AstMod Baseline 如何接入 Competitive Rework，包括框架边界、载入方式、复制资产和验证结果。AstMod → AstRedux 的设计变化和当前开发方向见 `README.md`；SMX 与源码关系见 `PLUGIN_SOURCE_INVENTORY.md`。

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
- `cfg/generalfixes.cfg` 放所有模式都适用的修复与通用体验调整；`l4d_skip_intro.smx` 也在此统一加载，以牺牲少量战役演出换取首关重试速度。竞技模式额外执行 `cfg/competitive_shared.cfg`，因此 Ast 系列不会加载 `playermanagement.smx`、竞技反作弊或竞技地图过渡插件，也不会与自己的 `jointeam.smx` 冲突。
- 模式关闭使用 `pred_unload_plugins`。模式 cfg 不自行调用 `load_unlock`、`unload_all` 或 `load_lock`。
- 100 多条插件加载命令拆分为 `plugins_1.cfg`、`plugins_2.cfg` 和 `plugins_3.cfg`，避免 Source engine command buffer 截断后半段命令。AstMod 的 difficulty manager 在依赖插件之后加载。
- `cfgs.txt` 中旧模式切换条目已删除；Wingman / Hunter 等历史模式没有迁移。ACS 与 `!vote` 会过滤首图未安装的战役，但目录本身仍需人工维护。

## AstMod 运行内容

AstMod 是持续维护的 Baseline。它已同步到 2.8.1 的配置、VScript 和终章需求量规则，并保留资源控制与 `versus_coop_mode.smx`：章节过程中借用 Versus 行为，回合结束时切回 Coop 以继续战役。

- `!vote` 通过 `!ast` 打开玩法调整；`!tz` 作为兼容短命令保留，`!settings` 也继续可用。单人生还者直接调整，多人生还者发起投票；天气和激光不再属于菜单选项。
- 临时玩法调整跨地图保留，最后一名真人离开后延迟恢复当前 DAS/profile 默认值；管理员可用 `!astreset` 立即走同一恢复路径。只有存在非默认调整时才周期播报，新玩家进入时会收到当前人数档和波次状态。
- 新版刷特由作者仓库提交 `c0d829f` 的 `wave_spawner.sp` 编译；2.8.1 运行包只有加载行而缺少成品 SMX。Challenge 仍负责新旧机制投票，旧版实际刷新仍由 VScript 执行，不再在 Challenge 中重复维护新版波次 CVar 和 `!si`。
- 通用功能插件采用 Rework 共享版本；`pause.smx` 以 Rework 6.9 为主体，合入海洋版 `!p`、`!pausepanel` 和 0.1 秒延迟暂停。
- Uzi、消音微冲、木喷、铁喷及确定性霰弹散布已与 Zonemod 同步。旧 weapon-attributes binary 不支持 `reloadduration`，`l4d2_smg_reload_tweak.smx` 会覆盖同步后的换弹参数，因此二者不再使用。
- 旧 `sm_melee ... damageflags` 接口已停用；DAS 的近战对 Tank 倍率继续使用 `sm_weapon melee tankdamagemult`。
- `clip_removal.smx` 仅作为上游文件保留，不加载。它没有源码、用途无法确认，Zonemod 也不使用。
- `astmod.nut` 对模式初始化时的第二次 `update_diff` 增加保护，避免直接切换 matchmode 时出现瞬时 Squirrel 异常。

## 资产与来源边界

- 57 份符合 `cXmY*.cfg` 的 Zonemod 官图 Stripper 已同步到 `cfg/stripper/astmod/maps/`；global filters 和第三方地图文件没有覆盖，校验脚本会比较哈希。
- `addons/astmod.vpk` 提供 `astmod`、`astredux` 和历史 `hunter` mutation。可审阅源文件位于 `assets/astmod_vpk/`，可用 `tools/build_astmod_vpk.ps1` 重建。
- 2026-08-16 与当时 App 222860 的官方 `gamemodes.txt` 比较，当前副本只在末尾追加自定义模式。游戏更新后仍需重新比较，其他携带同名文件的 addon 也可能产生加载顺序冲突。
- AstMod 运行包引入内容主要包括模式 cfg、VScript、Stripper、VPK、`optional/astmod/` 插件池、`cfgs.txt` 及所需 data/gamedata/translations；没有用旧版 SourceMod/MetaMod core 覆盖 Rework。当前 Baseline 以 2.8.1 为更新基准，历史文件不因升级而自动获得源码对应关系。
- 本项目修改并维护 ACS、vote、Challenge 和 AI_HardSI；其余历史二进制的源码覆盖与重建能力以 `PLUGIN_SOURCE_INVENTORY.md` 为准。
- `server.smx` 已移除；空服换图不是必需行为，服务器进程重启应交给 systemd 等宿主服务管理，而不是依赖插件触发 `sv_crash`。
- `tls_restore_vocalize.smx` 已更新为不再需要 `sceneprocessor.smx` 的版本；后者保留在插件池中但不加载，仍需实机确认笑声等 vocalize 功能。

## 校验与测试

静态校验命令：

```powershell
pwsh -File tools/validate_astmod_integration.ps1
```

当前脚本检查必要资产、启用插件加载、生命周期禁手、matchmode 注册、地图过滤、Hard SI 链路、Wave/Challenge 所有权、`generalfixes` 分层、57 份官图 Stripper 哈希和基本 KeyValues 结构；脚本也包含当前 Redux scaffold 的静态检查，其开发状态以 `README.md` 为准。

已在 WSL2 Ubuntu 22.04 Dedicated Server 验证：

- AstMod 冷加载及核心 CVar/plugin 状态；
- 有客户端连接时从 AstMod 切换到 Zonemod，确认 `versus_coop_mode.smx`、ACS、AstMod AI 和投票插件卸载；
- 当前武器参数不再触发旧插件接口报错。

仍需真人验证：

- 完整 `!match`、`!rmatch`、`!vote`、`!mapvote`、`!ast`、`!tz`、`!settings` 和 `!si` 流程；
- 新旧刷特切换、临时调整跨图保留、最后一名真人离开后的自动重置和 `!astreset`；
- 正常完成章节、终章与 ACS 战役切换；
- 至少三轮 AstMod / Zonemod 往返切换。
