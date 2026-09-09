# 插件源码

## 目录与二进制的对应关系

以 `addons/sourcemod/` 为基准，`scripting/` 的插件入口尽量与 `plugins/` 使用同一相对路径：基础插件在根目录，通用修复在 `fixes/`，功能插件在 `optional/`，再分 `competitive/`、`coop/` 和 Legacy `astmod/`。跨模式共用且只有一份维护源码的插件可以放在 `scripting/optional/`，不为不同 SMX 复制源码。

- `include/` 是共用编译接口；它不需要对应 SMX。插件私有模块随入口文件移动，如 `AI_HardSI/`、`l4d2lib/`；模块 SP 不单独生成插件。
- `optional/astmod/include/` 保留 Legacy 依赖，`optional/astmod/nativevotes/` 保留其配套模块。旧标准库不要整体置于现代 include 之前。
- `sourcemod/` 保留编译器、随附标准 include 与测试材料；标准插件入口按二进制用途放置。
- `archive/` 和 `dev_plugins/` 保留历史与开发材料；没有对应运行插件的参考版本不伪装成当前构建。
- 多份同名源码可能是不同分支，不能仅按名字合并。`l4d2_stats` 等共用候选对应的 Competitive/Coop SMX 也不一定来自同一次构建。

### 历史副本命名

当前维护入口保留与 SMX 同名的 `xxx.sp`；历史版本使用 `xxx.版本号.sp`，同版本或版本不明的分支副本使用 `xxx.来源-ver.sp`。版本和来源依据源码与获取记录，不由文件日期推测。PVP/PVE 等各自维护的入口仍按功能目录区分，模块文件随所属插件保留原名。

本次区分的历史副本如下（相对 `scripting/`）：

- `optional/astmod/disabled/AI_HardSI.1.1.sp`
- `optional/astmod/disabled/challenge.2.5.sp`
- `optional/astmod/disabled/jointeam.1.7.sp`
- `optional/coop/l4d_boss_percent.3.2.5.sp`
- `optional/astmod/disabled/l4d2_hunter_no_deadstops.astmod-ver.sp`
- `optional/astmod/disabled/mob_interval_limit.astmod-ver.sp`
- `optional/astmod/disabled/pause.6.7.1.sp`
- `optional/astmod/disabled/script_reloader.astmod-ver.sp`
- `optional/astmod/disabled/survivor_mvp.0.3.sp`
- `optional/astmod/disabled/vote.1.2.sp`
- `optional/astmod/disabled/wave_spawner.1.0.sp`
- `archive/confoglcompmod.2.2.4.sp`
- `archive/l4d_tongue_float_fix.1.1.sp`

这些后缀描述源码身份，不要求改名现有 SMX；对应构建仍以加载配置和下方已知差异为准。`astmod-ver` 表示 AstMod 源码快照分支，不声称它严格早于另一份同名实现。

## 源码例外

本表记录已核对的源码例外，不代表未列出的历史二进制均可原样重建。目录对应只提供维护入口，不证明构建一致。

2026-09-09 核对：原缺源码的 16 项中，已补入 10 份同源候选及 2 份有明确差异的参考实现，余 4 项未保存源码；AstRedux 当前加载的原缺源码 8 项已覆盖 7 项，剩喷漆。目标是提供二次开发入口，不要求每个历史 SMX 原样重建。下方恢复源码说明记录版本、接口差异、来源及编译范围。

