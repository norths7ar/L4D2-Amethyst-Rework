# 作者配置阅读指南

这份文档说明改一项规则时该先看哪里、它由谁加载，以及各层配置如何协作。

## 先从调用链读起

以玩家在游戏内选择 `!match` 的 `astredux` 为例：

```text
addons/sourcemod/configs/matchmodes.txt
  → 注册 astredux，并提供玩家看到的名称
  → Confogl / Competitive Rework 选择 cfg/cfgogl/astredux/
      → shared_cvars.cfg：模式身份、通用模式 CVar、Stripper 路径
      → confogl_plugins.cfg：按既定顺序执行 plugins_1/2/3.cfg
          → 各插件加载项
      → confogl.cfg：进入模式时的规则
      → confogl_off.cfg：退出模式时的收尾
      → mapinfo.txt：地图特例与物资限制
```

`astmod` 复用同一条骨架，但它以兼容为主，不主动更新；`astredux` 是当前 Coop/PVE 主线，以 `cfg/cfgogl/astredux/`、`astredux` mutation、模式身份入口和 `addons/sourcemod/configs/astredux_profiles.cfg` 组成规则层。AstRedux 的 generic profile controller 通过 `profile_controller_config` 指向 `configs/astredux_profiles.cfg`。AstMod 与 AstRedux（以及暂停的 AstFlex）共享的 Stripper 资产权威目录是 `cfg/stripper/astredux/`。

服务器无 matchmode 启动时，`cfg/server.cfg` 让 Confogl 在首个真人客户端完成连接后的下一帧自动加载 `astredux`；该模式通过 `confogl_match_unload_when_empty 0` 保持空服期间的加载状态。任何加载 `campaign_switcher` 的模式在空服等待后，都会选择一张官方首图，并通过 `campaign_empty_matchmode`（当前为 `astredux`）切换到该模式再换图。管理员仍可用 `sm_forcechangematch <mode> [map]` 手动切换。

## 各层只回答一个问题

| 路径 | 回答的问题 | 修改时的原则 |
| --- | --- | --- |
| `cfg/server.cfg` | 这台服务器的全局基线是什么？ | 日志、网络、槽位等不随模式切换的设置。 |
| `cfg/generalfixes.cfg` | 所有模式都需要哪些引擎修复？ | 模式中立的引擎修复入口。 |
| `addons/sourcemod/configs/matchmodes.txt` | 玩家可以选择哪些模式？ | 注册 ID 与显示名；每个条目对应一套完整的模式配置。 |
| `cfg/cfgogl/<mode>/shared_cvars.cfg` | 这个模式以什么 mutation、Stripper 和共同规则运行？ | 模式身份和模式级 CVar。 |
| `cfg/cfgogl/<mode>/confogl_plugins.cfg` | 该模式要加载哪几段插件清单？ | Ast 模式按命令缓冲限制确定顺序地 `exec plugins_1/2/3.cfg`；Competitive Rework 模式也可直接在此加载，和/或 `exec shared_plugins.cfg`。 |
| `cfg/cfgogl/<mode>/plugins_1.cfg` 至 `plugins_3.cfg` / `shared_plugins.cfg` | 具体加载哪些插件？ | 两种合法布局都只包含插件生命周期命令与 `exec`，绝不放 gameplay CVar；Ast 模式用有序切分，Competitive Rework 模式可直接加载。 |
| `cfg/cfgogl/<mode>/confogl.cfg` / `confogl_off.cfg` | 进入与退出模式各做什么？ | 分别写 on/off 行为；收尾仍由 Rework 生命周期统一处理。 |
| `cfg/cfgogl/<mode>/mapinfo.txt` | 哪些规则必须按地图覆写？ | 地图例外与物资限制。 |
| `addons/sourcemod/configs/astredux_profiles.cfg` | Redux 在 1–4 人时的最终规则是什么？ | Redux 的唯一人数基线；generic Controller 应用 CVar，`tank_health`、`tank_melee_damage`、`witch_control`、`smg_reload_control`、刷特和 AutoWipe 组件各自执行。 |

## 插件加载的职责

Competitive Rework 负责插件锁定、模式切换和逆序卸载。自定义模式通过现有生命周期进入和退出。

下面四条命令由框架生命周期管理：

```text
sm plugins load_unlock
sm plugins unload_all
sm plugins load_lock
sm plugins refresh
```

新增插件时，先判断它属于哪一层：

1. 所有模式都使用的引擎修复：`generalfixes.cfg`；
2. 某个 matchmode 的功能：Ast 模式使用按命令缓冲限制切分的 `plugins_1/2/3.cfg`；Competitive Rework 模式可直接写入 `confogl_plugins.cfg` 和/或 `exec shared_plugins.cfg`。两种插件清单形式都只放插件生命周期命令与 `exec`，不要放 gameplay CVar；
3. 个人服务器功能：个人可选层的独立入口；
4. 新增插件时，同时核对所需的 `configs`、`data`、`gamedata`、`translations`、VScript、Stripper 与 VPK 资产。

