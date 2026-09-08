# 插件源码例外

未列在此表中的插件均已在本仓库保存可作为当前维护入口的源码。以下插件的源码关系或可重建状态仍不确定。

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
| `musical_jockeys_coop.smx` | 有源码但未复现 | 源码文件名为 `archive/musical_jockeys.sp`，对应关系待确认。 |
| `optional/astmod/jointeam.smx` | 有源码但未复现 | AstMod Legacy 保留源码与原二进制，当前构建关系尚未锁定。 |
| `versus_coop_mode.smx` | 有源码但未复现 | 本仓库维护源码，但当前二进制的构建关系尚未锁定。 |
| `l4d_boss_percent.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `pause.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `survivor_mvp.smx` | 源码重复，来源未确认 | 本仓库源码与 AstMod 快照均为候选。 |
| `enhancedsprays.smx` | 仅插件无源码 | 无冷却喷漆、旁观喷漆。 |
| `healer_witch.smx` | 仅插件无源码 | 秒妹回血。 |
| `l4d_swimming.smx` | 仅插件无源码 | 出门前可以游泳。 |
| `l4d2_saferoom_gun_control.smx` | 仅插件无源码 | 已知来自 ProMod。 |
| `l4d2_si_ladder_booster.smx` | 仅插件无源码 | 来源未确认。 |
| `l4d2_storm.smx` | 仅插件无源码 | 天气系统。 |
| `l4d2_tank_facts_announce.smx` | 仅插件无源码 | 来源未确认。 |
| `l4d2_weapon_csgo_reload.smx` | 仅插件无源码 | 老 Wingman 插件，兼容性未确认。 |
| `l4d_nowitch.smx` | 仅插件无源码 | 人数变化时开关 Witch 生成。 |
| `l4d_unscope.smx` | 仅插件无源码 | 老 Wingman 插件。 |
| `sceneprocessor.smx` | 仅插件无源码 | 旧版 `tls_restore_vocalize.smx` 的前置插件。 |
| `spawnstatefix.smx` | 仅插件无源码 | 来源与用途未确认。 |
| `swamp_finale_fix.smx` | 仅插件无源码 | 疑似修复 c3m4 终局。 |
| `tank_hud.smx` | 仅插件无源码 | ProMod 的旁观 Tank HUD。 |
| `tls_restore_vocalize.smx` | 仅插件无源码 | 允许手动发出笑声。 |
| `witch_glow.smx` | 仅插件无源码 | Witch Party 插件。 |

## 第三方原生扩展

`custom_fakelag.ext.2.l4d2.so` / `.dll` 与 `gamedata/custom_fakelag.games.txt` 来自 [ProdigySim 的 1.0.0.0 正式发布包](https://github.com/ProdigySim/custom_fakelag/releases/tag/1.0.0.0)，未修改二进制；对应源代码和构建流程由上游维护。发布 ZIP 的 SHA256 为 `BFDEC07FC54B1FC5D23C91020AD9EAB88D7D0DDD691BEEB95512039353010A30`，许可随 `extensions/custom_fakelag.LICENSE.txt` 保存。Linux 扩展已在本地 L4D2 2.2.4.3 / SourceMod 1.12.0.7230 实例加载；Windows 二进制未运行验证。命令包装层由本仓库 `scripting/optional/coop/player_fakelag.sp` 编译，不使用发布包的旧 SMX。
