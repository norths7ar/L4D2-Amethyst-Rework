# 特感 AI：行为与设计取舍

AstRedux 的特感增强以补足接敌、攻击选择和地形处理的弱点为主，保留玩家提前处理、走位和互救的空间。主动退避与寻路卡住采用不同处理；接管结束后要及时交回原生 AI，避免增强插件反而阻塞攻击和绕障。

## 实现与配置入口

[AI_HardSI](../../addons/sourcemod/scripting/optional/coop/AI_HardSI.sp) 将普通特感的职业模块编入同一插件；Tank 已拆为独立控制器，见 [Tank AI](tank-ai.md)。Witch 的管理、生成与统计由独立组件处理。

共同选人、防退避、脱困分别由 `si_targeting`、`si_anti_retreat`、`si_unstuck` 负责。波次系统管理阵容和出生节奏，`profile_controller` 应用人数档位。职业行为与人数平衡分别维护，让 AI 调整和武器反制可以独立变化。

当前参数查[模式基线](../../cfg/cfgogl/astredux/shared_cvars.cfg)、[模式设置](../../cfg/cfgogl/astredux/astredux.cfg)和[人数 profiles](../../addons/sourcemod/configs/astredux_profiles.cfg)。加载关系查 [plugins_2.cfg](../../cfg/cfgogl/astredux/plugins_2.cfg)及全局 [generalfixes.cfg](../../cfg/generalfixes.cfg)。

## 职业设计中的重要取舍

### Hunter：行为增强与伤害反制分开维护

Hunter 积极接近并快速连续起扑，被正面盯防且尚未贴近时会加入随机侧向角度和低扑；起扑仍受蹲地、视线、冷却及被推状态约束。

Hunter AI 曾写入和复原空爆伤害门槛，导致行为插件介入模式平衡。`32ba705b` 将门槛交还模式配置，使飞扑行为和武器伤害可以独立调整。

[l4d_pounceprotect](../../addons/sourcemod/scripting/optional/l4d_pounceprotect.sp) 处理的是飞扑结束后仍短暂残留的伤害打断预算：它可能使 Hunter 受伤粘地，妨碍再次起扑和蹬墙。修复清除飞扑结束后的意外阻塞，保留正在飞扑时的空爆判定。

### Jockey：推击应延缓进攻，但不能永久锁住跳跃

Jockey 在技能跳之间穿插普通跳，少量情况下继续步行，形成不同接近节奏；骑乘和爬梯移动交回引擎。

旧逻辑要求自然跳跃来解除被推标志，却又在标志存在时禁止跳跃，形成互锁。`f987c567` 改为等待真实踉跄和推击延迟结束，并从最后一次推击重新计时，保留连续推击的打断效果。跳跃节奏也改为在技能实际发动后推进，避免未成功发动的动作消耗节奏。

低人数档增加霰弹枪空爆反制，是人数平衡决定；具体血量和门槛由 profiles 维护，不由职业跳跃逻辑决定。

### Charger：统一目标和起手时机，避免多个修正互相打架

Charger 健康且远离目标时暂缓冲锋，接近或血量下降后放开。

早期用近身目标覆盖解决“追远处而忽略身边”的问题，后来发现胆汁特殊保留是多个职业的共同因素，便撤去 Charger 独有覆盖，改由 `si_targeting` 处理（`495295f0`）。技能可用时优先寻找未控目标仍留在职业模块，减少无效叠控。

近距离反跑和突然转冲的另一来源是目标不一致：准星扫到的人未必是 AI 实际追击者。`658241b1` 统一追击、移动和瞄准所用目标；移动纠正仅用于通路清楚的近处场景，绕障仍交给原生导航。随后 `5fe13be5` 将瞄准前移到引擎消费攻击输入之前，并清除起手残留移动输入，避免技能已经启动才改朝向。

这些处理不替代原生冲锋、搬运和砸地。控制状态修复以及真人被 BOT 接替后的追踪冲锋，仍分别由 `l4d2_charge_target_fix`、`blockheatseekingchargers` 负责。

### Smoker：近身进攻与人数差异

Smoker 近身时主动攻击和近战；舌头冷却期间的退避另由防退避模块处理，舌头恢复后交回原生攻击站位。