插件的二进制来源和可重建性见 `PLUGIN_SOURCE_INVENTORY.md`。

## 修改规则时的阅读顺序

- 想改 AstMod 的玩法数值：`cfg/cfgogl/astmod/shared_cvars.cfg`、`confogl.cfg` 与相关插件配置。
- 想改 Redux 的人数基线：`astredux_profiles.cfg`；想改执行方式：分别看 `profile_controller`、`tank_health`、`tank_melee_damage`、`witch_control`、`smg_reload_control`、`wave_spawner` 和 `autowipe`。`!si` 临时值由 Wave Spawner 单独维护。
- 想改 Redux 的玩家流程：队伍、bot 席位与跨图位置保护看 `player_manager`；开局加载门禁与 Coop 暂停看 `ready_pause`；跨图背包与开局药物看 `survivor_loadout`；`!fuck` 等管理异常处理看 `admin_tools`。AstMod 的同类行为仍由 `optional/astmod/jointeam.smx` 和 `pause_coop.smx` 保持；AstFlex 暂停且不在当前维护范围。

- 想改武器：先找当前加载的武器属性插件与该模式的加载清单，再确认这项属性没有被模式 cfg 或 mutation 覆盖。
- 想改某张地图：先读共享权威目录 `cfg/stripper/astredux/maps/`，再读对应模式的 `mapinfo.txt`。
- 想排查“切模式后残留”：`confogl_off.cfg` 与 Rework 的 `pred_unload_plugins` 路径。

AstRedux 每轮全员准备后倒计时开局，`!fs` 也走倒计时；暂停恢复共用每人准备与面板。开局倒计时结束触发 `OnRoundIsLive`，由 `survivor_loadout` 每轮清理医疗槽、恢复健康并发起始药；恢复暂停不会重做这些操作。准备面板支持 `!hide`／`!show`，避让菜单与投票，并列出加载玩家和待返回生还者的席位剩余时间。换章席位按 SteamID 保留，从下一张图开始计时，恢复、主动 `!spec`、超时或正式开局结束相应等待；旁观者预留不阻塞开局。

连接公告由 `optional/coop/cannounce.sp`（Arg! 1.9 的本地适配版）构建，复用随源码保存的 multicolors。`sm_ca_showconnecting` 控制加载前提示，`sm_ca_connectdisplaytype` 保留原版的公告时点设置；默认在管理员检查后输出完整身份和地域公告。既有 `data/cannounce_settings.txt`、`cannounce_messages.txt` 与自动生成的 `cfg/sourcemod/cannounce.cfg` 格式保留。

## AstRedux 商店与玩家功能

这些组件由 `cfg/cfgogl/astredux/plugins_3.cfg` 加载，不影响未加载它们的模式。

| 功能 | 编辑入口 | 使用方式 |
| --- | --- | --- |
| 战役商店 | `cfg/sourcemod/coop_shop.cfg` 控制开关和状态限制；`addons/sourcemod/configs/coop_shop.txt` 控制奖励、商品开关、初价与个人购买涨价 | `!buy` 打开菜单，`!ammo` 购买主武器备用弹药；管理员 `sm_coopshop_reload` 重读商品与奖励，错误配置保留上一份有效设置。 |
| 追加延迟 | `cfg/sourcemod/player_fakelag.cfg` 设置上限 | `!fakelag` 查询，`!fakelag <毫秒>` 设置自己，0 关闭；配置管理员可用 `!fakelag <玩家> <毫秒>` 与 `!printlag`。默认不追加延迟。 |
| 旁观 HUD | `coop_spechud.sp` 的 PVE 显示层 | 旁观者 `!spechud` / `!tankhud` 切换；准备和暂停期间避让准备面板。AstRedux 不再同时加载旧 `tank_hud.smx`。 |
| 帽子 | `addons/sourcemod/data/l4d_hats.cfg` 保存原生模型与位置、角度、大小 | `!hat` / `!hats`；免费开放，保留上游的帽子偏好 cookie，不建立积分解锁数据库。 |
| 称号 | `addons/sourcemod/configs/coop_tags.cfg` | `!tag` / `!tags` 显示、隐藏或选择允许的称号；管理员默认“管理员”，普通玩家默认无称号，不开放任意文字输入。 |

商店积分和个人商品购买次数保存在内存，跨章节、团灭重开不回滚；切换战役清空，服务器重启或商店插件卸载也会清空。修改价格与奖励请使用配置重载命令，不要通过卸载插件重载。配置中的数值是临时试玩值；Witch 奖励暂为 0，电击器默认不开放，尚未完成完整 AstRedux 规则下的实际使用验证。

## 维护原则

- 一项规则有明确的权威位置，其他文档链接过去。
- 改动前先定位它属于全服基线、模式规则、地图例外或运行时临时调整。
- 玩法验证由实际进图和模式往返完成；静态校验覆盖资产和加载声明。
- 二进制来源与可重建性记录在 `PLUGIN_SOURCE_INVENTORY.md`；当前模式行为以实际 cfg、插件加载清单和 VScript 为准。
