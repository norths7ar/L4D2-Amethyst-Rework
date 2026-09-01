# AstMod 插件源码与 SMX 对应清单

这份清单记录现有 `.smx` 的二进制来源、可供维护的 `.sp` 线索和可重建状态。数据来自插件加载配置、SHA-256 对照和源码路径扫描；构建关系以记录的源码、编译器、include、参数和产物比较为准。

## 判定标准

- 主清单范围是 `addons/sourcemod/plugins/optional/astmod/*.smx`，共 122 个；“当前加载”表示 `astmod`、`astredux` 或 `astflex` 至少有一个模式启用该插件。
- “AstMod 2.7.1 一致”表示当前 SMX 与原包同名二进制哈希一致；源码关系另按本清单中的构建状态记录。
- `repo:` 指本仓库 `addons/sourcemod/scripting/`；`AstSrc:` 指外部参考克隆 `../../repos/L4D2-AstMod-Scriptings-upstream/`。
- “源码线索”列出值得核对的文件；可重建关系同时记录源码、编译器、include、参数和产物比较。

## 总数

| 项目 | 数量 |
| --- | ---: |
| AstMod 隔离目录内的 SMX | 122 |
| 当前加载 | 84 |
| 当前停用 | 38 |
| 与 AstMod 2.7.1 原包二进制完全一致 | 113 |
| 本地修改或新增、由本仓库维护的当前二进制 | 9 |

“与 2.7.1 一致”是历史二进制来源判定；当前 Baseline 的运行规则以 2.8.1 为基准。历史插件继续按已有源码线索列示，Wave Spawner 和本轮重建插件由仓库直接维护构建关系。

## 仓库统一提供、三个模式共同加载的插件

下面插件由 Ast 系列模式共享。Rework 已有功能优先使用共享版本；AstMod 和 AstFlex 使用 AstMod 隔离目录中的作者 Wave Spawner，AstRedux 使用自己的单一波次实现。

| 加载路径 | 源码 |
| --- | --- |
| `confoglcompmod.smx` | `addons/sourcemod/scripting/confoglcompmod.sp` |
| `match_vote.smx` | `addons/sourcemod/scripting/match_vote.sp` |
| `optional/l4d2_weapon_attributes.smx` | `addons/sourcemod/scripting/l4d2_weapon_attributes.sp` |
| `optional/l4d2_static_shotgun_spread.smx` | `addons/sourcemod/scripting/l4d2_static_shotgun_spread.sp` |
| `optional/l4d2_skill_detect.smx` | `addons/sourcemod/scripting/l4d2_skill_detect.sp` |
| `optional/lerpmonitor.smx` | `addons/sourcemod/scripting/lerpmonitor.sp` |
| `optional/slots_vote.smx` | `addons/sourcemod/scripting/slots_vote.sp` |
| `optional/specrates.smx` | `addons/sourcemod/scripting/specrates.sp` |
| `optional/l4d_boss_vote.smx` | `addons/sourcemod/scripting/l4d_boss_vote.sp` |
| `optional/pause.smx` | `addons/sourcemod/scripting/pause.sp`（Rework 6.9 主体，合入海洋版短命令、面板命令和延迟暂停） |
| `optional/astmod/wave_spawner.smx` | `addons/sourcemod/scripting/wave_spawner.sp`（作者仓库提交 `c0d829f` 为基线；2.8.1 包缺少成品） |

## AstRedux 专属、可从仓库源码重建的插件

下面 5 个插件位于 `optional/astredux/`，单列于 AstMod 隔离目录的 121 个二进制之外。它们已经用仓库保存的 SourceMod 1.12.0.7230 compiler 和 include 编译通过；本仓库直接维护其构建产物关系。

| 加载路径 | 源码 | 职责 |
| --- | --- | --- |
| `optional/astredux/astredux_profile_controller.smx` | `addons/sourcemod/scripting/astredux_profile_controller.sp` | 缓存、选择，并在完整验证后下发 1–4 人声明式 profile，不执行具体玩法规则 |
| `optional/astredux/wave_spawner.smx` | `addons/sourcemod/scripting/astredux_wave_spawner.sp` | 执行 Redux 唯一的波次刷特模型，拥有默认值、临时有效值与 `!si` |
| `optional/astredux/astredux_rules.smx` | `addons/sourcemod/scripting/astredux_rules.sp` | 执行 profile 驱动的 Tank、Witch 和武器规则 |
| `optional/astredux/astredux_autowipe.smx` | `addons/sourcemod/scripting/astredux_autowipe.sp` | 常驻 AutoWipe adapter，并拥有自己的 profile 开关 CVar |
| `optional/astredux/challenge.smx` | `addons/sourcemod/scripting/astredux_challenge.sp` + `challenge.sp` | Redux 专用 `!ast` build，读取当前 Redux profile 并与旧 DAS 解耦 |

