# 资源规则

`optional/resource_rules.smx` 统一承载武器替换、安全室物资处理和资源策略。Zone 系列继续使用原有 `l4d2_addweaponrule`、`confogl_*`、`sm_safeitemkill_*` 设置及 Stripper；AstRedux 使用 `addons/sourcemod/configs/resource_rules.cfg`。下文的策略文件格式适用于后者。

## 半场一致性

复用 Confogl 的 ItemTracking，而非另写一套保存机制。Zone 系列在替换和安全室清理后，由 ItemTracking 执行原数量／路程筛选，再保存和重建药丸、针及三种投掷物；原有 MapInfo 覆盖和人数限额保持不变。武器生成仍使用原生生成器及各模式原有固定替换规则。

AstRedux 的数量／分布仍由策略文件负责，ItemTracking 只提供可选的结果保存／重建，不再套用旧限额。`confogl_enable_itemtracking 1` 启用这一接口；`confogl_itemtracking_savespawns 0` 保持每轮重新选择，设为 `1` 则复用已保存的上述五类补给。新地图清除记录。重建时不重复执行资源替换和随机裁剪。

随机补给按地图候选池抽取，再执行删除或替换，最后按替换后的物品裁剪数量和分布。合并全局与地图配置后，有单资源策略的资源只应用自身策略，整个资源退出分类；其余资源可由一个分类接管，不叠加单项与分类限制，也不按声明顺序处理分类冲突。

AstRedux 当前默认删除医疗包，但救援关已标定终点补给范围内的医疗包替换为止痛药；普通起点、终点及沿途医疗包仍删除。肾上腺素替换为止痛药，电击器仍删除；原生止痛药保留，全局不设固定数量上限，止痛药路线密度为 0.3、空间最小间距为 500，地图特例仍沿用既有限额。

资源状态在 `OnMapInit` 及 `round_start_pre_entity` 的 Pre 阶段重置，先使旧回调失效，再由引擎重建实体。初始化等待配置就绪及 `round_start_post_nav` 的 Post 通知，再于下一帧统一执行替换、筛选和记录／恢复；不在 `round_start` Post 或 `OnMapStart` 清除已收到的导演通知。换图及回合重开共用此流程，加载或重载插件后须刷图，不补跑当前回合。

枪械保留地图原始候选池和导演的成组选择，生成后再按 `rules` 将步枪换成冲锋枪、连喷换成单喷、狙击换成鸟狙。固定枪点和运行时生成的枪械也走生成后替换；不增加枪点，不提前混改同组枪点的武器等级。原 `weapon_selections` 生成前改写已移除，区域规则使用具体武器名称。

## 配置覆盖

**插件 `global` < 插件 `maps/<地图名>`**，逐字段覆盖，其余字段继承。资源插件 2.2.0 的策略文件不再使用 `ItemLimits`，单资源数量上限统一写入 `distribution/<资源名>/limit`。全局 7 项限额和 45 张地图的既有限额迁入同一结构，数值不变；配置文件模式不再读取 MapInfo 的 `ItemLimits` 或 `pillflow_min/max/separation`。MapInfo 仍提供安全区等地图信息，Zone 系列的框架资源模式继续使用原有 MapInfo 限额。

## 怎么填写

通用设置写在 `global`：`melee_pickups`、替换规则和资源限制都放在这一层。某张地图需要调整时，在 `maps` 下用地图名建立一块，填写要覆盖的字段。

下面是一份展示各层级写法的完整示例，数量与区间数值仅用于演示；示例中的密度与空间间距为 0，用于演示关闭写法；实际止痛药配置为 0.3 与 500：

