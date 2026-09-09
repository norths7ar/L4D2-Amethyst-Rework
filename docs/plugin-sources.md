# 插件源码

## 目录对应

以 `addons/sourcemod/` 为基准，`scripting/` 的插件入口尽量与 `plugins/` 使用相同相对路径：基础插件在根目录，通用修复在 `fixes/`，功能插件在 `optional/`，再分 `competitive/`、`coop/` 和 Legacy `astmod/`。跨模式共用源码可放在 `scripting/optional/`。

`include/` 和插件私有模块目录不对应独立 SMX；`optional/astmod/include/` 保留旧依赖，编译时不要让整套旧标准库覆盖现代 include。`sourcemod/` 保留编译器、标准 include 和测试材料，`archive/`、`dev_plugins/` 保留历史与开发材料。

当前维护入口使用 `<name>.sp`；历史副本使用 `<name>.<version>.sp`，分支副本使用 `<name>.<来源>-ver.sp`。不同功能目录中各自维护的入口及其内部模块保留原名。

## 源码例外

这里只列缺源码、构建对应关系尚未确认或仅有参考实现的插件。普通源码直接阅读 `.sp`，不另列作者和下载记录。

| 插件 | 状态 |
| --- | --- |
| `all4dead2.smx` | 有源码，未确认同构建 |
| `autowipe.smx` | 有源码，未确认同构建 |
| `difficulty_adjustment_system.smx` | 有源码，未确认同构建 |
| `HunterSkeetSound.smx` | 有源码，未确认同构建 |
| `l4d2_bot_spit_ignite_gascan.smx` | 有源码，未确认同构建 |
| `l4d2_drop.smx` | 有源码，未确认同构建 |
| `l4d2_sniper_stats.smx` | 有源码，未确认同构建 |
| `l4d2_votetospec.smx` | 有源码，未确认同构建 |
| `mob_interval_limit.smx` | 有源码，未确认同构建 |
| `pills_giver.smx` | 有源码，未确认同构建 |
| `script_reloader.smx` | 有源码，未确认同构建 |
| `versus2coop.smx` | 有源码，未确认同构建 |
| `weapon_slowdown.smx` | 有源码，未确认同构建 |
| `wingman.smx` | 有源码，未确认同构建 |
| `l4d_reload_fix.smx` | 有源码，未确认同构建 |
| `l4d2_nobackjump.smx` | 有源码，未确认同构建 |
| `musical_jockeys_coop.smx` | 有源码，未确认同构建 |
| `optional/astmod/jointeam.smx` | 有源码，未确认同构建 |
| `versus_coop_mode.smx` | 有源码，未确认同构建 |
| `l4d_boss_percent.smx` | 有源码，未确认同构建 |
| `pause.smx` | 有源码，未确认同构建 |
| `survivor_mvp.smx` | 有源码，未确认同构建 |
| `enhancedsprays.smx` | 缺源码 |
| `healer_witch.smx` | 有源码，未确认同构建 |
| `l4d_swimming.smx` | 有源码，未确认同构建 |
| `l4d2_saferoom_gun_control.smx` | 缺源码 |
| `l4d2_si_ladder_booster.smx` | 有源码，未确认同构建 |
| `l4d2_storm.smx` | 有源码，未确认同构建 |
| `l4d2_tank_facts_announce.smx` | 有源码，未确认同构建 |
| `l4d2_weapon_csgo_reload.smx` | 仅参考实现 |
| `l4d_nowitch.smx` | 缺源码 |
| `l4d_unscope.smx` | 有源码，未确认同构建 |
| `sceneprocessor.smx` | 有源码，未确认同构建 |
| `spawnstatefix.smx` | 有源码，未确认同构建 |
| `swamp_finale_fix.smx` | 缺源码 |
| `tank_hud.smx` | 仅参考实现 |
| `tls_restore_vocalize.smx` | 有源码，未确认同构建 |
| `witch_glow.smx` | 有源码，未确认同构建 |

## 已知差异与特殊依赖

- `l4d_reload_fix.smx`、`l4d2_nobackjump.smx`：候选源码分别叫 `l4d2_reload_fix.sp`、`l4d2_nobackjumps.sp`，对应关系待确认。
- `l4d_boss_percent`、`pause`、`survivor_mvp`：存在不同版本的源码，尚未确定现有二进制对应哪份。
- `l4d2_si_ladder_booster`：源码和 SMX 都标为 2.3.3，但源码增加了 `l4d2_boost_multiplier`，当前 SMX 未见此项。
- `spawnstatefix`：SMX 为 1.0，源码为 1.1，增加 `uf4_airfield` 自动修复；涉及引擎内存偏移，修改时需核对兼容性。
- `l4d_swimming`、`l4d_unscope`：SMX 分别为 1.8、1.9，源码分别为 1.9、1.10；源码更新日志说明新版修复 SM 1.11 编译警告。
- `l4d2_weapon_csgo_reload`：SMX 为 2.1，源码为较早的 1.0。源码的 `l4d2_enable_reload_clip` / `l4d2_enable_clip_recover` 与现有 `l4d2_weapon_csgo_reload_allow` / `l4d2_weapon_csgo_reload_clip_recover` 不同，仅作参考。
- `tank_hud`：参考源码缺少现有 SMX 的 `sm_tankhud` 切换等逻辑，依赖旧 `l4d2_direct` include 链。AstRedux 当前使用 `spechud`。
- `sceneprocessor`：编译另需 `optional/astmod/include/sceneprocessor.inc`，不要因此导入整套旧标准库。
- Legacy `jointeam.1.7.sp`、`l4d_drop.sp` 和 `archive/confoglcompmod.2.2.4.sp`：存在现代编译器下的接口或旧语法错误，不能直接重建。

## 原生扩展

`custom_fakelag` 扩展源码未放在本仓库，修改扩展需使用 [上游源码](https://github.com/ProdigySim/custom_fakelag)。本地命令包装层是 `scripting/optional/coop/player_fakelag.sp`。
