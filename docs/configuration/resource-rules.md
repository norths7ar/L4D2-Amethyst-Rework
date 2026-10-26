# 资源规则

AstRedux 的替换、区域例外和数量／分布统一写在 [`resource_rules.cfg`](../../addons/sourcemod/configs/resource_rules.cfg)。Zone 系列沿用框架资源设置与 Stripper，不使用下述策略文件。

## 入口与生效

- `resource_rules_file`：相对 SourceMod `configs` 的路径；AstRedux 使用 `resource_rules.cfg`，空字符串使用框架设置。须在地图生成前选定，修改配置或重载插件后换图生效。
- `resource_rules_visualize`：`0` 正常执行，`1` 预览数量／分布裁剪，`2` 执行并高亮保留点；预览时替换照常执行。
- `resource_finale_supply_clusters`：默认 `0`，AstRedux 开启；换图生效。救援终章自动识别起点外的紧凑医疗包组，转换为不受数量／分布裁剪的止痛药，不要求预录终点区域。

## 结构与覆盖

根节点为 `ResourceRules`，通用设置放 `global`，地图特例放 `maps/<地图名>`。地图按字段覆盖全局，省略即继承；分类的 `members` 列表整体替换。MapInfo 提供区域信息，资源限额由本文件配置。

| 配置块／字段 | 含义 |
| --- | --- |
| `rules` | 按资源名替换：`none` 删除，自身名称保留，逗号分隔的目标列表等概率抽取。 |
| `melee_pickups` | 近战刷新点拾取次数，默认 1。 |
| `regions/start,end,along,finale` | 按资源名设置区域替换例外，未指定的资源回退到通用 `rules`；救援例外见下文。 |
| `distribution/<资源名>` | 单资源的数量、路线与统计区域策略。 |
| `categories/<分类名>` | `members` 为逗号分隔的资源名，成员共用数量与分布策略。 |

最小覆盖示例（数值仅作演示）：

```text
"ResourceRules"
{
    "global"
    {
        "rules" { "first_aid_kit" "none" }
        "regions" { "finale" { "first_aid_kit" "pain_pills" } }
        "distribution"
        {
            "pain_pills"
            {
                "limit" "8"
                "flow_density" "0.3"
                "min_distance" "500"
            }
        }
        "categories"
        {
            "recovery"
            {
                "members" "pain_pills,adrenaline,first_aid_kit"
                "limit" "10"
            }
        }
    }
    "maps"
    {
        "c1m1_hotel"
        {
            "distribution"
            {
                "pain_pills"
                {
                    "limit" "6"
                    "flow_density" "0"
                }
            }
        }
    }
}
```

旅馆的药上限为 6，密度关闭，间距仍继承 500；要关闭间距须显式写 `min_distance 0`。止痛药已有单资源策略，因此退出 `recovery`，分类上限 10 只约束其余成员。数量均按替换后的最终资源统计。

## 数量与分布字段

以下字段可写在 `distribution/<资源名>` 或 `categories/<分类名>` 中。这里列的是字段默认值，不是当前止痛药配置：

| 字段 | 含义与默认值 |
| --- | --- |
| `limit` | 固定数量上限，默认 `-1` 不设上限，`0` 清除，正整数封顶。 |
| `flow_min / flow_max` | 路线进度区间，取值 0..1，默认 0 / 1。 |
| `flow_density` | 每 1000 导航 flow 长度的数量，非负数，默认 0 关闭。 |
| `min_distance` | 同策略任意两个保留点间的三维直线最小距离，Source 单位，非负数，默认 0 关闭。 |
| `flow_finale` | 救援关是否应用密度与路线区间筛选，默认 0；固定限额和空间间距仍生效。 |
| `regions` | 数量／分布统计区域：`start,end,along,unknown`，默认 `along,unknown`。 |

**归属以合并后的配置为准。** 有单资源策略的整个资源退出分类，包括该策略统计范围外的点；`limit -1` 也保留这一归属，仅取消固定上限。要交回分类，须移除单资源策略，地图层省略字段不能取消继承。单资源块至少包含一个已知数量／分布字段，空块或仅含未知字段会报错。

其余资源只能归一个分类；多分类接管报错，与声明顺序或各分类范围无关。同分类重复成员不报错，已有单资源策略的成员不参与分类冲突判断。

启用密度时，预算为 `floor(maxflow × (flow_max - flow_min) × flow_density / 1000)`，其中 `maxflow` 是整图最大导航 flow 长度。固定上限非负时取两者较小值；`limit -1` 仍受密度预算约束。预算可以为 0，候选不足或间距不满足时只减少保留量。

有预算时沿有效路线区间分布选点，无预算时按间距筛选。整图 flow 无效或全部候选缺少 flow 时，跳过密度与路线区间筛选并告警，保留固定上限和间距约束；部分候选缺少 flow 时，优先选有效点，再用无 flow 点填补同一预算。

## 区域与救援例外

区域识别优先使用 MapInfo，数据缺失时用精确盒子后备，起点识别优先；未知位置使用通用替换规则，按 `unknown` 参与数量限制。

`regions/finale` 是**替换例外**，仅作用于救援终章已识别的 `end` 补给范围（MapInfo 的 `end_point/end_dist`），不是整张救援地图。按资源名依次回退：`finale → end → 通用 rules`；普通地图使用对应区域规则。

换出的资源仍属于 `end`。要把它计入数量／分布限制，策略的 `regions` 须包含 `end`；默认 `along,unknown` 将其豁免。`flow_finale` 则是**路线筛选开关**，控制救援关的密度和路线区间，与上述替换例外独立。

### 救援补给自动识别

三方图不会提前录入终点数据，但救援时仍需要补给。因此，插件尝试将终章中起点外、集中摆放的四个及以上医疗包识别为补给，整组换成药，并跳过数量和分布裁剪。起点的包仍按原规则处理。

这不保证准确识别救援场地：路途中符合条件的四包组也会保留，零散或不足四包的补给可能漏掉。这是为了让未经专门配置的地图也能获得一些救援补给，而接受的取舍。

由 `resource_finale_supply_clusters` 控制，AstRedux 默认开启，换图生效。

## 当前玩法与保留范围

资源先按地图候选池和枪械成组规则生成，再替换、删除和裁剪，空缺不补刷。T2 换 T1，狙击仅保留 Scout。默认删除医疗包、电击器，肾上腺素换止痛药，原生止痛药保留；救援终章的终点补给范围内医疗包换药，自动成组识别另保护起点外符合条件的补给。

止痛药全局固定上限为 `-1`，路线区间 0.2–0.9、密度 `0.3`、最小间距 `500`，地图可覆盖；`recovery`、`throwables` 分类默认不限量。

数量按地面实体／刷新点计，而非可拾取次数。医疗资源、投掷物、武器、弹药堆和已识别机关物品均可配置，标准灌油任务资源及兼容投票放行资源豁免。物品进入玩家装备后，即使传递或掉落也退出地图替换、分布筛选和地面额度统计。

灌油机关油桶按 `weapon_scavenge_item_spawn` 的真实生成关联保护；暂时不选择因本图有灌油机关而放行所有普通油桶。关联接口目前支持 Linux 服务端；油桶不再按皮肤单独豁免，接口不可用时会记录一次启动错误。

同轮保留点固定，后续生成资源只能填补空位，重开重新选择。需要复用药丸、针及三种投掷物时，启用 `confogl_enable_itemtracking 1`：`confogl_itemtracking_savespawns 0` 每轮重新选择，设为 `1` 复用已保存结果。Zone 系列的 ItemTracking 继续使用其 MapInfo 覆盖、数量／路线筛选和人数限额。