```text
"ResourceRules"
{
    "global"
    {
        // 替换或删除地图物品
        "rules"
        {
            "first_aid_kit" "none"             // 默认删除医疗包
            "adrenaline"    "pain_pills"       // 针也换药
            "defibrillator" "none"             // 删除电击器
            "rifle"         "smg,smg_silenced" // 两种目标各一半概率
        }

        // 全局近战拾取次数
        "melee_pickups" "1"

        // 仅救援关的既有终点补给范围内，医疗包换药
        "regions"
        {
            "start" {}
            "along" {}
            "end"   {}
            "finale" { "first_aid_kit" "pain_pills" }
        }

        // 单资源数量、路线分布及统计区域统一填写
        "distribution"
        {
            "pain_pills"
            {
                "limit"        "8"
                "flow_min"     "0.1"           // 从路线 10% 起
                "flow_max"     "0.9"           // 到路线 90% 止
                "flow_density" "0"             // 每 1000 导航 flow 单位的数量，0 关闭
                "min_distance" "0"             // 三维直线最小距离，0 关闭
                "flow_finale"  "0"             // 救援关只执行固定数量与空间限制
                "regions"      "along,unknown" // 仅限制这些点，但其他区域的药也不归分类
            }
            "ammo" { "limit" "3" }
        }

        // 自定义分类：仅接管没有单资源策略的成员，共用数量上限和分布参数
        "categories"
        {
            "recovery"
            {
                "members" "pain_pills,adrenaline,first_aid_kit,defibrillator"
                "limit"   "10"
                "regions" "start,end,along,unknown"
            }
            "throwables"
            {
                "members"      "molotov,pipe_bomb,vomitjar"
                "limit"        "4"
                "flow_density" "0"
                "min_distance" "0"
            }
        }
    }
    "maps"
    {
        "c1m1_hotel"
        {
            // 在同一 distribution 块内覆盖数量和分布，其余字段继承
            "distribution"
            {
                "pain_pills"
                {
                    "limit"        "6"    // 旅馆药上限改为 6
                    "flow_density" "0"    // 暂不启用密度
                    "min_distance" "0"    // 暂不启用空间间距
                }
            }
            "categories"
            {
                "recovery" { "limit" "8" } // 医疗类总上限改为 8，继承成员列表
            }
        }
    }
}
```

例中，止痛药有单资源策略，即使列在 `recovery/members` 中，也不计入该分类。旅馆最终使用药上限 6，密度与空间间距关闭；`recovery` 的共享上限 8 只约束没有单资源策略的其他成员，均按替换后的最终资源统计。其余字段继承，`melee_pickups` 也支持同样的地图覆盖写法。

## 救援补给替换例外

`regions/finale` 仅在“当前地图是救援终章”且资源已识别为 `end` 时生效。按资源名依次查询 `finale → end → global/rules`，某层未指定才回退；普通起点、终点和沿途仍使用原有区域规则。默认只在 `finale` 指定 `first_aid_kit → pain_pills`，其余区域继承全局 `first_aid_kit → none`，不会把普通终点医疗包改成药。

这里复用现有 MapInfo 的 `end_point/end_dist` 终点补给范围，沿用 `SAFEDETECT` 的 MapInfo 优先、数据缺失时精确盒子后备。它不是整张救援地图，也不根据机关实体、按钮或脚本猜测救援范围；起点识别仍优先，不额外逐图补刷资源。

`finale` 只是替换规则例外，不新增分布区域。替换后的药在数量、密度、空间间距及分类筛选中仍属于 `end`；默认 `regions "along,unknown"` 因而不限制这些点。要将其纳入限制需显式包含 `end`；`flow_finale` 只控制救援关的密度与路线区间筛选，不控制医疗包替换。

## 单资源与分类的归属

归属按 `global` 与当前地图逐字段合并后的策略确定，不按实体是否落在某个范围内临时选择：

- 有单资源策略时，整个资源退出所有分类。即使某个刷新点位于该策略的 `regions` 或路线范围之外，也不会交回分类处理；这些点仍按单资源策略本身的范围规则处理。
- `limit "-1"` 配合默认路线与空间参数是明确的不限量策略，同样屏蔽分类，不表示“没有单资源策略”。地图中只覆盖 `limit` 不会清除继承的 `flow_*` 或 `min_distance`，恢复默认参数须显式覆盖相应字段。
- 单资源块必须含至少一个已知参数：`limit`、`flow_min`、`flow_max`、`flow_density`、`min_distance`、`flow_finale` 或 `regions`。空块或仅含未知参数的块报错，不能靠空块意外取得分类豁免。
- 没有单资源策略时，同一资源被多个分类接管会报错，与分类声明顺序无关，即使各分类范围不同也不能多重接管。同一分类内重复列出成员无需报错；已由单资源策略接管的资源不参与分类冲突判断。

分类仍可用共享 `limit`、`flow_*`、`min_distance` 和 `regions` 管理其余成员，但不会再叠加到单资源策略上。若希望某资源交由分类管理，需移除其单资源策略；地图层省略字段仍会继承全局策略。

## 字段取值速查

