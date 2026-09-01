# 服务器运行与重启

服务器采用单所有者模型：`ecs-user` 是 SSH/SFTP 维护账户，`l4d2` 是游戏进程账户，两者同属 `l4d2` 组。`/home/l4d2/server` 是配置、插件和 VPK 的唯一真实目录；不再使用 Git release、overlay 或 VPK 投递目录覆盖它。

## 两个维护入口

`sudo l4d2-restart-now [原因]` 无条件记录操作者、地图、真人数和内容摘要，然后通过 systemd 重启。它适合已经有人等着玩的情况。

`l4d2-restart-if-needed` 由 timer 每分钟运行，只监视以下内容：

- `left4dead2/addons/**/*.vpk`
- `left4dead2/addons/sourcemod/plugins/**/*.smx`

新增、删除或修改会写入 pending；同一个变化连续稳定 60 秒且服务器确认没有真人时才自动重启。未知人数或有人在线时只延期。CFG、管理员、服务器名、公告和 Stripper 文件不参与自动重启。

游戏内 `!restart [原因]` 和 `!restartserver [原因]` 由 `server_restart.smx` 提供，需要 SourceMod 的 `m`（RCON）管理标志。插件记录管理员身份并广播提示，然后立即执行正常 `quit`；systemd 的 `Restart=always` 负责重新拉起，不向游戏进程开放 sudo。这里故意不用 SourceMod timer，避免空服休眠让倒计时挂起。

## 安装与检查

```bash
cd /home/l4d2/integration
sudo ./ops/install.sh
sudo l4d2-restart-now "加载新的插件或配置"
systemctl status l4d2 l4d2-content-watch.timer
journalctl -u l4d2 -t l4d2-restart --since today
```

安装脚本会把 `ecs-user` 加入 `l4d2` 组，并让 `/home/l4d2/server` 保持组可写和目录 setgid。首次执行后重新连接 SSH/WinSCP，之后可直接维护游戏目录。历史记录和最后一次内容差异保存在 `/var/lib/l4d2-restart/`。
