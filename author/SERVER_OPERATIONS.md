# Ubuntu 22.04 L4D2 服务器运行与维护

这份笔记面向在 Ubuntu 22.04 上部署 L4D2 Dedicated Server 的维护者，覆盖账号、进程、更新、发布、日志和恢复。玩法规则与模式配置见同目录的 `CONFIG_GUIDE.md`；AstMod 接入资产见 `../ASTMOD_INTEGRATION.md`。

## 运行账户与目录

服务器维护使用两个账户：日常 SSH/SFTP 运维账户，以及专门运行游戏进程的服务账户。服务账户拥有游戏目录，运维账户通过 `sudo -u <service-user>` 发布和启动服务。

建议将目录划分为：

```text
/srv/l4d2/
  server/       # SteamCMD 安装的实际游戏目录
  integration/  # 本仓库的服务器工作副本
  backup/       # 可恢复的配置与个人数据备份
  inbox/        # SFTP 上传暂存区
```

管理员 SteamID、个人称号、聊天归档和私有战役清单保存在维护者自己的 overlay；仓库记录这些功能的格式、部署位置和操作流程。

## 连接与交互式控制台

SSH 密钥是日常连接方式，SFTP 客户端可以作为图形化上传、下载和编辑工具。WinSCP、FileZilla 等客户端均可使用同一套 SFTP 凭据。

首次安装、调试启动参数或观察插件加载时，使用 tmux 或 screen 保存游戏控制台：

```bash
tmux new -s l4d2
tmux attach -t l4d2
```

按 `Ctrl+B` 后按 `D` 脱离 tmux，会话和游戏继续运行。tmux 适合交互式调试；稳定服务由 systemd 承载。

## systemd 承载游戏进程

systemd 服务负责启动 Dedicated Server、记录标准输出，并在异常退出后重新拉起。一个基础服务包含以下职责：

```ini
[Service]
User=l4d2
WorkingDirectory=/srv/l4d2/server
ExecStart=/srv/l4d2/server/srcds_run -game left4dead2 -console -usercon -tickrate 100 -port 27015 +map c1m1_hotel
Restart=on-failure
RestartSec=10
```

常用操作：

```bash
sudo systemctl start l4d2
sudo systemctl restart l4d2
sudo systemctl status l4d2
sudo journalctl -u l4d2 -f
```

游戏内插件负责玩法，systemd 负责进程生命周期。部署、更新和空服维护通过 systemd service/timer 或维护脚本发起服务重启。

## 空服维护与定时任务

定时任务适合安排在维护窗口执行：检查 Steam 更新、同步仓库工作副本、部署已验证改动、轮转日志和重启服务。

空服发布使用一个维护脚本完成两件事：读取服务器玩家状态，并在无人时执行部署和 `systemctl restart l4d2`。有玩家时脚本留下待发布标记，在下一次空服窗口继续处理。这样玩法插件始终服务于游戏过程，主机服务统一处理发布和重启。

## 更新与发布

更新游戏本体时，停止服务后使用 SteamCMD 更新 App 222860，再启动服务完成一次冷加载检查。

本仓库的发布流程：

1. 更新 `/srv/l4d2/integration/` 工作副本；
2. 在工作副本运行 `pwsh -File tools/validate_astmod_integration.ps1`；
3. 将 `addons/`、`cfg/`、`scripts/` 同步到 `server/left4dead2/`；
4. 确认游戏目录归服务账户所有；
5. 重启服务，进入对应模式完成冒烟测试。

VPK 放入 `left4dead2/addons/`。新增战役后检查控制台 addon 载入信息，再实际换图或运行 `!mapvote` 验证战役入口。

## 管理员与个人文件

`addons/sourcemod/configs/admins_simple.ini` 是 SourceMod 的管理员列表。维护者可用图形化编辑器维护私有 overlay 中的副本，再发布到服务器配置目录；新增管理员后重载管理员配置或重启服务。

个人可选插件放在独立的 optional 层，启用方式、所需 cfg、data、translations、VScript 和 VPK 资产写入插件清单。实际 SteamID、称号映射与玩家日志留在私有 overlay。

## 日志、备份与恢复

| 信息 | 位置或入口 |
| --- | --- |
| 进程启动与崩溃 | `journalctl -u l4d2` |
| 引擎日志 | `left4dead2/logs/` |
| SourceMod 日志 | `left4dead2/addons/sourcemod/logs/` |
| 实时调试 | tmux/screen 控制台或 journal 跟随输出 |

排查记录至少包含发生时间、地图、模式、玩家人数和控制台报错。备份覆盖私有 overlay、已验证配置版本和上传的第三方 VPK；恢复时先还原已验证配置，再启动服务验证冷加载和模式进入。

## 日常检查

- 查看磁盘空间、系统内存、游戏进程和 UDP 端口监听状态。
- 查看 SourceMod error log、systemd journal 和游戏崩溃痕迹。
- 在游戏、插件或 VPK 更新后执行一次模式加载与换图测试。
- 定期验证备份能恢复管理员配置和个人 overlay。
