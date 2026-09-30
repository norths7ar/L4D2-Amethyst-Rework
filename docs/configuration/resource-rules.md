# 资源规则

`optional/resource_rules.smx` 统一承载武器替换、安全室物资处理和资源策略。Zone 系列继续使用原有 `l4d2_addweaponrule`、`confogl_*`、`sm_safeitemkill_*` 设置及 Stripper；AstRedux 使用 `addons/sourcemod/configs/resource_rules.cfg`。下文的策略文件格式适用于后者。

## 半场一致性

复用 Confogl 的 ItemTracking，而非另写一套保存机制。Zone 系列在替换和安全室清理后，由 ItemTracking 执行原数量／路程筛选，再保存和重建药丸、针及三种投掷物；原有 MapInfo 覆盖和人数限额保持不变。武器生成仍使用原生生成器及各模式原有固定替换规则。

AstRedux 的数量／分布仍由策略文件负责，ItemTracking 只提供可选的结果保存／重建，不再套用旧限额。`confogl_enable_itemtracking 1` 启用这一接口；`confogl_itemtracking_savespawns 0` 保持每轮重新选择，设为 `1` 则复用已保存的上述五类补给。新地图清除记录。重建时不重复执行资源替换和随机裁剪。

随机补给按地图候选池抽取，再执行删除或替换，最后按替换后的物品裁剪数量和分布。先执行单物品限制，再按分类首次声明顺序执行分类限制；重叠分类依次处理剩余物品。

## 配置覆盖

**插件 `global` < MapInfo < 插件 `maps/<地图名>`**，逐字段覆盖，其余字段继承。MapInfo 提供 `ItemLimits` 和止痛药的 `pillflow_min/max/separation`，地图专属调整写在插件的 `maps` 中。

## 怎么填写

通用设置写在 `global`：`melee_pickups`、`weapon_selections`、替换规则和资源限制都放在这一层。某张地图需要调整时，在 `maps` 下用地图名建立一块，填写要覆盖的字段。

下面是一份展示各层级写法的完整示例，数值用于演示：

```text
"ResourceRules"
{
    "global"
    {
        // 替换或删除地图物品
        "rules"
        {
            "first_aid_kit" "pain_pills"       // 医疗包换药
            "adrenaline"    "pain_pills"       // 针也换药
            "defibrillator" "none"             // 删除电击器
            "rifle"         "smg,smg_silenced" // 两种目标各一半概率
        }

        // 全局近战拾取次数、枪械刷新类型
        "melee_pickups" "1"
        "weapon_selections"
        {
            "any_primary" "tier1_any" // 任意主武器刷新点 → T1武器刷新点
            "any_rifle"   "any_smg"   // 任意步枪刷新点 → 任意冲锋枪刷新点
        }

        // 区域替换特例：起点保留医疗包，沿途和终点继承通用替换
        "regions"
        {
            "start" { "first_aid_kit" "first_aid_kit" }
            "along" {}
            "end"   {}
        }

        // 单物品数量上限
        "ItemLimits"
        {
            "pain_pills" "8"
            "ammo"       "3"
        }

        // 止痛药的路线分布，以及上述数量上限的统计区域
        "distribution"
        {
            "pain_pills"
            {
                "flow_min"     "0.1"           // 从路线 10% 起
                "flow_max"     "0.9"           // 到路线 90% 止
                "flow_spacing" "0.05"          // 最小间隔为路线的 5%
                "flow_finale"  "0"             // 救援关仅执行数量限制
                "regions"      "along,unknown" // 统计沿途及位置未知的点
            }
        }

        // 自定义分类：成员共用一个数量上限和一套分布参数
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
                "flow_spacing" "0.05"
            }
        }
    }
    "maps"
    {
        "c1m1_hotel"
        {
            "ItemLimits" { "pain_pills" "6" } // 旅馆药上限改为 6
            "distribution"
            {
                "pain_pills" { "flow_spacing" "0.02" } // 药间距改为 2%
            }
            "categories"
            {
                "recovery" { "limit" "8" } // 医疗类总上限改为 8，继承成员列表
            }
        }
    }
}
```

例中，药先接受单物品限制，再与其他医疗物品一起接受 `recovery` 的合计限制。旅馆最终使用药上限 6、药间距 2%、医疗类上限 8，其余字段继承。`melee_pickups`、`weapon_selections` 也支持同样的地图覆盖写法。

## 字段取值速查

| 字段 | 用途 |
| --- | --- |
| `rules` | 物品替换：`none` 删除，自身名称保留，逗号分隔的目标列表等概率抽取。 |
| `weapon_selections` | 收窄地图枪械刷新类型。 |
| `melee_pickups` | 近战刷新点拾取次数，默认 1。 |
| `regions/start,end,along` | 起点、终点、沿途的替换特例，优先于通用规则。 |
| `ItemLimits/<物品名>` | 单物品数量上限；`-1` 无限，`0` 清除，正整数为上限。 |
| `distribution/<物品名>` | 该物品的路线分布及统计区域。 |
| `categories/<分类名>` | `members` 填逗号分隔的物品名，`limit` 设置合计上限；地图层的成员列表整体覆盖。 |

分布字段也可直接写在分类内：

| 字段 | 含义与默认值 |
| --- | --- |
| `flow_min / flow_max` | 路线进度区间，取值 0..1，默认 0 / 1。 |
| `flow_spacing` | 最小路线进度差，默认 0。 |
| `flow_finale` | 救援关启用路线筛选，默认 0。 |
| `regions` | 数量和分布的统计区域，可选 `start,end,along,unknown`，默认 `along,unknown`。 |

数量按地面实体／刷新点计数。限制适用于医疗资源、投掷物、武器、弹药堆及插件已识别的机关物品；兼容投票放行的资源豁免。当前默认沿用章节限额，新增 `recovery`、`throwables` 分类的上限均为 `-1`。

## ConVar

- `resource_rules_file`：相对 SourceMod `configs` 的文件路径；默认空字符串，使用框架原有资源设置。各模式插件加载清单显式选择空字符串或 `resource_rules.cfg`，在地图生成前确定配置来源。
- `resource_rules_visualize`：`0` 正常执行，`1` 预览数量／分布裁剪，`2` 执行并高亮保留点。预览时物品替换照常执行。

原 `resource_pills_flow_*` 参数迁入配置文件。修改配置后换图生效。
