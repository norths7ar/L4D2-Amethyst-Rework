# L4D2 AstMod Rework

这是一个以 [L4D2 Competitive Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) 为框架、以 AstMod 2.7.1 为 PVE 基础的完整服务端配置。仓库保留 Competitive Rework 原有的对抗配置，并把 AstMod 系列做成可以通过 `!match` / `!rmatch` 进入、切换和退出的独立模式。

AstMod 原版由海洋空气维护，公开源码来自 [L4D2-AstMod-Scriptings](https://github.com/Sglight/L4D2-AstMod-Scriptings)。

## 为什么做这个项目

AstMod 的核心魅力并不只是“把数值调难”，而是围绕多人 PVE 形成的一整套药役体验：自定义刷特、特感 AI、资源控制、武器节奏、地图修正和难度投票。另一方面，它借用了 Versus 的若干底层行为，年代较早的插件和配置也会与今天的 Competitive Rework、第三方地图机制产生摩擦。

本项目希望做到：

- 保留 AstMod 有辨识度的玩法，而不是把它稀释成普通战役加几只特感；
- 把不同取向做成互不污染的 matchmode，而不是靠临时改一堆 cvar；
- 优先兼容第三方战役自己的提示、机关、固定 Boss 和脚本；
- 尽量复用 Competitive Rework 的框架、修复和生命周期，不无谓分叉核心代码；
- 所有重要取舍都能在配置、文档或持久化记录里查到，便于复盘和回滚；
- 先把规则底层想清楚，再讨论“减多少难度”，不让休闲版反过来决定基础架构。

## 三个模式的定位

| 模式 | 当前状态 | 定位 |
| --- | --- | --- |
| **AstMod** | 已可在 `!match` 选择 | 维护后的个人 Baseline。保留原版的高压药役方向、自定义刷特和默认开启的 Hard SI；它不是未经修改的 2.7.1 历史镜像。 |
| **AstRedux** | 新 Profile Controller 已运行，当前工作重点 | 并行容器已脱离旧 DAS：人数 profile、Tank 血量与近战、刷特组成、No-Witch 和 AutoWipe 改由 Redux 自己声明和应用。当前底层仍借用 Versus，下一阶段继续审计哪些行为能在 Coop 下可靠重建。 |
| **AstFlex** | 暂停开发，保留实验配置 | 前期减压讨论留下的可用 preview，目前仍依赖 AstMod 的 Versus-backed 底层。等 AstRedux 或其他 Coop-native 方案可行后再重启，并作为该 ruleset 的减压 preset。 |

稳定 Baseline 的运行时 namespace 已统一为 `astmod`。AstRedux 使用独立的 `astredux` matchmode、mutation、cfg、VScript 和 profile controller，同时暂时复用未修改的 AstMod 插件池与 Stripper；`astflex` 只保留已有 preview 配置。

## 当前 Baseline 已经改了什么

当前仓库里的 `AstMod` 已经是维护版 Baseline。完整文件边界、武器同步清单、Stripper 哈希和运行记录见 [ASTMOD_INTEGRATION.md](ASTMOD_INTEGRATION.md)，下面只给定位级概述。

- Competitive Rework 负责框架、扩展、通用修复和模式切换生命周期；AstMod 专属插件隔离在 `plugins/optional/astmod/`，不会在其他模式自动加载。模式进出由 Rework 的 `!match` / `!rmatch` 负责，模式 cfg 遵循框架生命周期，不自行执行 `load_unlock` / `unload_all` / `load_lock`。
- 武器参数随当前 Zonemod 同步（Uzi、消音微冲、木喷、铁喷、确定性霰弹散布），改用支持 `reloadduration` 的插件，并停掉会覆盖已同步换弹参数或缺源/用途不明的旧插件；`clip_removal.smx` 保留为上游文件但默认不加载。具体清单见 ASTMOD_INTEGRATION。
- 57 张官图 Stripper 配置从 Zonemod 同步到 AstMod，第三方地图文件和全局过滤未覆盖；`astmod.nut` 对直接切换 matchmode 时的瞬时 Squirrel 异常加了保护。
- AstFlex 的已有配置保留前期减压试验结果，但当前暂停开发；它仍使用 AstMod 的 Versus-backed 底层，不能视为第三方战役兼容方案。

### 战役投票和第三方地图

AstMod 自带的 ACS 和 `!vote` 仍使用 `addons/sourcemod/configs/cfgs.txt` 作为战役目录。当前改动会检查每个目录项的第一张地图是否真实安装：没有安装的条目不会出现在投票中，安装后无需再改配置即可出现。

这不是完全动态发现。服务器只能从地图 code 知道 `x1m1` 之类的名字，无法可靠推导玩家能看懂的战役标题。后续可能维护一份明确的战役目录，把 VPK/战役名称、首图 code 和展示名关联起来；在那之前，`cfgs.txt` 仍是可审计的白名单和元数据源。

## AstRedux：接下来的主线

AstRedux 首先处理规则底层，而不是先做难度减法。当前 AstMod 通过 `versus_coop_mode.smx` 在章节过程中借用 Versus，在对抗回合结束时切回 Coop，从而同时取得部分对抗特感行为和战役推进能力。这套办法有效，但也带来回合逻辑、第三方地图兼容和自制机制方面的不确定性；部分第三方 VPK 未声明支持 Versus，另一些地图的剧情、Boss 或 Director/VScript 也可能被对抗底层和 AstMod 插件接管。Redux 将作为与 AstMod 并列的 Coop-native 实验 ruleset，而不是 AstMod 的少量增删版。

当前已经完成第一层 scaffold 和第一项独立规则改造：`!match` 中注册 `astredux`，VPK 提供同名 mutation，配置与 VScript 独立；旧 `difficulty_adjustment_system.smx` 不再由 Redux 加载，改由 `astredux_profiles.cfg` 和常驻 Profile Controller 根据 1–4 名真人生还者应用可读的最终规则。AstMod Baseline 仍保留原实现，后续 Coop-native 底层和插件替换可以继续只在 Redux 内验证。

Redux 的第一阶段会逐项回答：

1. 当前实际依赖 Versus 的行为有哪些，哪些只是历史实现选择；
2. 哪些能力能在原生 Coop 下由插件可靠实现，哪些强行重写反而风险更高；
3. 如何保留 AstMod 的刷特、资源和武器身份，同时避免 Versus 回合结算干扰战役；
4. 第三方地图的提示、固定 Tank、自制 Boss、机关和结局脚本能否不受模式底层破坏；
5. 从 AstRedux 派生 AstFlex 时，哪些压力项应当成为可投票开关，哪些属于模式身份。

[CompetitiveWithAnne](https://github.com/fantasylidong/CompetitiveWithAnne) 会作为实现思路参考之一，重点看它如何在插件层接管 Coop/药役行为；不会在没有逐项审计的情况下整体搬入。

### 路程 Tank 的计划

第三方战役可能同时存在地图固定 Tank、插件固定 Tank 和 Director 路程 Tank。初见时叠加并不罕见。计划是在安全门内提供投票，只关闭当前地图的 Director 路程 Tank，并把结果按地图持久化到可读配置中：

- 重开本关后仍然生效；
- 不误杀地图脚本或插件明确安排的固定 Boss；
- 后台可以直接查看哪些地图被人工覆盖，以及是谁/何时做了决定；
- 后续可以删除记录，恢复该地图的默认行为。

具体数据格式和 Tank 来源识别要在 AstRedux 规则审计后确定，目前尚未实现。

## 已验证与待验证

已完成：

- 静态检查 310 条有效插件加载和 57 张官图 Stripper 哈希；
- Ubuntu 22.04 / L4D2 Dedicated Server 的核心插件加载；
- `sm_forcematch astmod`、AstMod/AstFlex 核心 cvar 和插件状态；
- 改名后的 `astmod` mutation、`astmod.nut`、Stripper 和插件 namespace 已在 WSL2 实际加载；`astredux` mutation、独立 VScript、Baseline Stripper 路径和三份 Redux 专属插件也已完成 WSL2 冷加载，确认旧 DAS 未加载；当前 `gamemodes.txt` 在官方文件基础上追加 `astmod`、`astredux` 与历史 `hunter` 三个模式；
- AstRedux 1P–4P profile 已在 WSL2 逐档强制应用，确认最终 Tank 语义血量 `1200/2550/4500/6750`、底层 `z_tank_health`、刷特波次、mob 数量、No-Witch 和 AutoWipe 开关与声明一致；
- 有玩家连接时从 AstMod 直接切到 Zonemod，确认 `versus_coop_mode.smx`、ACS、AstMod AI 和投票插件被清理；
- 与 Zonemod 同步后的微冲、单喷换弹和散布配置不再产生旧插件接口报错。

仍需完成：

- 游戏内完整走一遍 `!match`、`!vote`、`!mapvote`、`/tz` / `!settings`；
- 正常完成章节和终章，验证 ACS 战役切换；
- 有真人连接时验证 AstRedux 随加入/退出自动切换 profile、已生成 Tank 不被追溯改血、新生成 Tank 的最终血量，以及通用 `weapon_melee` 固定 300 伤害；
- 多次执行 AstMod / AstRedux / AstFlex / Zonemod 往返切换；
- 游戏更新后重新比较官方 `gamemodes.txt`，并验证其他同样携带该文件的第三方 addon 是否存在加载顺序冲突；历史 `hunter` 条目后续也可评估是否删除；
- 决定是否保留 `server.smx` 的空服换图和 `sv_crash` 管理命令；
- 找回或明确替代上游配置提到、但运行包和源码包都缺失的 `wave_spawner.smx`。

## 仓库关系

- GitHub `origin`：公开主仓库；
- 私有 Gitea `gitea`：个人备份镜像；
- `upstream-rework`：Competitive Rework 上游，只拉取、不推送；
- `main` 是单人维护主线。接受变更后通常将同一个已签名提交推送到 GitHub 和 Gitea，不为例行个人改动额外制造 PR。

本仓库包含 AstMod 2.7.1 运行包带来的 `.smx`。原始源码包没有覆盖每一个二进制，因此文档会诚实区分“有源码且可重编译”“只有上游二进制”和“本项目修改过的源码”，不会假装能够从当前源码完整复现全部插件。

---

## **Upstream foundation: L4D2 Competitive Rework**

> [!IMPORTANT]
> It is recommended to host servers on Linux, but Windows is supported.  
> When running Linux ensure that your setup is running a minimum of **`GLIBC 2.35`** (Ubuntu 22.04 or higher) or you will run into issues loading certain extensions.  
> This repository only supports Sourcemod **1.12** and up (which comes with the repository for ease of use)

---

> [!NOTE]
> ConVar **`mv_maxplayers`** was added which replaces **`sv_maxplayers`** in **`cfg/server.cfg`**, this is used to prevent it from being overwritten every map change.  
> On config unload, the value will be reset to the value used in the **`cfg/server.cfg`**.

> [!NOTE]
> Every confogl matchmode will now execute 2 additional files; **`cfg/sharedplugins.cfg`** and **`cfg/generalfixes.cfg`**.  
> **`generalfixes.cfg`** contains all the crucial fixes that will be loaded in every matchmode.  
> **`sharedplugins.cfg`** is for you, the server owner. You can load any custom plugin that you want to be loaded in every matchmode here.

> [!CAUTION]
> Plugin load locking and unlocking is no longer handled by the configs themselves, refrain from doing it manually or you can run into issues.

## **About:**

This project started off with a focus on reworking the very outdated platform for competitive L4D2. In its current state it allows anyone to host their own up to date competitive L4D2 servers.

> **Included Matchmodes:**

* **Zonemod 2.9.1b**
* **Zonemod Hunters**
* **Zonemod Retro**
* **NeoMod 0.4a**
* **NextMod 1.0.5**
* **Promod Elite 1.1**
* **Acemod Revamped 1.2**
* **Equilibrium 3.0c**
* **Apex 1.1.2**

---

## **Download & Installation:**

> [!IMPORTANT]
> Pick the archive that matches your **Server OS**:
> * **Linux:** `L4D2-Competitive-Rework-<version>-linux.tar.gz`
> * **Windows:** `L4D2-Competitive-Rework-<version>-windows.zip`

1. Download the latest archive from the [**Releases**](../../releases/latest) page.
2. Extract it directly into your server's **`left4dead2/`** directory.
3. For first-time server setup on dedicated servers, the [Dedicated Server Install Guide](Dedicated%20Server%20Install%20Guide/README.md) might be of use to you!

> [!NOTE]
> Releases only include what the servers need, **no** SourcePawn sources or compiler.  
> To modify or recompile plugins, clone the repository instead.

---

## **Credits:**

> **Foundation/Advanced Work:**

* A1m`
* AlliedModders LLC.
* "Confogl Team"
* Dr!fter
* Forgetest
* Jahze
* Lux
* Prodigysim
* Silvers
* XutaxKamay
* Visor

> **Additional Plugins/Extensions:**

* Accelerator74
* Arti
* AtomicStryker
* Backwards
* BHaType
* Blade
* Buster
* Canadarox
* CircleSquared
* Darkid
* DarkNoghri
* Dcx
* Devilesk
* Die Teetasse
* Disawar1
* Don
* Dragokas
* Dr. Gregory House
* Epilimic
* Estoopi
* Griffin
* Harry Potter
* Jacob
* Luckylock
* Madcap
* Mr. Zero
* Nielsen
* Powerlord
* Rena
* Sheo
* Sir
* Spoon
* Stabby
* Step
* Tabun
* Target
* TheTrick
* V10
* Vintik
* VoiDeD
* xoxo
* $atanic $pirit

> **Competitive Mapping Rework:**

* Aiden
* Derpduck
* Mart

> [!NOTE]
> If your work is being used and I forgot to credit you, don't hesitate to contact me on Discord (user: `sirplease`)
