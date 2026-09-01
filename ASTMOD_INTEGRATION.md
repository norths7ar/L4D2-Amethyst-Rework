# AstMod 集成说明

本文说明 AstMod Baseline 如何接入 Competitive Rework，包括框架边界、载入方式、复制资产和验证结果。AstMod → AstRedux 的设计变化和当前开发方向见 `README.md`；SMX 与源码关系见 `PLUGIN_SOURCE_INVENTORY.md`。

## 命名

| 对象 | 当前名称 |
| --- | --- |
| Baseline matchmode / mutation / VScript / Stripper / plugin namespace | `astmod` |
| 玩家菜单名称 | `AstMod - 药役` |
| Redux matchmode / mutation / VScript | `astredux` |

运行时统一使用 `astmod` namespace；`amethyst` 用于上游历史与版本来源说明。

## 框架边界

- SourceMod、MetaMod、Confogl、Left4DHooks、扩展、通用修复和基础管理插件由 Competitive Rework 提供。
- AstMod 专属插件统一放在 `addons/sourcemod/plugins/optional/astmod/`，避免服务器启动时自动加载；Redux 专属替代件放在 `optional/astredux/`。
- 模式启动、切换和退出由 Rework 的 `!match`、`!chmatch` 和 `!rmatch` 统一处理。
- `confoglcompmod.smx`、`match_vote.smx`、`l4d2_skill_detect.smx` 与武器属性插件使用 Rework 共享版本。
- `cfg/generalfixes.cfg` 放所有模式都适用的修复与通用体验调整；`l4d_skip_intro.smx` 也在此统一加载，以首关重试速度为目标。竞技模式额外执行 `cfg/competitive_shared.cfg`；Ast 系列加载 `jointeam.smx`，竞技模式加载 `playermanagement.smx`、反作弊和地图过渡插件。
- Rework 以 `pred_unload_plugins` 完成模式关闭；其生命周期覆盖 `load_unlock`、`unload_all` 与 `load_lock`。
- 100 多条插件加载命令拆分为 `plugins_1.cfg`、`plugins_2.cfg` 和 `plugins_3.cfg`，避免 Source engine command buffer 截断后半段命令。AstMod 的 difficulty manager 在依赖插件之后加载。
- `missioncycle.txt` 是 Campaign Switcher 的 Map 策略文件，只维护允许项、顺序和可选显示名；实际可用 Mission、Chapter 及官图/三方图属性来自 imatchext Mission Cache。`vote_menu.txt` 只维护 `!vote` 的服务器操作菜单；运维工具只双向收敛第三方 Map 策略段。

## AstMod 运行内容

AstMod 是持续维护的 Baseline。它已同步到 2.8.1 的配置、VScript 和终章需求量规则，并保留资源控制与 `versus_coop_mode.smx`：章节过程中借用 Versus 行为，回合结束时切回 Coop 以继续战役。

- `!ast` 打开 Ast 玩法调整菜单，`!tz` 保留为兼容短命令。单人生还者直接调整，多人生还者发起投票；菜单提供当前保留的玩法项。`!vote` 从 `vote_menu.txt` 读取服务器操作，不再承担地图投票。
- 临时玩法调整跨地图保留，最后一名真人离开后延迟恢复当前 DAS/profile 默认值；管理员可用 `!astreset` 立即走同一恢复路径。只有存在非默认调整时才周期播报，新玩家进入时会收到当前人数档和波次状态。
- AstMod Baseline 的新版刷特由作者仓库提交 `c0d829f` 的 `wave_spawner.sp` 编译，Challenge 仍保留新旧机制投票。AstRedux 不再加载这份共享插件或旧 VScript 刷特，而由 `astredux_wave_spawner.sp` 单独维护唯一波次模型、`!si` 临时值和 VScript 重载。
- Challenge 已修正濒死生还者击杀特感回血、普通感染者事件的 `infected_id` 读取、小僵尸击杀累加和生命值链式比较；AstMod 与 AstRedux 两份 SMX 均由同一修正源码重建，回血与备弹待实机复测。
- `versus_coop_mode.smx` 已将 Director 中相邻的一字节回合状态字段由四字节写改为 `NumberType_Int8`，避免回合重开时覆盖后续指针；海洋按原崩溃路径复测后未再出现问题。
- `jointeam.smx` 已恢复仓库源码，补充 ReadyUp 兼容 Forward。其管理员命令 `sm_fuck <名称|all>` 使用 ban flag，只按 Bot 名称处死 AI 特感，不会处死人类感染者。
- AstMod 与 AstRedux 使用仓库维护的 `pause_coop.smx`，由每名真人生还者独立准备并在全员准备后倒计时恢复；AstFlex 与竞技模式继续使用 Rework 的通用 `pause.smx`。
- Uzi、消音微冲、木喷、铁喷及确定性霰弹散布已与 Zonemod 同步。旧 weapon-attributes binary 不支持 `reloadduration`，`l4d2_smg_reload_tweak.smx` 会覆盖同步后的换弹参数，因此二者不再使用。
- 旧 `sm_melee ... damageflags` 接口已停用；DAS 的近战对 Tank 倍率继续使用 `sm_weapon melee tankdamagemult`。
- `clip_removal.smx` 已删除。历史源码与当前二进制可追溯到 Rework 2020 年移除前的同一版本；该插件会整图禁用 `env_player_blocker`，上游因破坏地图边界和两队一致性而停用并删除。
- `astmod.nut` 对模式初始化时的第二次 `update_diff` 增加保护，避免直接切换 matchmode 时出现瞬时 Squirrel 异常。

