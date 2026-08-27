# AstMod 插件源码与 SMX 对应清单

> 初始盘点基于 2026-08-16 的仓库提交 `a330a487`；当前文档已追加 AstMod namespace 迁移、`challenge.smx` 重建结果和 AstRedux 专属可复现构建。

这份清单用于回答两个不同的问题：服务器里的 `.smx` 二进制从哪里来，以及仓库里哪份 `.sp` **可能**是它的源码。二者不能混为一谈：同名文件只能证明“值得核对”，不能证明该 `.smx` 确实由该源码、以当前编译器和依赖编译而成。本次数据由本地审计脚本从插件加载配置、SHA-256 对照和源码路径扫描生成，再经少量文件名别名复核；下面是静态盘点快照，不是逐项凭印象填写。

## 范围与判定标准

- 主清单范围：`addons/sourcemod/plugins/optional/astmod/*.smx`，共 122 个。
- “当前加载”指 `astmod`、`astredux` 或 `astflex` 的插件加载配置中至少有一处启用；AstRedux 继续复用大部分 AstMod 插件，但已用自己的 Challenge、AutoWipe adapter 和 Profile Controller 替换旧 DAS 链路。
- “AstMod 2.7.1 一致”指当前 `.smx` 与归档原包中的同名二进制 SHA-256 完全一致，只确认二进制来源。
- `repo:` 指本仓库 `addons/sourcemod/scripting/` 下的路径；`AstSrc:` 指工作区外部保存的 AstMod 公开源码克隆 `../../repos/L4D2-AstMod-Scriptings-upstream/`，该参考仓库本身不属于本仓库。
- “可能对应的源码线索”仅表示按文件名、目录和已知别名找到可供核对的文件，尚未通过可重复编译确认；它不是“已证明的构建源码”。
- “本地修改，尚不可复现”表示源码和二进制都相对 AstMod 2.7.1 有改动，但用当前随仓库保存的编译器重新编译仍不能得到字节一致的 `.smx`。

## 总数

| 项目 | 数量 |
| --- | ---: |
| AstMod 隔离目录内的 SMX | 122 |
| 当前加载 | 90 |
| 当前停用 | 32 |
| 与 AstMod 2.7.1 原包二进制完全一致 | 118 |
| 本地修改、二进制来源不再等同原包 | 4 |
| 没找到源码线索，仅有二进制 | 21 |
| 找到单一源码线索 | 92 |
| 找到多个源码线索，需人工确认 | 5 |
| 本地修改且尚不能可重复编译 | 4 |

21 个“仅二进制”插件中，13 个当前启用，8 个当前停用。现阶段不能声称仓库中所有 SMX 均有源码，也不能声称现有源码可以完整重建发布包。

四个本地修改插件的具体位置已并入后面的分层清单；“尚不可复现”不表示插件不能工作，只表示当前产物还不能通过已记录命令得到字节一致的二次构建。

## Rework 提供、三个模式共同加载的插件

下面 5 个插件不使用 `optional/astmod/` 中的副本，而是加载 Competitive Rework 的共享版本。当前二进制均与本地保存的纯 Rework 上游副本 SHA-256 完全一致，并且仓库内有对应源码。

| 加载路径 | 源码 |
| --- | --- |
| `confoglcompmod.smx` | `addons/sourcemod/scripting/confoglcompmod.sp` |
| `match_vote.smx` | `addons/sourcemod/scripting/match_vote.sp` |
| `optional/l4d2_weapon_attributes.smx` | `addons/sourcemod/scripting/l4d2_weapon_attributes.sp` |
| `optional/l4d2_static_shotgun_spread.smx` | `addons/sourcemod/scripting/l4d2_static_shotgun_spread.sp` |
| `optional/l4d2_skill_detect.smx` | `addons/sourcemod/scripting/l4d2_skill_detect.sp` |

## AstRedux 专属、可从仓库源码重建的插件

下面 3 个插件位于 `optional/astredux/`，不计入后文 `optional/astmod/` 的 122 个历史二进制。它们已经用仓库保存的 SourceMod 1.12.0.7230 compiler 和 include 编译通过；构建产物的来源关系由本仓库直接维护，不是按同名猜测。

