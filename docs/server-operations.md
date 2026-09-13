# 服务器操作

## 性能观测

主机 `l4d2-observe.service` 每 5 秒采集一次，使用服务器现有 Python 3.10+ 标准库，不需要安装包。要求 cgroup v2 的 `system.slice/$SERVICE_NAME` 布局；安装入口启用 `kernel.sched_schedstats=1` 并只重启观测服务，不启动或重启游戏。完整基线为 `/var/lib/l4d2-observe/host-YYYY-MM-DD.jsonl`，按日保留约 7–8 天（到期按文件修改时间清理），不再限制为最近若干行。`OBSERVE_INTERVAL_SECONDS` 和 `OBSERVE_RETENTION_DAYS` 在 `/etc/l4d2-restart.conf` 配置。

记录逐逻辑 CPU 的 steal/user/system/idle、进程及各线程的区间 CPU、运行毫秒和调度等待毫秒、上下文切换、真实 swap、三类 PSI、换页、磁盘 I/O、网卡 errors/drops 和游戏 cgroup 的限流计数。线程 CPU 以一个逻辑 CPU 为 100%，主机汇总以所有 CPU 为 100%；等待是 Linux 调度器记录的 runnable 等待，不代表全部宿主机干扰。不可用字段为 null/缺失，不等于零。网卡本地丢包不是玩家网络链路丢包率。云平台未暴露的硬件频率、IPC 和物理核争用不能由这些指标直接证实或排除。

进程更替、逐核 steal 连续 3 个样本达到 10%、主线程调度等待占区间至少 10%、或 cgroup throttle 会在 `incidents/` 封存最近约 2 分钟主机样本与控制台尾部；非进程事件冷却 5 分钟。事后的记录仍在完整日文件中，判断卡顿不依赖是否触发归档。

全局加载的 `server_observe.smx` 在 `addons/sourcemod/logs/server_observe_YYYYMMDD.log` 每约 5 秒记录真实帧间隔的平均/最大值、超过 20/50/100ms 的次数、真人/特感/普通感染者/Witch/实体数、地图及暂停/准备/休眠状态；只清理自身超过 7 天的日文件。帧间隔不是 CPU 执行耗时；插件在引擎阻塞时也无法执行，恢复后才记录长间隔，完全无响应依靠主机日志判断。时间来自 SourcePawn 浮点引擎时钟，长时间运行后的精度会降低，不应解释成亚毫秒精密 profiler。实体数量是每次输出时的快照，不是该窗口所有工作量或峰值。

管理员可在聊天输入 `!lag`（卡）或 `!fine`（顺）；需带备注时仍可用 `!observe_mark <备注>`。命令只标记玩家体感，不参与自动测量；标记不广播、不记录玩家身份，只向调用者确认。没打标记也会持续采样。报告读取两套日志，排除空服/明确暂停/休眠样本，列出地图汇总、标记附近的窗口与缺失状态：

```bash
sudo python3 /usr/local/libexec/l4d2/observe_report.py --date 2026-09-10
```

报告是事后命令，不会自动给玩家发送消息。第一次部署后应检查 observer 的 active 状态、两端新日志及一次标记落盘；实时游玩表现仍需实际验证。

服务器是单所有者环境。`ecs-user` 用于 SSH/WinSCP，`l4d2` 只运行游戏；两个账户共享 `l4d2` 组。游戏目录 `/home/l4d2/server` 是唯一运行状态，Git checkout `/home/l4d2/integration` 是仓库内容的部署来源；不使用 overlay、release staging 或单独的 VPK 投递目录。

## 直接修改

重新连接 SSH/WinSCP 后，`ecs-user` 可以直接进入：

```text
/home/l4d2/server/left4dead2/
```

常用位置：

| 内容 | 路径 |
| --- | --- |
| 管理员 | `addons/sourcemod/configs/admins_simple.ini` |
| 服务器名、密码和基础设置 | `cfg/server.cfg` |
| 公告和插件配置 | `cfg/`、`addons/sourcemod/configs/` |
| Stripper | `addons/stripper/` |
| 插件 | `addons/sourcemod/plugins/` |
| 第三方地图 | `addons/` |

Git 跟踪的 CFG、管理员、公告和 Stripper 文件在仓库中维护，并由 02 部署；未跟踪的服务器私有文件和第三方内容仍可直接维护。需要立即让 SourceMod 重读管理员时，在服务器控制台执行 `sm_reloadadmins`；普通 CFG 是否立即生效由具体插件和执行时机决定。

## 应用 VPK/SMX

部署保护脚本须先更新到 `/usr/local/sbin/l4d2-update-and-restart`，再部署包含数据库取消跟踪的版本；仅拉取仓库不会自动更新这个已安装脚本。

Windows 的唯一更新/部署入口是 `ops/windows/02-apply-content-and-restart.cmd`，远端执行 `sudo l4d2-update-and-restart`。命令要求 Git checkout 位于配置分支且工作树干净，fetch 后仅允许 fast-forward，并以 `OWNER_USER` 身份运行 Git；只部署 Git 跟踪的 `addons/`、`cfg/`、`scripts/` 到 `GAME_DIR`，不覆盖未跟踪文件，也不执行 `rsync --delete`。数据库及 SQLite 辅助文件在复制和删除阶段均排除，即使旧版本曾跟踪数据库，也保留运行服现有数据。首次运行以更新前的 checkout revision 为基线，后续使用已成功部署的 revision；只按 Git revision 差异删除被删除或重命名的运行时路径。检查或重启失败时 marker 不更新，01 仍只检查内容，03 仍只重启。

文件仍然直接上传到游戏目录。整批 VPK/SMX 传完后先检查：

```bash
sudo l4d2-content-apply --check
```

确认结果后执行：

```bash
sudo l4d2-content-apply
```

命令按文件大小和修改时间缓存成功校验结果（`/var/cache/l4d2/vpk-campaigns.json`），仅完整校验新增或变化的 VPK；分卷任一变化会重新检查整组。汇总全部战役检查冲突，并要求第三方战役提供 AstMod/AstRedux 的 Versus 章节定义；随后合并并原子更新 `addons/sourcemod/configs/missioncycle.txt`，再重启一次。02 不直接覆盖云服清单：官图段使用仓库版本；三方图按“仓库顺序及译名、仓库外历史顺序及名字、本次新增地图”排列。新增地图被仓库收录后移到仓库指定位置，不重复出现；删除 VPK 则移除条目。直接内容应用使用相同规则，仓库来源为 `CHECKOUT_ROOT`（默认 `/home/l4d2/integration`）；`!mapvote`、`!nextmap` 使用每个战役的第一关，`!chaptervote` 由 Mission Cache 读取当前战役的全部章节。校验发现 VPK 损坏、任务定义不完整或 ID/地图冲突时，命令失败，不改清单也不重启。

## 重启

有人急着玩、无需等待空服时：

```bash
sudo l4d2-restart-now "原因"
```

脚本会在 systemd journal 中记录操作者、当前地图、真人数和原因，然后直接重启并等待健康检查；不再生成内容 manifest 或独立历史文件。

查看服务和重启历史：

```bash
systemctl status l4d2
journalctl -u l4d2 -t l4d2-restart --since today
```

具备 SourceMod `m`（RCON）管理标志的管理员也可以在游戏内执行：

```text
!restart 原因
!restartserver 原因
```

服务器广播提示后立即正常退出，systemd 自动拉起。该插件故意不使用会受空服休眠影响的倒计时，也不执行 shell、不持有 sudo、不能运行任意主机命令。
