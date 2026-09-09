# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架的服务端配置。仓库保留 Rework 的对抗配置，并新增了 AstMod 药役，以及在 AstMod 基础上开发的 AstRedux 药役。

## 设计取舍

### AstRedux 与 AstMod 的关系

AstMod 是海洋维护的原版Config，最新版本为2.8.1；AstRedux 是轨迹目前正在更新维护的改版插件，目前侧重于简化功能、优化结构，处于早期快速迭代中。计划中的 AstFlex 为 AstRedux 的低压力版预设，供新手朋友使用。

### Redux 用声明式人数 profile 表达基线

旧 Mod 使用的 DAS 通过人数切换整份难度 cfg：数值、插件加载、脚本重载和临时运行行为会一起变动，维护一个规则时往往要追踪多层间接关系。Redux 将 1–4 人的最终基线直接写入 `astredux_profiles.cfg`；Profile Controller 只负责选择和下发，Tank、波次和 AutoWipe 等组件各自负责自己的运行规则。具体数值及当前生效项以 `addons/sourcemod/configs/astredux_profiles.cfg` 为准。

### 尽量复用 Rework，共享能力不复制

Competitive Rework 负责模式生命周期、通用修复、基础管理、投票与对抗规则等共享能力。

服务器没有 matchmode 时，Confogl 按 `cfg/server.cfg` 的设置，在首个真人客户端完成连接后的下一帧自动加载 `astredux`；空服时保持该模式。加载 `campaign_switcher` 的模式在空服倒计时后，会切换到配置的 `campaign_empty_matchmode`（当前为 `astredux`）并随机选择一张官方战役首图。管理员使用 `sm_forcechangematch <mode> [map]` 手动切换。

插件按实际运行生态归类：`optional/` 根目录是跨 Competitive/Coop 通用组件，`optional/competitive/` 是PVP药抗专用插件，`optional/coop/` 是PVE药役专用插件，`optional/astmod/` 是AstMod专用的遗留实现；未加载二进制分别放在 `optional/astmod/disabled/` 与 `plugins/disabled/`。AstRedux 的模式身份留在其 matchmode、cfg、VScript、显示名等模式入口，通用组件保持中性命名。

### 服务器功能与 Ast 配置分开

服务器自己的娱乐和便利功能——例如地图切换、终章下一图投票、公告与管理员维护入口——服务于整台服务器，不属于 Ast 的玩法规则。它们应使用 Rework 的共享入口或独立服务器配置，并在各模式间保持一致。

AstMod/AstRedux 只定义进入 Ast 模式后如何游玩。某项功能是否归入 Ast，取决于它是否改变 Ast 的规则本身，而不是它最早在哪个模式里实现。

### 关于命名

运行时主线使用 `astredux` matchmode、mutation、cfg、VScript 和显示名；`amethyst` 仅用于说明上游历史。

## 入口与维护

- `!match` / `!chmatch` / `!rmatch`：由 Rework 统一进入、切换或重置模式。
- `!ast`：Ast 玩法调整菜单；`!tz` 仅保留为兼容短命令。
- `!si <时间> <数量>`：调整当前地图的波次参数；多人时走投票。
- `!vote`、`!mapvote`、`!nextmap`、`!chaptervote`：服务器通用投票入口。
- `tools/validate_astmod_integration.ps1`：检查必要资产、模式加载链和关键配置结构的静态校验。

具体数值以 cfg、SourcePawn 和 VScript 为准；开发计划见 ROADMAP，已完成变更见 CHANGELOG。

## AstRedux 配置与组件

模式入口为 `cfg/cfgogl/astredux/` 与 `astredux` mutation；`profile_controller_config` 指向 `configs/astredux_profiles.cfg`，保存 1–4 人基线。`tank_health`、`tank_melee_damage`、`witch_control`、`smg_reload_control`、`wave_spawner` 和 `autowipe` 分别执行自己的规则，`!si` 的地图临时值由 Wave Spawner 维护。共享 Stripper 资产位于 `cfg/stripper/astredux/`，地图例外在各模式的 `mapinfo.txt`。

玩家队伍与跨图席位看 `player_manager`，准备和暂停看 `ready_pause`，初始药物与背包看 `survivor_loadout`，异常管理命令看 `admin_tools`。AstMod 保留自己的 Legacy 实现。

