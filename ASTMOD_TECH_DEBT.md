# AstMod / AstRedux 技术债与验证 Backlog

这份清单记录 AstMod Baseline 的存量风险、AstRedux 后续重构对象，以及尚未闭环的 runtime 验证。它不是“发现什么都算技术债”的扫描报告；已经确认的框架约束、可选文件和部署备注会与真正待修的代码问题分开。

## 阅读约定

- 基准 commit：`f304ae60`（`fix: harden AstRedux profile integrations`）。
- 仓库根：`E:\l4d2_configs_merge\repos\L4D2-Amethyst-Rework\`，下文相对路径均相对于该目录。
- 证据尽量写成“文件 + 可 grep 片段”，行号会随提交漂移，以片段为准。
- 状态分为：`待实现`、`待验证`、`长期约束`、`部署备注`、`已解决`。
- `PLUGIN_SOURCE_INVENTORY.md` 是插件二进制与源码关系的唯一详细清单；本文件只记录这类不确定性对维护工作的影响，不重复整份 inventory。

## 当前优先级

### P1. 验证并调校 AstRedux 的 plugin 版波次刷特

- 状态：职责迁移已实现，待真人 gameplay 验证与调参。
- 现状：AstRedux 已根据作者仓库 `c0d829f` 引入独立 `wave_spawner.smx`；AstMod Baseline 继续保留 2.7.1 VScript 实现，因为 2.7.1 与 2.8.1 runtime tar 包都没有提供历史配置引用的二进制。
- 作者信息：海洋明确建议使用 plugin 版，理由是 VScript 版性能差、容易出现特感逐只单上；plugin 版从第一只特感死亡开始计算下一波，计时结束后统一恢复波次。作者同时说明 plugin 版必须配合 2.8.1 VScript，且整体难度可能提高，刷新时间尚未细调。
- 代码证据：AstMod scriptings 的 `c0d829f`（“新版刷特改为插件实现”）新增 `wave_spawner.sp`，并从 `challenge.sp` 移除新版波次 ConVar、`sm_si` 和投票结果处理；2.8.1 `amethyst.nut` 则停用原来的 VScript 波次执行逻辑。
- 已完成：Redux build 的 Challenge 不再创建 `ast_wave_spawn`、`ast_sitimer_new`、`ast_silimit_new` 或注册 `sm_si`；Wave Spawner 独占这些接口，Redux VScript 移除波次执行状态，Profile Controller 继续写入声明式波次参数，`/tz` 仍保留新旧刷特切换。
- 处理边界：迁移只进入 AstRedux，AstMod Baseline 不变。编译、静态职责校验、WSL2 冷加载、4P/1P 参数切换、波次开关、管理员强制刷新和 AstMod 往返卸载/重载均已完成；剩余工作是真人验证整波刷新、`!si` 投票和不同 profile 下的实际节奏。

### P2. 完成 AstRedux 的真人 gameplay 验证

- 状态：待验证。
- 已验证：四份 Redux 专属插件可编译、模式可在 WSL2 冷加载、1P–4P profile 可强制应用；`/tz` 与 `!si` 的 Redux reload 路径已静态校验，plugin 版波次开关、管理员强制刷新和模式往返已完成控制台 smoke test。
- 仍缺：真人加入/退出后的自动切档、混合“被控 + 倒地”的 AutoWipe、全员倒地交还原版灭团、Tank 存量边界、完整章节与终章、游戏内投票菜单。
- 判定标准：不能用冷加载和 cvar 查询替代玩家流程验证；详细 checklist 见 `ASTMOD_INTEGRATION.md`。

### P3. 锁定 `versus_coop_mode.smx` 的真实上游与行为边界

- 状态：待验证。
- 现状：当前二进制与 AstMod 2.7.1 原包一致；本地曾按文件名把 `versus2coop.sp` 视为可能对应的源码。
- 作者信息：海洋给出的上游线索是 `umlka/l4d2/versus_coop_mode`。
- 影响：这是“章节内借 Versus 特性、回合结束切回 Coop 以推进战役”的核心插件，来源不清会阻碍 Redux 最终审查 Versus-backed 规则。
- 下一步：锁定 `umlka/l4d2` 的具体提交，和当前二进制、`versus2coop.sp` 做行为级对照。作者指定的上游线索不等于已经证明当前 SMX 的准确构建输入。

### P4. 确认 `hostname.smx` 是否应从三个 Ast 系模式移除

- 状态：待验证。
- 现状：`astmod`、`astredux`、`astflex` 都从 `plugins_2.cfg` 加载 `optional/astmod/hostname.smx`。
- 作者信息：海洋明确认为它和 Zonemod / Rework 的 hostname 处理冲突，不需要保留。
- 影响：可能和 `hostname`、ReadyUp 显示或其他 server-namer 逻辑竞争。
- 下一步：在 AstMod 与 Zonemod 各加载一次，记录 `hostname` 及相关 ConVar 的 owner 和切换结果；确认后从三个模式的加载清单移除，但保留二进制来源记录。

### P5. 运行时确认 `Smoker_escape_range`

- 状态：待验证。
- 现状：`cfg/cfgogl/{astmod,astflex,astredux}/shared_cvars.cfg` 都包含 `confogl_addcvar Smoker_escape_range 700`；源码、VScript、公开参考仓库和可直接搜索的二进制内容中均未找到创建或读取该 ConVar 的证据，紧邻的引擎 ConVar `tongue_range 700` 才明确生效。
- 风险：Confogl 会把未知 ConVar 放入 pending，最终找不到时静默跳过，因此拼写错误不会自动出现在日志里。
- 证据边界：静态扫描无法排除游戏内部或只有二进制的插件创建该 ConVar，不能直接写成“确认不存在”。
- 下一步：加载 AstMod 后在 server console 查询该 ConVar；若仍不存在，再从三份 cfg 删除并加一条针对性的静态校验。

## 插件来源与构建链

### S1. `optional/astmod/` 不能完整从仓库源码重建

- 状态：长期约束。
- 当前事实：详细数量、加载状态、AstMod 2.7.1 哈希和可能对应的 `.sp` 见 `PLUGIN_SOURCE_INVENTORY.md`。仓库不能声称所有 bundled SMX 都有源码，也不能声称同名 `.sp` 已被证明是当前二进制的构建输入。
- 作者信息：海洋认为多数仅二进制插件不需要修改，并建议必要时使用 Lysis 反编译；对五个存在多个可能源码的插件，今后维护应优先采用他的 AstMod scriptings 仓库版本。
- 处理原则：Lysis 只用于行为审计，反编译输出不等于可维护原始源码。先判断 Redux 是否仍需要某插件，再优先审计“当前加载、行为关键、没有替代”的二进制，不批量反编译全部文件。
- 可复现要求：若要把“找到可能对应的 `.sp`”升级为“已确认构建来源”，至少记录源码哈希、编译器、include、编译参数与产物哈希；作者指定的维护来源和旧二进制的精确构建来源是两个不同问题。

### S2. 旧 DAS 二进制与公开参考源码版本不一致

- 状态：长期约束（AstMod/AstFlex）；Redux 已脱离。
- 证据：运行时生成的 `cfg/sourcemod/difficulty_adjustment_system/*.cfg` 标注 `v12.0`，当前公开参考源码定义 `DAS_VERSION "14.0 + 1.0"`。
- 影响：不能用当前参考源码完整断言 AstMod 2.7.1 DAS 二进制行为。
- 处理原则：AstMod Baseline 暂时保留旧 DAS；Redux 不回流 DAS，只以声明式 profile 和 adapter 重建需要的行为。

### S3. `l4d2_weapon_attributes` 新旧接口语义不同

- 状态：长期约束（AstMod/AstFlex）；Redux 已规避 Tank 近战倍率链。
- 现状：本仓库运行时使用 Competitive Rework 的新版 `optional/l4d2_weapon_attributes.smx`。旧 AstMod 命令 `sm_melee` 已不存在，旧 DAS 的 `sm_weapon melee tankdamagemult` 也不会匹配新版按具体近战脚本名处理的伤害键。
- 影响：旧 DAS cfg 中该命令可能静默无效；Redux 已通过 profile 的 `melee_damage=300` 和自己的 damage adapter 单点表达目标值。
- 处理原则：AstMod 保留为历史 Baseline 时诚实记录该偏差；不要重新叠加第二套 Tank 近战 hook。全局 `fixes/l4d2_melee_damage_control.smx` 仍由 `generalfixes.cfg` 加载，因此 Redux 必须保留 `l4d2_melee_damage_tank_nerf 0` 来关闭它的 Tank nerf。

### S4. 无源码插件的处理边界

- 状态：长期约束。
- `clip_removal.smx`：用途仍未确认，保持文件存在但默认不加载。
- 海洋对其余仅二进制插件的用途与去留说明应记录在 `PLUGIN_SOURCE_INVENTORY.md`，并区分确定信息与“大概、可能、不知道”等不确定判断。
- 未加载的 optional 插件不自动等于死文件；Competitive Rework 本来就发布按模式选用的插件池。只对 Ast 系模式实际加载集合做依赖和冲突判断。

## 已确认的架构约束

### C1. AstRedux 当前仍是 Versus-backed 实验容器

- 状态：长期约束。
- `assets/astmod_vpk/scripts/gamemodes.txt` 中 `astredux` 的 base 仍是 `versus`。当前工作只是把规则显式化和逐步解耦，不代表 Coop-native 已完成。
- `astredux_tank_engine_scale=1.5` 明确承载当前 Versus Tank 血量乘区。将来尝试 Coop-native 时必须重新测量并修改该值，不能未经验证就假定一定为 `1.0`。

### C2. 人数 profile 统计“仍在生还者队伍中的真人”

- 状态：长期约束。
- 玩家死亡但没有退出仍计入原人数档；退出、离队或进入 kick queue 后才降档。死亡是游戏过程，不应自动降低难度。
- 新 profile 立即影响后续规则，但不追溯扣改已经生成的 Tank，也不因人数变化突然删除已经生成的 Witch。

### C3. Profile Controller 必须晚于其 profile 依赖加载

- 状态：长期约束。
- Controller 应用 profile 时会校验声明的每个 ConVar 已存在；因此它当前位于 `plugins_3.cfg` 末尾是有意的。
- Challenge 与 AutoWipe 对 Redux ConVar 使用运行时查找，不需要为了表面上的依赖顺序把 Controller 提前。若新增 profile-owned 插件，必须保证它先创建 ConVar。

### C4. 三段 plugin cfg 是当前 command buffer 保护措施

- 状态：长期约束。
- 单一 `confogl_plugins.cfg` 曾因命令量过大导致后续加载命令静默丢失，因此拆成 `plugins_1/2/3.cfg`。
- 这不是当前需要消灭的债务。调整分段或顺序必须有 runtime 证据；除非以后实际插件数量显著收敛，不引入抽象 loader 或“插件元数据”方案。

### C5. Competitive Rework 继续拥有模式生命周期

- 状态：长期约束。
- 自定义模式 cfg 不得加入 `sm plugins load_unlock`、`unload_all`、`load_lock` 或 `refresh`。AstMod/AstFlex 的旧 DAS 生成 cfg 仍含临时解锁逻辑，这是 Baseline 遗留；Redux 已改为常驻 adapter + ConVar 开关，不得回退。
- `confogl_addcvar` 对未知 ConVar 静默 pending 是上游框架行为；本项目优先用针对性静态检查与 runtime cvar 查询发现问题，不广泛修改 Rework 核心。

## 后续取舍

### D1. `server.smx`、空服换图与 `sv_crash`

- 状态：待验证。
- 海洋认为 `sv_crash` 有实际运维价值，因为部分卡顿无法通过重载插件解决。
- 若保留，应确认管理员权限边界，并在未来 VPS/Docker 部署中配合 systemd、Docker restart policy 或其他 supervisor；主动 crash 不是独立的恢复方案。

### D2. AstRedux 仍复用 AstMod 大插件池

- 状态：待实现（低优先级、渐进处理）。
- Redux 目前只替换 DAS、Challenge、AutoWipe 和 Profile Controller，其余多数插件仍从 `optional/astmod/` 加载。
- 不为了“整洁”批量删除或复制插件。以实际玩法需求、作者来源信息和 runtime 依赖为依据，逐项决定保留、替换或淘汰。

## 部署备注（不作为 Redux gameplay 技术债）

- 当前桌面测试环境是 WSL2 Ubuntu 22.04，已经完成多轮冷加载和 smoke test。海洋偏好 Docker，主要价值是发布前快速获得干净 server 和可重复部署；Docker 的文件映射、UDP 网络和持久化仍需单独设计，不阻塞当前 Redux 开发。
- 租用 Ubuntu VPS 仍是未来计划，裸机与 Docker 都可评估。
- SteamCMD 匿名下载 App 222860 Linux depot 曾出现 `Invalid platform`，现有文档记录了先下载 Windows 平台再补 Linux 的 workaround。该行为可能随 Steam 后端变化，新环境部署时应重新验证。

## 已解决（Redux 重构基线）

- `89e63ebd`：用 `astredux_profiles.cfg`、Profile Controller 和常驻 adapter 替换旧 DAS；Tank 最终血量和固定近战伤害改为直接声明值。
- `f304ae60`：Redux `/tz` 与 `!si` 修改后显式 reload VScript；旧刷特路径改读 `astredux_si_*`；移除 `ast_humantankhp` 休眠耦合与 `confogl_current_config` legacy；加固 AutoWipe 快照边界。
- `l4d2_melee_damage_tank_nerf 0` 不是死配置：全局 `generalfixes.cfg` 会加载 `fixes/l4d2_melee_damage_control.smx`，Redux 用该值关闭全局 Tank 近战 nerf，避免覆盖自己的 300 伤害规则。
- AutoWipe 的 5 秒路径不是死分支：它处理“部分被控、部分倒地但仍有活人”的混合无法行动状态；全员倒地继续交给游戏原生灭团。