## 资产与来源边界

- 57 份符合 `cXmY*.cfg` 的 Zonemod 官图 Stripper 已同步到 `cfg/stripper/astmod/maps/`；global filters 和第三方地图文件没有覆盖，校验脚本会比较哈希。
- `addons/astmod.vpk` 提供 `astmod`、`astredux` 和历史 `hunter` mutation。可审阅源文件位于 `assets/astmod_vpk/`，可用 `tools/build_astmod_vpk.ps1` 重建。
- 2026-08-16 与当时 App 222860 的官方 `gamemodes.txt` 比较，当前副本只在末尾追加自定义模式。游戏更新后仍需重新比较，其他携带同名文件的 addon 也可能产生加载顺序冲突。
- AstMod 运行包包含模式 cfg、VScript、Stripper、VPK、`optional/astmod/` 插件池、imatchext 扩展及其可选 langparser 依赖、gamedata/translations、`missioncycle.txt`、`vote_menu.txt` 和其余所需 data/gamedata/translations；SourceMod/MetaMod core 延续 Rework 提供的版本。当前 Baseline 以 2.8.1 为更新基准，历史二进制的源码对应关系以清单逐项记录。
- 本项目修改并维护 Campaign Switcher、vote、Challenge、AI_HardSI、jointeam 和 versus_coop_mode，并直接维护 Wave Spawner 的构建关系；其余历史二进制的源码覆盖与重建能力以 `PLUGIN_SOURCE_INVENTORY.md` 为准。
- `server.smx` 已移除；空服换图和服务器进程重启由 systemd 等宿主服务管理。避免以插件触发 `sv_crash` 作为重启方式。
- `tls_restore_vocalize.smx` 已更新为不再需要 `sceneprocessor.smx` 的版本；后者保留在插件池中但不加载，仍需实机确认笑声等 vocalize 功能。

## 校验与测试

静态校验命令：

```powershell
pwsh -File tools/validate_astmod_integration.ps1
```

当前脚本检查必要资产、启用插件加载、生命周期所有权、matchmode 注册、地图过滤、Hard SI 链路、Wave/Challenge 所有权、`generalfixes` 分层、57 份官图 Stripper 哈希和基本 KeyValues 结构；脚本也包含当前 Redux scaffold 的静态检查，其开发状态以 `README.md` 为准。

已在 WSL2 Ubuntu 22.04 Dedicated Server 验证：

- AstMod 冷加载及核心 CVar/plugin 状态；
- 有客户端连接时从 AstMod 切换到 Zonemod，确认 `versus_coop_mode.smx`、Campaign Switcher、AstMod AI 和投票插件卸载；
- 当前武器参数不再触发旧插件接口报错。

仍需真人验证：

- 完整 `!match`、`!rmatch`、`!vote`、`!mapvote`、`!nextmap`、`!chaptervote`、`!ast`、`!tz` 和 `!si` 流程；
- AstMod/AstRedux 暂停后的逐人生还者准备、迟到加入、离队与管理员强制暂停流程；
- 新旧刷特切换、临时调整跨图保留、最后一名真人离开后的自动重置和 `!astreset`；
- 正常完成章节、终章与 Campaign Switcher 战役切换；
- 至少三轮 AstMod / Zonemod 往返切换。