Smoker 模块内重写断舌门槛和出舌延迟的旧代码已停用，当前规则归模式与人数配置。模式登记基线、profiles 应用最终值，是为了避免切换人数后残留上一档的拖拽时序；共享实现见 [l4d2_smoker_drag_damage_interval](../../addons/sourcemod/scripting/optional/l4d2_smoker_drag_damage_interval.sp)。

单人击杀自救窗口由 [si_damage_control](../../addons/sourcemod/scripting/optional/coop/si_damage_control.sp) 管理，从出舌时开始计时，抓住玩家不会重新延长。

### Spitter：先利用已有控制，不接管原生射弹

Spitter 原本是空模块，`17476250` 增加配控选人。采用的顺序为 Charger → Hunter → Smoker → Jockey，同类选最近者，Charger 只计砸地。

职业模块负责选择已有的控制机会，攻击站位和射弹轨迹仍由原生 AI 决定。口水伤害节奏、扩散和死亡口水由配套插件维护；补充节点特效只是帮助辨认，不改变伤害算法，也不是精确伤害边界。

### Boomer：减轻接近压力，保留喷吐威胁

早期实现按攻击键就向范围内可见生还者施加胆汁，并自行恢复被推后的喷吐机会。`2588b505` 参考 Anne 改用引擎真实喷吐状态与冷却：首次中喷后才建立转向队列，补中仍须满足正在喷吐、未踉跄及距离、角度、遮挡条件。这把转头威胁约束在一次真实喷吐中。

双人反馈随后指出，高速、高飞的胖子迫使玩家仰头追枪，压缩处理正面控制特感和互救的空间。移除胖子会减少阵容变化，完全关闭连跳又失去其接近手段；关闭转头只影响首次中喷后的扩散，落地禁喷则削弱已经接近后的攻击，都没有解决首次接敌的反应窗口。

因此先采用双人水平限速与独立垂直速度（`a4fbbebf`），后来改为各人数共用起跳算法，只用一个倍率调整接近强度。这样三人也能折中，不必维护独立算法和额外上限；喷吐、转向及中喷尸潮不随这项调整改变。

速度缩放在引擎完成起跳后对三轴应用一次，避免垂直速度被原生跳跃覆盖。喷吐期间停止连跳，让喷吐动作正常完成。实现见 [AI_Boomer.sp](../../addons/sourcemod/scripting/optional/coop/AI_HardSI/AI_Boomer.sp)，倍率归 profiles。

## 共同选人与移动控制

### 胆汁选人

[si_targeting](../../addons/sourcemod/scripting/optional/coop/si_targeting.sp) 去掉普通特感和 Tank 对中喷目标的特殊保留，让它们可以利用其他攻击机会；并不取消胆汁吸引普通感染者的作用，也不替代 Spitter 配控和 Charger 未控目标策略。

它使用已核验的 32 位 Linux 服务端指令补丁。更换平台或引擎构建时，必须重新核验 [gamedata](../../addons/sourcemod/gamedata/si_targeting.txt)。

### 防退避与脱困

[si_anti_retreat](../../addons/sourcemod/scripting/optional/coop/si_anti_retreat.sp) 只短暂替换已确认的 `ChargerEvade` 和舌头冷却中的 `SmokerRetreatToCover`，不按普通后退输入统一拦截。后退也可能是绕障和准备攻击的一部分；追击接管必须让位于技能、控人和原生站位判断。

[si_unstuck](../../addons/sourcemod/scripting/optional/si_unstuck.sp) 从直接隐藏重定位演变为先尝试恢复原生寻路。移动现有实体而不重生，可以保留血量、冷却和波次计数；普通特感原位置也须隐藏，以保留玩家观察、处理目标的连续性。Tank 允许从可见卡位救出，见其独立规则。

仅看方向按键曾漏掉通过速度移动、无输入但有追击动作，以及局部往返不前的情况。检测逐步覆盖这些状态，同时保留有路可走的正常待机，并按 Hunter 当前蹲姿判断嵌入，避免误判低顶下的合法蹲伏。防退避与脱困需协调临时移动控制，否则恢复的路线会被前一个追击命令覆盖。

主动候战仍是后续设计方向。若引入有意等待，需要与防退避、脱困协调，避免它们提前打断候战；具体方向见 [ROADMAP](../ROADMAP.md)。