AstRedux 每轮全员准备后倒计时开局，`!fs` 也走倒计时；暂停恢复共用每人准备与面板。开局倒计时结束触发 `OnRoundIsLive`，由 `survivor_loadout` 每轮清理医疗槽、恢复健康并发起始药；恢复暂停不会重做这些操作。准备面板支持 `!hide`／`!show`，避让菜单与投票，并列出加载玩家和待返回生还者的席位剩余时间。换章席位按 SteamID 保留，从下一张图开始计时，恢复、主动 `!spec`、超时或正式开局结束相应等待；旁观者预留不阻塞开局。

连接公告由 `optional/coop/cannounce.sp`（Arg! 1.9 的本地适配版）构建，复用随源码保存的 multicolors。`sm_ca_showconnecting` 控制加载前提示，`sm_ca_connectdisplaytype` 保留原版的公告时点设置；默认在管理员检查后输出完整身份和地域公告。既有 `data/cannounce_settings.txt`、`cannounce_messages.txt` 与自动生成的 `cfg/sourcemod/cannounce.cfg` 格式保留。

### 商店与玩家功能

这些组件由 `cfg/cfgogl/astredux/plugins_3.cfg` 加载，不影响未加载它们的模式。

| 功能 | 编辑入口 | 使用方式 |
| --- | --- | --- |
| 战役商店（默认关闭） | `cfg/sourcemod/campaign_shop.cfg` 控制开关和状态限制；`addons/sourcemod/configs/campaign_shop.txt` 控制奖励、商品开关、初价与个人购买涨价 | `!buy` 打开菜单，`!ammo` 购买主武器备用弹药；管理员 `sm_campaign_shop_reload` 重读商品与奖励，错误配置保留上一份有效设置。 |
| 追加延迟 | `cfg/sourcemod/player_fakelag.cfg` 设置上限 | `!fakelag` 查询，`!fakelag <毫秒>` 设置自己，0 关闭；配置管理员可用 `!fakelag <玩家> <毫秒>` 与 `!printlag`。默认不追加延迟。 |
| 旁观 HUD | `spechud.sp` 的 PVE 显示层 | 旁观者 `!spechud` / `!tankhud` 切换；准备和暂停期间避让准备面板。AstRedux 不再同时加载旧 `tank_hud.smx`。 |
| 帽子 | `addons/sourcemod/data/l4d_hats.cfg` 保存原生模型与位置、角度、大小 | `!hat` / `!hats`；免费开放，保留上游的帽子偏好 cookie，不建立积分解锁数据库。 |
| 称号 | `addons/sourcemod/configs/chat_tags.cfg` | `!tag` / `!tags` 显示、隐藏或选择允许的称号；管理员默认“管理员”，普通玩家默认无称号，不开放任意文字输入。 |

商店当前默认关闭，暂停购买和积分奖励，保留源码与配置。以下记账规则在启用时适用：积分和个人商品购买次数保存在内存，跨章节、团灭重开不回滚；切换战役清空，服务器重启或商店插件卸载也会清空。修改价格与奖励请使用配置重载命令，不要通过卸载插件重载。配置中的数值是临时试玩值；Witch 奖励暂为 0，电击器默认不开放，尚未完成完整 AstRedux 规则下的实际使用验证。


## AstRedux 寻敌规则

`optional/coop/si_targeting.smx` 通过 `si_bile_neutral` 控制六类特感与 Tank 的胆汁目标保留待遇，AstRedux 默认开启；共享选人及接触换目标流程忽略胆汁带来的额外锁定，普通感染者吸引与玩家胆汁效果保持原样。`AI_HardSI` 继续负责口水配控和 Charger 的已控目标处理，未另加近身距离强制换人规则。

该组件使用现有 SourceScramble 扩展，`gamedata/si_targeting.txt` 当前针对 32 位 Linux 服务端 2.2.4.3（10097）验证。各补丁位置全部校验通过后才应用；关闭开关或卸载插件会恢复原指令，平台或引擎字节不匹配时插件报错停用。

## 相关文档

- [插件源码](docs/plugin-sources.md)：源码布局、来源和已知差异。
- [架构笔记](docs/architecture.md)：配置分层、职责和设计原则。
- [服务器运维](docs/server-operations.md)：Ubuntu L4D2 服务器维护笔记。
- [ROADMAP](docs/ROADMAP.md)：后续开发计划。
- [CHANGELOG](docs/CHANGELOG.md)：未发布变更与版本更新记录。

## 上游与致谢

框架和大量通用修复来自 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)；AstMod 原版由海洋空气维护，公开源码见 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。其他插件继续保留各自源码与二进制中的作者信息；许可见 [LICENSE](LICENSE)。
