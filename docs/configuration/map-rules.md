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

static 只禁止路程 Boss，不影响固定 Boss；恢复允许后仍遵守地图刷新区间。

## 配置字段

文件按地图完整名称组织，`defaults` 为默认规则，`maps` 为各图规则。新图无需预先列入文件，游戏内修改时会新增当前地图条目。

| 字段 | 含义 |
| --- | --- |
| `static_tank` / `static_witch` | `1` 禁止对应路程 Boss；`0` 允许路程刷新 |
| `finale_mode` | `rounds` 为已知普通救援；`auto` 在确认普通救援阶段后开放编辑；`legacy` 使用预设救援规则，不提供菜单编辑 |
| `tank_round_1` / `tank_round_2` / `tank_round_later` | 对应救援第1轮、第2轮、第3轮及以后；`1` 允许，`0` 禁止。轮次不是同轮内每只 Tank 的编号 |
| `skip_intro` | `1` 本图始终跳过开场；`0` 按次数设置 |

手工编辑配置后，下一次回合开始读取；菜单和直接命令负责开局前的即时应用。游戏内保存直接更新这份配置，每次只修改当前地图的对应字段，保留其他规则。

## 救援轮次与逃生 Tank

轮次编辑用于已确认支持的普通救援；逃亡型救援使用预设规则。

AstRedux 在救援到来时保留已经存活的 AI Tank（`confogl_remove_existing_escape_tank 0`），包括灌油或其他地图流程已生成的 Tank；后续逃生 Tank 仍被禁止（`confogl_remove_escape_tank 1`）。这两项与救援轮次设置分开。

## 开场动画优先级

准备阶段按以下优先级处理：

1. `l4d_skip_intro_official 1`：默认开启，按内置官图完整名称匹配，始终跳过。
2. 本图 `skip_intro 1`：始终跳过，可用于接入第三方地图。
3. `l4d_skip_intro_play_count`：按本章队伍尝试次数决定是否跳过。

前两项均覆盖次数，包括 `-1`；开场跳过功能的总开关、模式限制和准备阶段策略开关仍然有效。官图无需写入配置名单。

AstRedux 设置 `l4d_skip_intro_ready 1`，在所有章节的准备阶段处理开场动画；正式开局后不再处理后续剧情。未启用此设置的模式仅处理首关开场。

### 队伍播放次数

未命中前两项优先规则时，`l4d_skip_intro_play_count` 决定播放次数：

| 值 | 效果 |
| --- | --- |
| `2`（AstRedux 设置） | 本章前两次队伍尝试正常播放，第三次起跳过 |
| `0` | 始终跳过 |
| `-1` | 始终播放 |

次数按队伍计算：同章重开累计，重新进入准备阶段和玩家重连不增加，后来加入的玩家沿用队伍次数。换章节清零；服务器重启或插件重新加载后重新计数。