## 作者可选功能

这里记录服务器作者额外加入的娱乐与管理功能。每项记录插件用途、实际加载位置、源码或二进制来源，以及所需 cfg、data、translations、VScript 或 VPK 资产。

| 插件 | 用途 | 加载位置 | 来源与资产 |
| --- | --- | --- | --- |
| 待首个功能落地后登记 |  |  |  |

## 维护来源补充

- 对存在多个源码线索的 `l4d_boss_percent`、`l4d2_hunter_no_deadstops` 和 `survivor_mvp`，海洋建议今后维护以 `AstSrc:` 为准；这不证明当前二进制由该版本构建。AstFlex 与竞技模式仍使用仓库可重建的共享 `pause.smx`；AstMod/AstRedux 改用 `pause_coop.smx`，隔离目录内其他历史副本仍不据此建立来源关系。
- Campaign Switcher 运行依赖官方 [`shqke/imatchext`](https://github.com/shqke/imatchext) CI 产物：提交 `c384bccefc593bc308fe829013b3ebcbe62e78a2`、Actions run `28502325023`、artifact `imatchext-sm1.12-oldlinux-c384bcc`。仓库只纳入 L4D2 oldlinux 扩展及运行所需 include、gamedata、translations；`imatchext.ext.2.l4d2.so` SHA-256 为 `8CD002D994B9569AC74763D9087411E118A76C38DD2F2901F1ACA96F153CC67F`。
- `versus_coop_mode.smx` 现由仓库内 `versus_coop_mode.sp` 维护；上游线索是 [`umlka/l4d2/versus_coop_mode`](https://github.com/umlka/l4d2/tree/main/versus_coop_mode)。当前版本将相邻的一字节 Director 回合字段改为 `NumberType_Int8` 写入，避免旧版四字节写破坏后续指针。
- Lysis 反编译只能用于分析仅二进制插件，不能恢复原始源码或证明构建链。

## 按状态分类的插件清单

## 1. 二进制来源已确认：与 AstMod 2.7.1 原包一致（113）

这里的“已确认”表示当前 SMX 与 2.7.1 运行包中的二进制哈希完全一致；源码对应关系由每项后的 `repo:`、`AstSrc:` 或构建状态继续说明。

### 已加载（75）

#### 找到单一源码线索（62）

- `all4dead2.smx` → `AstSrc:all4dead2.sp`
- `blockheatseekingchargers.smx` → `repo:blockheatseekingchargers.sp`
- `blocktrolls.smx` → `repo:blocktrolls.sp`
- `bossspawningfix.smx` → `repo:bossspawningfix.sp`
- `difficulty_adjustment_system.smx` → `AstSrc:difficulty_adjustment_system.sp`
- `eq_finale_tanks.smx` → `repo:eq_finale_tanks.sp`
- `fix_engine.smx` → `repo:fix_engine.sp`
- `HunterSkeetSound.smx` → `AstSrc:HunterSkeetSound.sp`
- `l4d_bash_kills.smx` → `repo:l4d_bash_kills.sp`
- `l4d_common_ragdolls_be_gone.smx` → `repo:l4d_common_ragdolls_be_gone.sp`
- `l4d_pounceprotect.smx` → `repo:l4d_pounceprotect.sp`
- `l4d_reload_fix.smx` → `repo:l4d2_reload_fix.sp`（文件名别名，仍需确认）
- `l4d_stuckzombiemeleefix.smx` → `repo:archive/l4d_stuckzombiemeleefix.sp`
- `l4d_tank_control_eq.smx` → `repo:l4d_tank_control_eq.sp`
- `l4d_tank_damage_announce.smx` → `repo:l4d_tank_damage_announce.sp`
- `l4d_tank_props.smx` → `repo:archive/l4d_tank_props.sp`
- `l4d_witch_damage_announce.smx` → `repo:l4d_witch_damage_announce.sp`
- `l4d2_bot_spit_ignite_gascan.smx` → `AstSrc:l4d2_bot_spit_ignite_gascan.sp`
- `l4d2_collision_adjustments.smx` → `repo:l4d2_collision_adjustments.sp`
- `l4d2_director_commonlimit_block.smx` → `repo:l4d2_director_commonlimit_block.sp`
- `l4d2_drop.smx` → `AstSrc:l4d2_drop.sp`
- `l4d2_fix_deathspit.smx` → `repo:archive/l4d2_fix_deathspit.sp`
- `l4d2_getup_fixes.smx` → `repo:l4d2_getup_fixes.sp`
- `l4d2_getup_slide_fix.smx` → `repo:l4d2_getup_slide_fix.sp`
- `l4d2_ghost_warp.smx` → `repo:l4d2_ghost_warp.sp`
- `l4d2_godframes_control_merge.smx` → `repo:l4d2_godframes_control_merge.sp`
- `l4d2_hittable_control.smx` → `repo:l4d2_hittable_control.sp`
- `l4d2_horde_equaliser.smx` → `repo:l4d2_horde_equaliser.sp`
- `l4d2_jockey_skeet.smx` → `repo:l4d2_jockey_skeet.sp`
- `l4d2_ladder_rambos.smx` → `repo:l4d2_ladder_rambos.sp`
- `l4d2_m2_control_eq.smx` → `repo:l4d2_m2_control_eq.sp`
- `l4d2_melee_spawn_control.smx` → `repo:l4d2_melee_spawn_control.sp`
- `l4d2_pickup.smx` → `repo:l4d2_pickup.sp`
- `l4d2_saferoom_detect.smx` → `repo:l4d2_saferoom_detect.sp`
- `l4d2_saferoom_item_remove.smx` → `repo:l4d2_saferoom_item_remove.sp`
- `l4d2_si_staggers.smx` → `repo:l4d2_si_staggers.sp`
- `l4d2_slowdown_control.smx` → `repo:l4d2_slowdown_control.sp`
- `l4d2_smoker_drag_damage_interval.smx` → `repo:l4d2_smoker_drag_damage_interval.sp`
- `l4d2_sniper_bodyshot.smx` → `repo:l4d2_sniper_bodyshot.sp`
- `l4d2_spitblock.smx` → `repo:l4d2_spitblock.sp`
- `l4d2_stats.smx` → `repo:l4d2_stats.sp`
- `l4d2_steady_boost.smx` → `repo:l4d2_steady_boost.sp`
- `l4d2_tank_announce.smx` → `repo:l4d2_tank_announce.sp`
- `l4d2_tank_attack_control.smx` → `repo:l4d2_tank_attack_control.sp`
- `l4d2_tank_charger_m2_fix.smx` → `repo:l4d2_tank_charger_m2_fix.sp`
- `l4d2_uncommon_blocker.smx` → `repo:l4d2_uncommon_blocker.sp`
- `l4d2_unsilent_jockey.smx` → `repo:l4d2_unsilent_jockey.sp`
- `l4d2_votetospec.smx` → `AstSrc:l4d2_votetospec.sp`
- `l4d2_weaponrules.smx` → `repo:l4d2_weaponrules.sp`
- `MeleeInTheSafeRoom.smx` → `repo:MeleeInTheSafeRoom.sp`
- `mob_interval_limit.smx` → `AstSrc:mob_interval_limit.sp`
- `musical_jockeys_coop.smx` → `repo:archive/musical_jockeys.sp`（文件名别名，仍需确认）
- `nosaferoomkits.smx` → `repo:nosaferoomkits.sp`
- `noteam_nudging.smx` → `repo:noteam_nudging.sp`
- `pill_passer.smx` → `repo:pill_passer.sp`
- `pills_giver.smx` → `AstSrc:pills_giver.sp`
- `rock_stumble_block.smx` → `repo:rock_stumble_block.sp`
- `script_reloader.smx` → `AstSrc:script_reloader.sp`
- `staggersolver.smx` → `repo:staggersolver.sp`
- `tankdoorfix.smx` → `repo:archive/tankdoorfix.sp`
- `temphealthfix.smx` → `repo:temphealthfix.sp`
- `witch_and_tankifier.smx` → `repo:witch_and_tankifier.sp`

#### 找到多个可能对应的源码线索（3）

- `l4d_boss_percent.smx` → `repo:l4d_boss_percent.sp` / `AstSrc:l4d_boss_percent.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）
- `l4d2_hunter_no_deadstops.smx` → `repo:l4d2_hunter_no_deadstops.sp` / `AstSrc:l4d2_hunter_no_deadstops.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）
- `survivor_mvp.smx` → `repo:survivor_mvp.sp` / `AstSrc:survivor_mvp.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）

#### 仅有二进制（10）

- `advertisements.smx`（海洋说明【确定】：广告插件；运行二进制与 AstMod 2.7.1、2.8.1 包内文件完全一致，配置文件实际为 `addons/sourcemod/configs/advertisements.txt`；其行为与配置格式参见上游 [sm-advertisements](https://github.com/ErikMinekus/sm-advertisements)）
- `cannounce.smx`（海洋说明【确定】：进服欢迎提示）
- `enhancedsprays.smx`（海洋说明【确定】：无冷却喷漆、旁观喷漆）
- `healer_witch.smx`（海洋说明【确定】：秒妹回血）
- `l4d_swimming.smx`（海洋说明【确定】：出门前可以游泳）
- `l4d2_si_ladder_booster.smx`（海洋说明【不确定】：大概是从 Anne 开源插件摸来的）
- `l4d2_tank_facts_announce.smx`（海洋说明【不确定来源】：Zonemod 还是 MoYu 摸来的）
- `spawnstatefix.smx`（海洋说明【不确定】：可能是 ProMod 或 Zonemod 的插件，可能已过时）
- `tank_hud.smx`（海洋说明【确定来源/用途】：ProMod 插件，适合战役使用的精简化旁观 TankHUD）
- `witch_glow.smx`（海洋说明【确定用途】：Witch Party 插件）

### 未加载（38）

#### 找到单一源码线索（27）

- `autowipe.smx` → `AstSrc:autowipe.sp`
- `checkpoint-rage-control.smx` → `repo:checkpoint-rage-control.sp`
- `code_patcher.smx` → `repo:code_patcher.sp`
- `double_getup.smx` → `repo:archive/double_getup.sp`
- `finale_tank_blocker.smx` → `repo:finale_tank_blocker.sp`
- `l4d_ci_ffblock.smx` → `repo:l4d_ci_ffblock.sp`
- `l4d_boss_vote.smx` → `repo:l4d_boss_vote.sp`（运行时使用 Rework 共享副本）
- `l4d_equalise_alarm_cars.smx` → `repo:l4d_equalise_alarm_cars.sp`
- `l4d_tankpunchstuckfix.smx` → `repo:l4d_tankpunchstuckfix.sp`
- `l4d_weapon_limits.smx` → `repo:l4d_weapon_limits.sp`
- `l4d2_charger_getup_fix.smx` → `repo:archive/l4d2_charger_getup_fix.sp`
- `l4d2_fireworks_noise_block.smx` → `repo:l4d2_fireworks_noise_block.sp`
- `l4d2_melee_shenanigans.smx` → `repo:l4d2_melee_shenanigans.sp`
- `l4d2_nobackjump.smx` → `repo:l4d2_nobackjumps.sp`（文件名别名，仍需确认）
- `l4d2_playstats.smx` → `repo:l4d2_playstats.sp`
- `l4d2_skill_detect.smx` → `repo:l4d2_skill_detect.sp`（隔离副本，运行时未使用）
- `l4d2_smg_reload_tweak.smx` → `repo:archive/l4d2_smg_reload_tweak.sp`
- `l4d2_sniper_stats.smx` → `AstSrc:l4d2_sniper_stats.sp`
- `l4d2_static_shotgun_spread.smx` → `repo:l4d2_static_shotgun_spread.sp`（隔离副本，运行时未使用）
- `l4d2_weapon_attributes.smx` → `repo:l4d2_weapon_attributes.sp`（隔离副本，运行时未使用）
- `lerpmonitor.smx` → `repo:lerpmonitor.sp`（运行时使用 Rework 共享副本）
- `nm3_ladder_damage.smx` → `repo:nm3_ladder_damage.sp`
- `slots_vote.smx` → `repo:slots_vote.sp`（运行时使用 Rework 共享副本）
- `specrates.smx` → `repo:specrates.sp`（运行时使用 Rework 共享副本）
- `versus2coop.smx` → `AstSrc:versus2coop.sp`
- `weapon_slowdown.smx` → `AstSrc:weapon_slowdown.sp`
- `wingman.smx` → `AstSrc:wingman.sp`

#### 找到多个可能对应的源码线索（2）

- `confoglcompmod.smx` → `repo:confoglcompmod.sp` / `repo:archive/confoglcompmod.sp`（隔离副本，运行时未使用；当前海洋源码 clone 中没有同名文件，无法把作者回复机械映射到这一项）
- `pause.smx` → `repo:pause.sp` / `AstSrc:pause.sp`（隔离历史副本；运行时使用仓库根共享版本）

#### 仅有二进制（9）

- `sceneprocessor.smx`（旧版 `tls_restore_vocalize.smx` 的前置插件；新版不再加载，二进制暂留）
- `autoadmin.smx`（海洋说明【确定用途】：进服自动获取阉割版 admin 身份，可用基础指令，如 all4dead 菜单、处死玩家和特感；笔记中另提到 `fuck`，具体是否可用未确认）
- `hostname.smx`（海洋说明【确定】：服务器名称；当前不加载）
- `l4d_nowitch.smx`（海洋说明【部分确定、需验证】：老 Zonemod 插件，用于人数变动时快速开关 Witch 生成；使用 Tankifier 时可能需要重新读取插件，需验证）
- `l4d_unscope.smx`（海洋说明【确定用途/版本背景】：老 Wingman 使用；新版本因有 bug 去除。狙击枪开镜射击后关镜，不能开镜连发）
- `l4d2_storm.smx`（海洋说明【确定用途、明确建议】：天气系统；当前不加载）
- `l4d2_saferoom_gun_control.smx`（海洋说明【确定来源】：ProMod 插件）
- `l4d2_weapon_csgo_reload.smx`（海洋说明【部分确定、不确定兼容性】：老 Wingman 使用；TLS 之后可能有 bug）
- `swamp_finale_fix.smx`（海洋说明【确定状态、不确定用途】：ProMod 插件，似乎修复 c3m4 种植园；海洋不知道具体作用，因此没有加载）

## 2. 本地修改或新增的当前二进制（9）

这九个插件由本仓库修改、新增或更新。`campaign_switcher.smx`、`pause_coop.smx`、`vote.smx`、`challenge.smx` 与 `wave_spawner.smx` 已用随仓库保存的 SourceMod 1.12.0.7230 compiler 和 include 重建；`jointeam.smx` 与 `versus_coop_mode.smx` 随对应仓库源码一同更新，构建复现列为后续工作；AI_HardSI 延续此前的本地修改二进制，构建链列为待锁定；`tls_restore_vocalize.smx` 记录为海洋提供的更新二进制。

### 已加载（9）

#### 有本仓库维护源码（8）

- `campaign_switcher.smx` → `repo:campaign_switcher.sp` / `AstSrc:ACS.sp`（以 imatchext Mission Cache 统一发现 Mission/Chapter；`missioncycle.txt` 只保留 Map 策略）
- `pause_coop.smx` → `repo:pause_coop.sp` / [`Sglight/L4D2-AstMod-Scriptings@9e71791`](https://github.com/Sglight/L4D2-AstMod-Scriptings/blob/9e7179187dd71d846a8a622d20a2fe43f0a312f1/pause_coop.sp)（逐人生还者准备面板，按当前 SourceMod 生命周期重写）
- `AI_HardSI.smx` → `repo:AI_HardSI.sp` / `AstSrc:AI_HardSI.sp`
- `challenge.smx` → `repo:challenge.sp`（本次重建使用） / `AstSrc:challenge.sp`（上游参考）
- `jointeam.smx` → `repo:jointeam.sp` / `AstSrc:jointeam.sp`（增加 ReadyUp 兼容 Forward；`sm_fuck` 使用 ban flag，只按名称处死 AI 特感）
- `vote.smx` → `repo:vote.sp` / `AstSrc:vote.sp`
- `versus_coop_mode.smx` → `repo:versus_coop_mode.sp` / [`umlka/l4d2`](https://github.com/umlka/l4d2/tree/main/versus_coop_mode)（修复 Director 一字节字段的越界写）
- `wave_spawner.smx` → `repo:wave_spawner.sp` / `AstSrc:wave_spawner.sp`（以作者仓库提交 `c0d829f` 为基线，本次重建使用）

#### 仅有更新二进制（1）

- `tls_restore_vocalize.smx`（允许手动发出笑声；新版不再依赖加载 `sceneprocessor.smx`，运行效果待实机确认）

### 未加载（0）

无。

## 构建边界

静态校验覆盖文件、加载路径和部分配置约束。完整可重建状态需要逐项保存 `.sp`、编译器、include、参数和产物比较；仅二进制插件、外部参考源码、AI_HardSI、`jointeam` 与 `versus_coop_mode` 的构建状态均在本清单中如实标注。