| 字段 | 用途 |
| --- | --- |
| `rules` | 物品替换：`none` 删除，自身名称保留，逗号分隔的目标列表等概率抽取。 |
| `melee_pickups` | 近战刷新点拾取次数，默认 1。 |
| `regions/start,end,along,finale` | 区域替换特例；`finale` 仅覆盖救援终章的 `end` 范围，未指定资源依次回退到 `end` 与通用规则。 |
| `distribution/<资源名>/limit` | 固定数量上限，默认 `-1`；`-1` 不设固定上限，`0` 清除，正整数封顶；仍受启用的密度预算约束。 |
| `distribution/<资源名>` | 单资源策略，统一设置数量、路线分布及统计区域；存在有效策略即排除该资源的分类接管。 |
| `categories/<分类名>` | `members` 填逗号分隔的资源名，`limit` 设置未被单资源策略接管成员的合计上限；地图层的成员列表整体覆盖。 |

以下分布字段写在单资源策略内，也可直接写在分类内；分类的共享 `limit` 同样以 `-1` 表示不设固定上限：

| 字段 | 含义与默认值 |
| --- | --- |
| `flow_min / flow_max` | 路线进度区间，取值 0..1，默认 0 / 1。 |
| `flow_density` | 每 1000 导航 flow 长度的资源数量，非负数，默认 0（关闭）。 |
| `min_distance` | 保留点之间的三维直线最小距离，单位为 Source 单位，非负数，默认 0（关闭）。 |
| `flow_finale` | 救援关是否执行密度预算和路线区间筛选，默认 0；固定 `limit` 与空间间距仍生效。 |
| `regions` | 数量和分布的统计区域，可选 `start,end,along,unknown`，默认 `along,unknown`。 |

数量按地面实体／刷新点计数。限制适用于医疗资源、投掷物、武器、弹药堆及插件已识别的机关物品；标准灌油任务刷新器（`weapon_scavenge_item_spawn`）和任务油桶（油桶模型、`m_nSkin = 1`）不进入补给删除、替换与裁剪，兼容投票放行的资源也豁免。当前保留原有限额数值；全局 7 项单资源策略均显式设置 `limit "-1"`，地图限额覆盖相应资源的 `limit`。`recovery`、`throwables` 分类的上限均为 `-1`，已有单资源策略的成员不再纳入分类。

## 密度、空间间距与本轮保留点

`flow_density > 0` 时，密度预算按整图最大导航 flow 长度及配置区间计算，向下取整：

```text
density_budget = floor(maxflow * (flow_max - flow_min) * flow_density / 1000)
```

这里的长度不是候选点之间的距离或三维直线距离。`limit >= 0` 时，最终数量预算取固定上限与有效密度预算的较小值；`limit -1` 仅取消固定上限，不取消密度预算。密度关闭或本轮不可用时只使用固定上限，两者都没有则不设数量上限。预算为 0 可以不保留任何点，不保证至少一个；候选不足或间距不满足时也不补生成资源。

有数量预算时，沿有效路线区间设置均匀目标，按从中心向两边的顺序选点，候选同优先级时使用本轮固定的随机顺序。没有数量上限时遍历候选并按空间间距筛选，不套用数量目标。`min_distance` 检查候选与该策略所有已保留点的三维直线距离，不只检查 flow 相邻点；分类成员共用预算与间距约束。

`flow_finale 0` 时，救援关不执行密度预算或路线区间筛选，仍执行固定 `limit` 和空间间距。整图 `maxflow` 无效或候选全部没有有效 flow 时，也停用密度与区间筛选，每轮每个策略只告警一次，固定数量和空间约束保留。仅部分候选缺少 flow 时，先选有 flow 的合格点，再用无 flow 点填充剩余空位；无 flow 点仍消耗同一数量预算并接受同样的距离检查。

同轮已经保留的地面点是后续筛选的固定约束，新生成资源只能填补空位，不重新抽换已有点；重开重新计算。玩家库存不占地面额度。ItemTracking 重放尊重已有保留点，不因重放重新随机裁剪；补空位只从已有候选或实际新生成资源中选择，不主动补刷。

2.2.0 的策略文件使用 `flow_density` 与 `min_distance` 替代 `flow_spacing`；当前止痛药配置为 `flow_density 0.3`、`min_distance 500`，路线区间保持 0–1，地图既有限额不变。Zone 框架原有的 `flow_spacing` 机制不变。

## ConVar

- `resource_rules_file`：相对 SourceMod `configs` 的文件路径；默认空字符串，使用框架原有资源设置。各模式插件加载清单显式选择空字符串或 `resource_rules.cfg`，在地图生成前确定配置来源。
- `resource_rules_visualize`：`0` 正常执行，`1` 预览数量／分布裁剪，`2` 执行并高亮保留点。预览时物品替换照常执行。

原 `resource_pills_flow_*` 参数迁入配置文件。修改配置后换图生效。