| 插件 | 状态 | 说明 |
| --- | --- | --- |
| `all4dead2.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `autowipe.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `difficulty_adjustment_system.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `HunterSkeetSound.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `l4d2_bot_spit_ignite_gascan.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `l4d2_drop.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `l4d2_sniper_stats.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `l4d2_votetospec.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `mob_interval_limit.smx` | 有源码但未复现 | 已恢复 AstMod 原版 SMX 和源码快照；AstRedux 不加载此插件。 |
| `pills_giver.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `script_reloader.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `versus2coop.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `weapon_slowdown.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `wingman.smx` | 有源码但未复现 | 已保存 AstMod 源码快照。 |
| `l4d_reload_fix.smx` | 有源码但未复现 | 源码文件名为 `l4d2_reload_fix.sp`，对应关系待确认。 |
| `l4d2_nobackjump.smx` | 有源码但未复现 | 源码文件名为 `l4d2_nobackjumps.sp`，对应关系待确认。 |
| `musical_jockeys_coop.smx` | 有源码但未复现 | 源码文件名为 `optional/coop/musical_jockeys_coop.sp`（原 `archive/musical_jockeys.sp`），对应关系待确认。 |
| `optional/astmod/jointeam.smx` | 有源码但未复现 | AstMod Legacy 保留源码与原二进制，当前构建关系尚未锁定。 |
| `versus_coop_mode.smx` | 有源码但未复现 | 本仓库维护源码，但当前二进制的构建关系尚未锁定。 |
| `l4d_boss_percent.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `pause.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `survivor_mvp.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `enhancedsprays.smx` | 仅插件无源码 | ReFlexPoison 1.2；已定位[原帖源码附件](https://forums.alliedmods.net/showthread.php?p=1998984)，帖子列 1.1，附件获取被站点 403 阻断，尚未保存源码。 |
| `healer_witch.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`healer_witch.sp`。 |
| `l4d_swimming.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`l4d_swimming.sp`。 |
| `l4d2_saferoom_gun_control.smx` | 仅插件无源码 | SMX：High Cookie and Standalone，版本 1；按 configs/saferoom_gun_control.txt 替换武器出生实体，待找原实现。 |
| `l4d2_si_ladder_booster.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`l4d2_si_ladder_booster.sp`。 |
| `l4d2_storm.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`l4d2_storm.sp`。 |
| `l4d2_tank_facts_announce.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`l4d2_tank_facts_announce.sp`。 |
| `l4d2_weapon_csgo_reload.smx` | 已保存参考实现 | 见下方恢复源码说明：`l4d2_weapon_csgo_reload.sp`。 |
| `l4d_nowitch.smx` | 仅插件无源码 | SMX：Sir，版本 1；描述为清除生成的 Witch，不能据此认定其内部实现人数调整。 |
| `l4d_unscope.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`l4d_unscope.sp`。 |
| `sceneprocessor.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`sceneprocessor.sp`。 |
| `spawnstatefix.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`spawnstatefix.sp`。 |
| `swamp_finale_fix.smx` | 仅插件无源码 | SMX：Jacob，版本 0.1；描述为修复沼泽终章第二队异常，内嵌 Pro-Mod-4.0 地址当前不可访问。 |
| `tank_hud.smx` | 已保存参考实现 | 见下方恢复源码说明：`tank_hud.sp`。 |
| `tls_restore_vocalize.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`tls_restore_vocalize.sp`。 |
| `witch_glow.smx` | 已补源码，未确认同构建 | 见下方恢复源码说明：`witch_glow.sp`。 |

## 第三方原生扩展

