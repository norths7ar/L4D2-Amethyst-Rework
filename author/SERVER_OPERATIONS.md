# Ubuntu 22.04 L4D2 服务器运行与维护

这份笔记面向 `/home/l4d2` 上的生产 L4D2 Dedicated Server。玩法规则与模式配置见同目录的 `CONFIG_GUIDE.md`；可执行运维入口和状态机见 `../ops/README.md`。

## 账户与目录

日常 SSH/SFTP 使用 `ecs-user`，游戏进程使用专用账户 `l4d2`。主机层维护通过 `sudo l4d2-maintain ...` 执行，再按职责以 `l4d2` 身份访问游戏和 Git 文件。

```text
/home/l4d2/
  server/       # SteamCMD 安装的实际游戏目录
  integration/  # 本仓库的干净工作副本，日常发布源为 origin/main
  releases/     # 按 commit 构建的不可变 release
  overlay/      # 管理员、个人配置等服务器私有覆盖
  content/      # 已激活的用户 VPK
  retiring/     # 被替换或删除的 VPK 可恢复副本
  backups/      # 发布前备份

/home/ecs-user/l4d2-addons/  # SFTP 可见的用户 VPK 期望集合
/var/lib/l4d2-maintain/      # manifest、pending 和已部署 commit
/run/l4d2/                   # 本机控制台 FIFO
```

管理员 SteamID、个人称号、聊天归档等保存在 overlay。仓库只记录这些功能的格式、部署位置和操作流程，不保存私密值。

## 连接与控制台

SSH 密钥是日常连接方式，WinSCP、FileZilla 等 SFTP 客户端可使用同一凭据。生产实例不开放 RCON。

稳定服务通过 `/run/l4d2/console.fifo` 接收固定的本机维护指令。tmux 只用于首次迁移前、迁移失败回退和临时交互调试，不再作为长期进程管理器。

## systemd 生命周期

`ops/systemd/l4d2.service` 以 `l4d2` 账户从 `/home/l4d2/server` 启动游戏，标准输出进入 journal，异常退出由 systemd 重启。不要在 service 运行时另起 tmux 游戏实例。

```bash
sudo systemctl start l4d2
sudo systemctl restart l4d2
sudo systemctl status l4d2
sudo journalctl -u l4d2 -f
```

首次安装分两步。第一步只写入脚本、配置和 unit，不改变当前 tmux；第二步设置临时服务器密码阻止新连接，确认空服后切换。systemd 启动失败会恢复并验证原 tmux 启动方式。

```bash
sudo ./ops/install.sh
sudo l4d2-maintain preflight
sudo ./ops/install.sh --activate
```

## 空服维护与 timer

`l4d2-maintenance.timer` 每十分钟运行一次收敛检查：检查 Steam 版本、Git 目标、用户 VPK 增删和进程 uptime。

`l4d2-maintain` 从本机控制台的 `status` 读取真人数。无法确认人数时拒绝维护；有人时只记录 pending；冷维护前先设置临时服务器密码阻止新连接，再确认空服并执行发布。中止时解除密码，成功重启后由 `server.cfg` 恢复 `NORMAL_SERVER_PASSWORD`。超过默认 36 小时 uptime 只增加待重启理由，不按固定时刻强退玩家。

## Git 更新与发布

默认发布过程如下：

1. 获取 `/home/l4d2/integration` 的 `origin/main`，解析固定 commit；
2. 在 `/home/l4d2/releases/<commit>/` 构建 release，随后合入私有 overlay；
3. 拒绝脏工作区和已纳管文件的未知漂移，备份当前版本；
4. 只同步 Git/overlay 纳管路径，并按旧 manifest 删除仓库中已经删除的文件；
5. 重启并通过 service、UDP 端口和控制台 `status` 健康检查；Git、overlay、missioncycle 和 content 失败时只自动恢复一次纳管状态。

服务器不会在游戏目录内运行 Git，也不会自动 reset 本地改动。功能分支或固定 commit 只能通过显式 `sudo l4d2-maintain converge <ref>` 发布；日常 timer 始终回到 `origin/main`。

更新游戏本体时，维护器先比较 Steam build。版本变化只记 pending，到空服窗口停止游戏后执行 SteamCMD，再与 Git/VPK 变更合并成一次冷启动。Steam 本体不在普通文件备份的回滚范围内；若更新后的二进制或 ABI 无法通过健康检查，需要使用 Steam/主机快照人工恢复，不能把配置恢复误称为 Steam 回滚。

## 用户 VPK 与战役清单

第三方 VPK 不进入 Git 发布目录。通过 SFTP 上传到 `/home/ecs-user/l4d2-addons`，上传中使用 `.part`，完成后原子改名为 `.vpk`。该目录是期望集合：新增文件表示安装，删除文件表示退役。

新增或更新时，维护器先检查 VPK 结构、分卷、mission 文件和重复地图，再原子复制并执行：

```text
update_addon_paths; mission_reload
```

热加载后仍保留冷重启标记。删除时先从 `addons/sourcemod/configs/missioncycle.txt` 的“第三方战役”段移除，实际 VPK 等到空服窗口再退役和冷重启。该文件是 Campaign Switcher 唯一 Map 策略文件，负责白名单、顺序和显示名；实际 Mission/Chapter 可用性来自 imatchext Mission Cache，`mission_reload` 后插件会随 `OnMissionCacheReload` 重建注册表。`vote_menu.txt` 只负责通用投票入口。

## 管理员与私有 overlay

`addons/sourcemod/configs/admins_simple.ini` 是 SourceMod 管理员列表。服务器私有版本应按同一相对路径放入 `/home/l4d2/overlay/`，由发布 staging 合入，避免 Git 更新覆盖私有值。

个人可选插件同样放在 overlay，并保持插件、cfg、data、translations、VScript 和 VPK 依赖完整。用户上传的第三方 VPK 不属于 overlay，由 content 状态机单独管理。

## 日志、备份与恢复

| 信息 | 位置或入口 |
| --- | --- |
| 进程启动与崩溃 | `journalctl -u l4d2` |
| 自动维护 | `journalctl -u l4d2-maintenance` |
| 引擎日志 | `left4dead2/logs/` |
| SourceMod 日志 | `left4dead2/addons/sourcemod/logs/` |
| 当前综合状态 | `sudo l4d2-maintain status` |

每次冷维护前保存旧 manifest、Git commit、missioncycle、纳管文件和 content 快照。纳管状态自动恢复只尝试一次；仍失败或 Steam 本体不兼容时，timer 以非零状态退出，保留 journal 和备份供人工处理。

```bash
sudo l4d2-maintain rollback
```

## 日常检查

- `sudo l4d2-maintain status`：磁盘、进程、端口、玩家、地图、Git、VPK 和 pending。
- `sudo l4d2-maintain preflight`：依赖、目录、工作区、进程唯一性和玩家状态来源。
- `sudo systemctl list-timers l4d2-maintenance.timer`：下次自动收敛时间。
- `sudo journalctl -u l4d2 -u l4d2-maintenance --since today`：游戏与维护失败。
- 游戏、插件或 VPK 更新后实际进入对应模式并换图；宿主健康检查不能替代玩法验证。