| 加载路径 | 源码 | 职责 |
| --- | --- | --- |
| `optional/astredux/astredux_profile_controller.smx` | `addons/sourcemod/scripting/astredux_profile_controller.sp` | 读取并应用 1–4 人声明式 profile，协调 Tank、刷特、No-Witch 和 adapter 开关 |
| `optional/astredux/astredux_autowipe.smx` | `addons/sourcemod/scripting/astredux_autowipe.sp` | 常驻 AutoWipe adapter，由 profile cvar 控制是否生效 |
| `optional/astredux/challenge.smx` | `addons/sourcemod/scripting/astredux_challenge.sp` + `challenge.sp` | Redux 专用 `/tz` build，读取当前 Redux profile 并与旧 DAS 解耦 |

## 按状态分类的插件清单

### 阅读方式

- 外层先区分当前二进制是否与 AstMod 2.7.1 原包一致，或属于本仓库的本地修改产物。
- 第二层区分插件当前是否由 `astmod`、`astredux` 或 `astflex` 加载。
- 第三层区分源码状态。这里列出的 `.sp` 是待核对的源码线索；除非另有说明，并不代表已经完成可重复编译验证。

## 1. 二进制来源已确认：与 AstMod 2.7.1 原包一致（118）

这里的“已确认”只表示当前 SMX 与 2.7.1 运行包中的二进制哈希完全一致，不表示源码对应关系已经确认。

### 已加载（86）

#### 找到单一源码线索（69）

- `all4dead2.smx` → `AstSrc:all4dead2.sp`
- `blockheatseekingchargers.smx` → `repo:blockheatseekingchargers.sp`
- `blocktrolls.smx` → `repo:blocktrolls.sp`
- `bossspawningfix.smx` → `repo:bossspawningfix.sp`
- `difficulty_adjustment_system.smx` → `AstSrc:difficulty_adjustment_system.sp`
- `eq_finale_tanks.smx` → `repo:eq_finale_tanks.sp`
- `fix_engine.smx` → `repo:fix_engine.sp`
- `HunterSkeetSound.smx` → `AstSrc:HunterSkeetSound.sp`
- `jointeam.smx` → `AstSrc:jointeam.sp`
- `l4d_bash_kills.smx` → `repo:l4d_bash_kills.sp`
- `l4d_boss_vote.smx` → `repo:l4d_boss_vote.sp`
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
- `lerpmonitor.smx` → `repo:lerpmonitor.sp`
- `MeleeInTheSafeRoom.smx` → `repo:MeleeInTheSafeRoom.sp`
- `mob_interval_limit.smx` → `AstSrc:mob_interval_limit.sp`
- `musical_jockeys_coop.smx` → `repo:archive/musical_jockeys.sp`（文件名别名，仍需确认）
- `nosaferoomkits.smx` → `repo:nosaferoomkits.sp`
- `noteam_nudging.smx` → `repo:noteam_nudging.sp`
- `pill_passer.smx` → `repo:pill_passer.sp`
- `pills_giver.smx` → `AstSrc:pills_giver.sp`
- `rock_stumble_block.smx` → `repo:rock_stumble_block.sp`
- `script_reloader.smx` → `AstSrc:script_reloader.sp`
- `server.smx` → `AstSrc:server.sp`
- `slots_vote.smx` → `repo:slots_vote.sp`
- `specrates.smx` → `repo:specrates.sp`
- `staggersolver.smx` → `repo:staggersolver.sp`
- `tankdoorfix.smx` → `repo:archive/tankdoorfix.sp`
- `temphealthfix.smx` → `repo:temphealthfix.sp`
- `versus_coop_mode.smx` → `AstSrc:versus2coop.sp`（文件名别名，仍需确认）
- `witch_and_tankifier.smx` → `repo:witch_and_tankifier.sp`

#### 找到多个可能对应的源码线索（4）

