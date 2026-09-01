# 服务器运维加固

`ops/` 是生产服务器的主机层运维入口，不参与玩法逻辑。目标服务器是 Ubuntu 22.04，当前约定路径为 `/home/l4d2`，游戏账户为 `l4d2`，SSH/SFTP 账户为 `ecs-user`。

## 能力边界

- `l4d2.service` 是稳定运行时唯一的游戏进程管理者；tmux 只用于迁移回退和临时调试。
- `/home/l4d2/integration` 只获取 Git，默认发布 `origin/main`。发布从固定 commit 构建不可变 release，不在游戏目录内执行 Git。
- `/home/l4d2/overlay` 保存服务器私有覆盖；它在 release 之后合入 staging。密钥、SteamID、管理员和个人数据不进入仓库。
- `/home/ecs-user/l4d2-addons` 是 SFTP 可见的用户 VPK 期望集合。加入稳定的 `.vpk` 表示安装，删除表示退役，上传中的文件应使用 `.part` 后缀。
- `/home/l4d2/content/addons` 是已激活用户 VPK 集合；`/home/l4d2/retiring` 保留替换或删除的可恢复副本。
- `addons/sourcemod/configs/missioncycle.txt` 是 Campaign Switcher 唯一 Map 策略文件，负责白名单、顺序和显示名；实际 Mission/Chapter 可用性来自 imatchext Mission Cache。工具保留官方段和已有显示名，只双向重建“第三方战役”段。
- 不开放 RCON。本机维护工具通过 systemd 的 FIFO 或迁移期 tmux 控制台执行固定的 `status`、addon reload 和 `quit`。

首次安装会把现有的 `admins_simple.ini` 和 `cfg/server.cfg` 种入 overlay，避免第一次 Git 发布覆盖服务器身份。SourceMod 的 SQLite 运行数据不纳入 Git 同步；自动更新的 gamedata/GeoIP 文件仍会发布，但不作为“工作区漂移”阻塞下一次维护。

## 状态收敛

`sudo l4d2-maintain converge` 执行同一个状态机：

1. 获取 `origin/main` 并构建 release/staging；脏工作区会被拒绝，不 reset、不覆盖。
2. 验证 SFTP 目录中的稳定 VPK、VPK 分卷、mission 文件和重复地图。
3. 新增或更新的 VPK 可原子热加入，并执行 `update_addon_paths; mission_reload`；无论热加载是否成功，都保留冷重启标记。
4. 删除的 VPK 立即从 `missioncycle.txt` 隐藏，但有人时保留实际文件。
5. 从控制台读取真人数。未知时失败关闭；有人时只保留 pending。冷维护前先设置临时服务器密码阻止新连接，再确认空服；中止时解除，成功重启后由 `server.cfg` 恢复正常密码。
6. 备份、停服、Steam 更新、Git 发布、VPK 退役、重建清单、启动和健康检查。
7. Git、overlay、missioncycle 或 content 发布失败时只自动恢复一次纳管状态。启动健康检查默认等待 60 秒，避免 srcds 正常冷启动被四秒级探测误判为失败；Steam 本体不做虚假的文件级回滚，更新后的二进制若无法启动，需要使用 Steam/主机快照人工恢复。日志进入 journal，失败的 timer 可由 systemd 直接审计。

连续运行超过 `MAX_UPTIME_HOURS`（默认 36 小时）只会增加一次待重启理由，不会在有人时强退。timer 每十分钟检查一次；Git、VPK、Steam 或 uptime 任一 pending 都在下一次空服窗口合并处理。

## 安装与切换

先安装文件但不切换当前 tmux：

```bash
cd /home/l4d2/integration
sudo ./ops/install.sh
sudo l4d2-maintain preflight
```

确认空服后执行一次迁移：

```bash
sudo ./ops/install.sh --activate
sudo l4d2-maintain converge
```

`--activate` 会设置临时新连接闸门并再次读取真人数，退出旧 tmux 实例，确认所有账户下的 `srcds_linux` 和端口占用均已消失，再启动 systemd。新服务健康检查失败时会恢复并验证 tmux 启动方式，不会启动第二个实例。

## 日常入口

```bash
sudo l4d2-maintain status
sudo l4d2-maintain preflight
sudo l4d2-maintain content-sync
sudo l4d2-maintain steam-check
sudo l4d2-maintain converge
sudo l4d2-maintain rollback
sudo systemctl status l4d2 l4d2-maintenance.timer
sudo journalctl -u l4d2 -u l4d2-maintenance --since today
```

服务器私有路径和阈值只改 `/etc/l4d2-maintain.conf`。修改 unit、脚本或配置后重新运行 `sudo ./ops/install.sh`，它不会在未带 `--activate` 时停止或启动游戏。
