# 地图规则配置

配置文件为 [`addons/sourcemod/configs/map_rules.cfg`](../../addons/sourcemod/configs/map_rules.cfg)，集中保存各地图的路程 Boss、救援轮次与开场动画规则。AstRedux 通过 `map_rules_enabled 1` 使用它；Zone 系列继续使用原模式配置。

## 游戏内设置

管理员（`b`）输入 `!mset` 打开当前地图的规则菜单。开局前修改本轮生效，开局后保存为下轮生效；灭团重开会重新读取，换图和重启后仍保留。菜单同时显示本轮状态和已保存的下轮状态。

路程 Boss 也可以直接设置：

| 操作 | Tank | Witch |
| --- | --- | --- |
| 禁止路程刷新 | `!setstatictank` | `!setstaticwitch` |
| 查询本轮和保存值 | `!getstatictank` | `!getstaticwitch` |
| 恢复允许路程刷新 | `!unsetstatictank` | `!unsetstaticwitch` |

static 只禁止路程 Boss，不影响固定 Boss；恢复允许后仍遵守地图刷新区间。未确认支持的救援不提供轮次编辑，逃亡型保留旧逻辑。

## 配置字段

文件按地图完整名称组织，`defaults` 为默认规则，`maps` 为各图规则。已有地图条目来自原 `astredux.cfg` 的 Boss 名单和救援预设。新图无需预先列入文件，游戏内修改时会新增当前地图条目。

| 字段 | 含义 |
| --- | --- |
| `static_tank` / `static_witch` | `1` 禁止对应路程 Boss；`0` 允许路程刷新 |
| `finale_mode` | `rounds` 为已知普通救援；`auto` 在观察到普通救援阶段后开放编辑；`legacy` 保留原预设的阶段拦截，不提供菜单编辑 |
| `tank_round_1` / `tank_round_2` / `tank_round_later` | 对应救援第1轮、第2轮、第3轮及以后；`1` 允许，`0` 禁止。轮次不是同轮内每只 Tank 的编号 |
| `skip_intro` | `1` 本图始终跳过开场；`0` 按次数设置 |

手工编辑配置后，下一次回合开始读取；菜单和直接命令负责开局前的即时应用。游戏内保存直接更新这份配置，每次只修改当前地图的对应字段，保留其他规则。

## 开场动画优先级

准备阶段按以下优先级处理：

1. `l4d_skip_intro_official 1`：默认开启，按内置官图完整名称匹配，始终跳过。
2. 本图 `skip_intro 1`：始终跳过，可用于接入第三方地图。
3. `l4d_skip_intro_play_count`：沿用原次数策略。

前两项均覆盖次数，包括 `-1`；原插件总开关、模式限制和准备阶段策略开关仍然有效。官图无需写入配置名单。

AstRedux 设置 `l4d_skip_intro_ready 1`，在所有章节使用 Ready 阶段的开场检查。未命中前两项时，`l4d_skip_intro_play_count 2` 表示本章前两次队伍尝试正常播放，第三次起跳过；`0` 始终跳过，`-1` 始终播放。计数来自回合边界，同章重开累计，Ready 重初始化和玩家重连不增加；换章节清零，服务器重启或插件重新加载后重新计数。后来加入的玩家沿用队伍次数。

跳过仅处理实际接管生还者的开场镜头，不要求全员都绑定摄像机；通过 Disable 结束镜头控制，不反复启动归位动画。正式开局后停止检查，不处理后续剧情。地图镜头实体保留，已有 OnUser1 输出每个镜头每次尝试最多触发一次，不清空地图延迟输出。没有启用 Ready 策略的模式保留原插件首关行为。

## 功能归属

AstRedux 的救援到来事件保留已经存活的 AI Tank（`confogl_remove_existing_escape_tank 0`），不提前结束灌油或其他地图流程已生成的 Tank。后续逃生 Tank 仍由 `confogl_remove_escape_tank 1` 拦截，与救援阶段轮次设置分开。新开关默认值为 `1`，其他模式保留原有清理行为。

`!mset` 菜单集成在 `admin_tools`。路程 Boss、救援轮次和开场动画分别由 `boss_spawn_rules`、`finale_tank_rules`、`l4d_skip_intro` 执行和保存，static 命令由 `boss_spawn_rules` 注册。
