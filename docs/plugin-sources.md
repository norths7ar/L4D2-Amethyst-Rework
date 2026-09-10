# 插件源码

此处只包括 AstRedux 的插件，包括随模式加载的共享插件和基础依赖。

## 目录对应

以 `addons/sourcemod/` 为基准，`scripting/` 的插件入口尽量与 `plugins/` 使用相同相对路径；跨模式共用源码可放在 `scripting/optional/`。`include/` 和插件私有模块目录不对应独立 SMX。

当前维护入口使用 `<name>.sp`；历史副本使用 `<name>.<version>.sp`，分支副本使用 `<name>.<来源>-ver.sp`。

## 源码例外

这里只列缺源码、构建对应关系尚未确认或仅有参考实现的插件。普通源码直接阅读 `.sp`，不另列作者和下载记录。

| 插件 | 状态 |
| --- | --- |
| `all4dead2.smx` | 有源码，未确认同构建 |
| `HunterSkeetSound.smx` | 有源码，未确认同构建 |
| `l4d2_bot_spit_ignite_gascan.smx` | 有源码，未确认同构建 |
| `l4d2_drop.smx` | 有源码，未确认同构建 |
| `l4d2_votetospec.smx` | 有源码，未确认同构建 |
| `pills_giver.smx` | 有源码，未确认同构建 |
| `script_reloader.smx` | 有源码，未确认同构建 |
| `l4d_reload_fix.smx` | 有源码，未确认同构建 |
| `musical_jockeys_coop.smx` | 有源码，未确认同构建 |
| `enhancedsprays.smx` | 缺源码 |
| `healer_witch.smx` | 有源码，未确认同构建 |
| `l4d_swimming.smx` | 有源码，未确认同构建 |
| `l4d2_si_ladder_booster.smx` | 有源码，未确认同构建 |
| `l4d2_tank_facts_announce.smx` | 有源码，未确认同构建 |
| `spawnstatefix.smx` | 有源码，未确认同构建 |
| `tls_restore_vocalize.smx` | 有源码，未确认同构建 |
| `witch_glow.smx` | 有源码，未确认同构建 |

## 已知差异与特殊依赖

- `l4d2_si_ladder_booster`：源码和 SMX 都标为 2.3.3，但源码增加了 `l4d2_boost_multiplier`，当前 SMX 未见此项。
- `spawnstatefix`：SMX 为 1.0，源码为 1.1，增加 `uf4_airfield` 自动修复；涉及引擎内存偏移，修改时需核对兼容性。
- `l4d_swimming`：SMX 为 1.8，源码为 1.9；源码更新日志说明新版修复 SM 1.11 编译警告。

## 原生扩展

`custom_fakelag` 扩展源码未放在本仓库，修改扩展需使用 [上游源码](https://github.com/ProdigySim/custom_fakelag)。本地命令包装层是 `scripting/optional/coop/player_fakelag.sp`。