- `l4d_boss_percent.smx` → `repo:l4d_boss_percent.sp` / `AstSrc:l4d_boss_percent.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）
- `l4d2_hunter_no_deadstops.smx` → `repo:l4d2_hunter_no_deadstops.sp` / `AstSrc:l4d2_hunter_no_deadstops.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）
- `pause.smx` → `repo:pause.sp` / `AstSrc:pause.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）
- `survivor_mvp.smx` → `repo:survivor_mvp.sp` / `AstSrc:survivor_mvp.sp`（海洋已回复：今后维护优先以作者仓库版本为准；这不证明当前 SMX 由该版本构建）

#### 仅有二进制（13）

- `cannounce.smx`（海洋说明【确定】：进服欢迎提示）
- `enhancedsprays.smx`（海洋说明【确定】：无冷却喷漆、旁观喷漆）
- `healer_witch.smx`（海洋说明【确定】：秒妹回血）
- `hostname.smx`（海洋说明【确定】：服务器名称；与 Zonemod 冲突，不需要）
- `l4d_swimming.smx`（海洋说明【确定】：出门前可以游泳）
- `l4d2_si_ladder_booster.smx`（海洋说明【不确定】：大概是从 Anne 开源插件摸来的）
- `l4d2_storm.smx`（海洋说明【确定用途、明确建议】：天气系统，图一乐功能，可删）
- `l4d2_tank_facts_announce.smx`（海洋说明【不确定来源】：Zonemod 还是 MoYu 摸来的）
- `sceneprocessor.smx`（海洋说明【确定】：`tls_restore_vocalize.smx` 的前置插件）
- `spawnstatefix.smx`（海洋说明【不确定】：可能是 ProMod 或 Zonemod 的插件，可能已过时）
- `tank_hud.smx`（海洋说明【确定来源/用途】：ProMod 插件，适合战役使用的精简化旁观 TankHUD）
- `tls_restore_vocalize.smx`（海洋说明【确定】：允许手动发出笑声）
- `witch_glow.smx`（海洋说明【确定用途】：Witch Party 插件）

### 未加载（32）

#### 找到单一源码线索（23）

- `autowipe.smx` → `AstSrc:autowipe.sp`
- `checkpoint-rage-control.smx` → `repo:checkpoint-rage-control.sp`
- `code_patcher.smx` → `repo:code_patcher.sp`
- `double_getup.smx` → `repo:archive/double_getup.sp`
- `finale_tank_blocker.smx` → `repo:finale_tank_blocker.sp`
- `l4d_ci_ffblock.smx` → `repo:l4d_ci_ffblock.sp`
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
- `nm3_ladder_damage.smx` → `repo:nm3_ladder_damage.sp`
- `versus2coop.smx` → `AstSrc:versus2coop.sp`
- `weapon_slowdown.smx` → `AstSrc:weapon_slowdown.sp`
- `wingman.smx` → `AstSrc:wingman.sp`

#### 找到多个可能对应的源码线索（1）

- `confoglcompmod.smx` → `repo:confoglcompmod.sp` / `repo:archive/confoglcompmod.sp`（隔离副本，运行时未使用；当前海洋源码 clone 中没有同名文件，无法把作者回复机械映射到这一项）

#### 仅有二进制（8）

- `advertisements.smx`（海洋说明【确定】：广告插件；配置文件为 `addons/sourcemod/configs/advertisement.cfg`）
- `autoadmin.smx`（海洋说明【确定用途】：进服自动获取阉割版 admin 身份，可用基础指令，如 all4dead 菜单、处死玩家和特感；笔记中另提到 `fuck`，具体是否可用未确认）
- `clip_removal.smx`（海洋未说明用途，仍待确认）
- `l4d_nowitch.smx`（海洋说明【部分确定、需验证】：老 Zonemod 插件，用于人数变动时快速开关 Witch 生成；使用 Tankifier 时可能需要重新读取插件，需验证）
- `l4d_unscope.smx`（海洋说明【确定用途/版本背景】：老 Wingman 使用；新版本因有 bug 去除。狙击枪开镜射击后关镜，不能开镜连发）
- `l4d2_saferoom_gun_control.smx`（海洋说明【确定来源】：ProMod 插件）
- `l4d2_weapon_csgo_reload.smx`（海洋说明【部分确定、不确定兼容性】：老 Wingman 使用；TLS 之后可能有 bug）
- `swamp_finale_fix.smx`（海洋说明【确定状态、不确定用途】：ProMod 插件，似乎修复 c3m4 种植园；海洋不知道具体作用，因此没有加载）

## 2. 本地修改的当前二进制（4）

这四个插件均为本仓库正在使用的修改版，当前 SMX 与 AstMod 2.7.1 原包不同。`challenge.smx` 在本次 namespace 迁移中已由 `repo:challenge.sp` 和随仓库保存的 SourceMod 1.12.0.7230 compiler 重建，但重复编译仍不能得到字节一致产物；其余三个插件继续沿用迁移前的本地修改二进制，准确构建链尚未锁定。

### 已加载（4）

#### 有本仓库修改源码，但构建链尚未锁定（4）

- `ACS.smx` → `repo:ACS.sp` / `AstSrc:ACS.sp`
- `AI_HardSI.smx` → `repo:AI_HardSI.sp` / `AstSrc:AI_HardSI.sp`
- `challenge.smx` → `repo:challenge.sp`（本次重建使用） / `AstSrc:challenge.sp`（上游参考）
- `vote.smx` → `repo:vote.sp` / `AstSrc:vote.sp`

### 未加载（0）

无。

## 海洋已回复与仍待确认

### 海洋已回复

1. 21 个仅二进制插件：海洋建议基本不需要修改，必要时可尝试反编译；提到的反编译程序是 Lysis。上面的 21 个条目已并入其用途、去留和不确定性说明；这些说明不等于找到了源码，也不等于证明当前 SMX 可复现。
2. 5 个存在多个可能对应源码线索的插件：海洋回复“以我的仓库为准”。其中 `l4d_boss_percent`、`l4d2_hunter_no_deadstops`、`pause` 和 `survivor_mvp` 能明确映射到作者源码 clone，今后维护优先采用 `AstSrc:` 版本；该维护优先级不证明当前 SMX 就是由这些版本构建的。第五项是未使用的隔离 `confoglcompmod.smx`，当前作者源码 clone 中没有同名文件，仍不能据此判定两个 `repo:` 线索哪份对应 2.7.1 二进制。
3. `versus_coop_mode.smx`：海洋给出的上游线索是 [`umlka/l4d2/versus_coop_mode`](https://github.com/umlka/l4d2/tree/main/versus_coop_mode)。这只是来源线索，仍不能单独证明当前 `versus_coop_mode.smx` 的构建链。
4. `ACS.smx`、`AI_HardSI.smx` 和 `vote.smx`：海洋说明“因为你使用的是 2.7.1”，但没有提供可核验的编译器、include 集合或参数；因此本清单仍只能把仓库源码作为今后维护参考，不能写成已证明的 SMX 构建来源。
5. 关于 `jointeam.smx`：海洋未提供进一步的源码、版本或构建链确认；若要加入指令，仍应先审查现有源码线索，再决定是否修改和重编译。

### 仍待确认

- 21 个仅二进制插件是否存在可公开或可归档的原始源码，以及各自准确版本；Lysis 反编译结果只能作为分析线索，不能自动恢复原始源码或构建链。
- 四个可映射到 `AstSrc:` 的多线索插件，其当前 SMX 的实际源码、SourceMod/include 版本、编译参数和字节可复现性；“今后维护优先以作者仓库版本为准”是维护决策，不是构建证明。
- 未使用的隔离 `confoglcompmod.smx` 应对应 `repo:confoglcompmod.sp` 还是 `repo:archive/confoglcompmod.sp`；Ast 系模式运行时使用的是已由 Rework 来源确认的共享 `confoglcompmod.smx`，不会受该隔离副本影响。
- `versus_coop_mode.smx` 是否确由 `versus2coop.sp` 或海洋给出的 `umlka/l4d2/versus_coop_mode` 上游版本构建，以及准确构建环境。
- `challenge.smx` 重复编译哈希不一致的原因，以及四个本地修改插件完整、可重现的构建链。

## 构建与发布边界

当前仓库的静态校验可以检查文件存在、加载路径和部分配置约束，但**不能**证明 `.sp` 与 `.smx` 一一对应。现有发布工作流也不能作为完整重建证明：仅二进制插件没有可编译输入，部分插件的源码线索位于归档或参考目录，而且编译器/include 版本尚未完全锁定。

后续若要把“源码线索”升级为“已确认对应”，至少应记录：源码文件哈希、编译器版本、include 集合、编译参数，以及重建产物和当前 SMX 的哈希比较结果。