`custom_fakelag.ext.2.l4d2.so` / `.dll` 与 `gamedata/custom_fakelag.games.txt` 来自 [ProdigySim 的 1.0.0.0 正式发布包](https://github.com/ProdigySim/custom_fakelag/releases/tag/1.0.0.0)，未修改二进制；对应源代码和构建流程由上游维护。发布 ZIP 的 SHA256 为 `BFDEC07FC54B1FC5D23C91020AD9EAB88D7D0DDD691BEEB95512039353010A30`，许可随 `extensions/custom_fakelag.LICENSE.txt` 保存。Linux 扩展已在本地 L4D2 2.2.4.3 / SourceMod 1.12.0.7230 实例加载；Windows 二进制未运行验证。命令包装层由本仓库 `scripting/optional/coop/player_fakelag.sp` 编译，不使用发布包的旧 SMX。

## 补回的插件源码

这些文件是二次开发的阅读和修改入口，不是当前 SMX 的逐字节重建保证。2026-09-09 从公开源码和本地上游快照补入，并按对应插件归入 `addons/sourcemod/scripting/optional/` 下的功能目录；保留原始作者、代码和许可声明，未修改加载配置或替换任何运行插件。

核对依据是当前 SMX 解压后的 `myinfo`、命令、ConVar、依赖和调试符号，与源码相互对照。相同作者和版本不证明构建完全相同；以下已知差异应在实际修改相关功能时处理，而不是直接编译覆盖。

### 维护入口与对应关系

| 源码 | 当前 SMX → 源码快照 | 核对结果、维护注意事项 | 来源 |
| --- | --- | --- | --- |
| `healer_witch.sp` | CanadaRox 1 → 1 | 作者、版本及 `hw_*` 接口对应。监听 `witch_killed` 给有效生还者回血，不限定爆头或秒妹；分实血、虚血及上限。 | [CanadaRox 代码副本](https://github.com/MatthewClair/sourcemod-plugins/blob/master/healer_witch/healer_witch.sp) |
| `witch_glow.sp` | CanadaRox 1.1 → 1.1 | 作者、版本及 `wg_min_range` 对应；远处显示，靠近或惊扰后关闭。Anne 的 fdxx 同名版接口不同，不作为本插件源码。 | [CanadaRox 代码副本](https://github.com/MatthewClair/sourcemod-plugins/blob/master/mutliwitch/witch_glow.sp) |
| `l4d2_si_ladder_booster.sp` | AiMee 2.3.3 → 2.3.3 | `l4d2_ai_ladder_boost`、`l4d2_pz_ladder_boost` 对应；候选增加可调 `l4d2_boost_multiplier`，当前 SMX 字符串未见该项。相同版本号仍有实现差异；通过 `m_flLaggedMovementValue` 改爬梯速度。 | [Anne 快照](https://github.com/fantasylidong/CompetitiveWithAnne)；本地提交 `f4dbddd618aeb749a015cda4072576ae16bbeee3`，`addons/sourcemod/scripting/optional/AnneHappy/l4d2_si_ladder_booster.sp` |
| `l4d2_tank_facts_announce.sp` | Forgetest 1.8 → 1.8 | 作者、版本、翻译文件及播报入口对应。Tank 结算输出标题、拳/石/铁命中、击倒/死亡、存活时间/伤害共四行；不是定时公告。翻译沿用仓库 `translations/l4d2_tank_facts_announce.phrases.txt` 及语言目录。 | [MoYu 作者源码](https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/7280af5284da5030add1853343fe5d10f245d72b/The%20Last%20Stand/l4d2_tank_facts_announce) |
| `tls_restore_vocalize.sp` | Forgetest 2.1 → 2.1 | 作者、版本及 `tls_restore_vocalize` gamedata 对应；此版本使用 DHooks/Left4DHooks，不是依赖 Scene Processor 的旧 1.4 方案。当前 `gamedata/tls_restore_vocalize.txt` 为维护配套入口。 | [MoYu 作者源码](https://github.com/Target5150/MoYu_Server_Stupid_Plugins/tree/7280af5284da5030add1853343fe5d10f245d72b/The%20Last%20Stand/tls_restore_vocalize) |
| `spawnstatefix.sp` | ProdigySim 1.0 → 1.1 | 同作者、`sm_fix_wff` 和终章复活状态操作对应；1.1 含 `uf4_airfield` 自动修复。包含相对内存偏移，不能以编译通过替代引擎兼容验证。 | [作者 Gist](https://gist.github.com/ProdigySim/04912e5e76f69027f8c4) |
| `l4d_swimming.sp` | SilverShot 1.8 → 1.9 | 同作者及 `l4d_swim_*` 接口；作者日志说明 1.9 修复 SM 1.11 编译警告。源码控制水中游泳/潜水、速度、溺水与倒地行为；不是专门的准备阶段插件。 | [作者源码](https://github.com/SilvDev/Various_Scripts_Collection/blob/main/l4d_swimming.sp)，[原帖](https://forums.alliedmods.net/showthread.php?t=187565) |
| `l4d_unscope.sp` | SilverShot 1.9 → 1.10 | 同作者及 `l4d_unscope_*` 接口；作者日志说明 1.10 修复 SM 1.11 编译警告。控制开枪退镜与栓狙自动回镜。 | [作者源码](https://github.com/SilvDev/Various_Scripts_Collection/blob/main/l4d_unscope.sp) |
| `l4d2_storm.sp` | SilverShot 1.8 → 1.8 | 同作者、版本及 `l4d2_storm_*` 接口；维护天气逻辑时同时检查现有 `data/l4d2_storm*.cfg`。源码快照选历史同版本，不替换为当前新版天气系统。 | [历史源码副本](https://github.com/zonde306/l4d2sc/blob/master/l4d2_storm.sp)，[作者原帖](https://forums.alliedmods.net/showthread.php?t=184890) |
| `l4d2_weapon_csgo_reload.sp` | Harry Potter 2.1 → 1.0 | 较早实现，仅作换弹逻辑参考。候选开关 `l4d2_enable_reload_clip`/`l4d2_enable_clip_recover` 与当前 `l4d2_weapon_csgo_reload_allow`/`l4d2_weapon_csgo_reload_clip_recover` 不同，不是直接替换件。 | [源码分支](https://github.com/wyxls/L4D2-Plugins/tree/master/l4d2_weapon_csgo_reload)，[后续维护分支](https://github.com/fbef0102/L4D1_2-Plugins/tree/master/l4d2_weapon_csgo_reload) |
| `sceneprocessor.sp` | Mr. Zero 1.0.1 → 1.0.1 | 作者、版本、场景操作 natives/forwards 对应。使用仓库已有 `optional/astmod/include/sceneprocessor.inc`。 | [作者原帖](https://forums.alliedmods.net/showthread.php?t=241585)；本地 Anne 提交 `f4dbddd618aeb749a015cda4072576ae16bbeee3` 的 `addons/sourcemod/scripting/optional/AnneHappy/sceneprocessor.sp` |
| `tank_hud.sp` | 当前未提供 myinfo → 早期源码 | 同类面板实现，缺少当前 SMX 的 `sm_tankhud` 切换等逻辑，不能视为当前版本。依赖老 `l4d2_direct` include 链；AstRedux 已使用独立 `spechud`，此文件仅保留为旧插件参考。 | [早期源码](https://github.com/MatthewClair/sourcemod-plugins/blob/master/tank_hud/tank_hud.sp) |

### 编译与使用

本轮使用仓库 SourcePawn 1.12.0.7230 编译器，除 `tank_hud.sp` 外的 11 份源码均原样编译通过，存在旧代码及 include 警告。产物仅输出到工作区临时目录，未提交 SMX。未做运行验证。上游源码的行尾空白原样保留，`git diff --check` 对这些导入文件会提示行尾空白；本轮新增说明文档无此问题。

普通文件使用 `scripting/include`；`sceneprocessor.sp` 另需上述旧快照中的 `sceneprocessor.inc`。不要把整个旧 include 目录排在现代 SourceMod 标准库前面，否则旧 `handles.inc`、`float.inc` 会造成编译冲突。可把确需的插件专属 include 放到临时构建目录；`tank_hud` 尚缺少完成验证的旧 `l4d2_direct` 依赖链。

源码哈希按 Git 的 LF 换行规范化后计算；对应当前 SMX 哈希见 [源码快照元数据](plugin-source-provenance.json)。未来具体修改时，以本表标明的源码入口阅读事件、状态和接口，并针对已知差异验证，不把源码版本号相同当成现有行为完全一致的证据。

## 结构调整校验

204 个移动入口在相同编译参数下移动前后均为 201 个通过、3 个失败，没有新增失败。既有失败为 Legacy `jointeam.1.7.sp`、`l4d_drop.sp` 和参考版 `tank_hud.sp`；未以新编译产物替换运行 SMX。后缀改名不改变模块相对路径。另核对的历史 `archive/confoglcompmod.2.2.4.sp` 使用已被现代编译器移除的旧语法，不能用本次编译器直接重建。MoYu 许可保留在 `scripting/MoYu-LICENSE`。
