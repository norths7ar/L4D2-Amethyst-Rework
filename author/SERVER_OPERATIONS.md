# 服务器操作

服务器是单所有者环境。`ecs-user` 用于 SSH/WinSCP，`l4d2` 只运行游戏；两个账户共享 `l4d2` 组。游戏目录 `/home/l4d2/server` 是唯一真实状态，不使用 overlay、release staging 或单独的 VPK 投递目录。

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

CFG、管理员、名字、公告和 Stripper 文件由所有者直接维护，不经过投递或覆盖层。需要立即让 SourceMod 重读管理员时，在服务器控制台执行 `sm_reloadadmins`；普通 CFG 是否立即生效由具体插件和执行时机决定。

## 重启

有人急着玩、无需等待空服时：

```bash
sudo l4d2-restart-now "原因"
```

脚本会记录操作者、当前地图、真人数、原因和 VPK/SMX 摘要，然后直接重启并等待健康检查。记录位于 systemd journal 和 `/var/lib/l4d2-restart/history.log`。

`l4d2-content-watch.timer` 每分钟比较游戏目录中全部 VPK 和插件 SMX。增、删、改任一种变化连续稳定 60 秒后，如果确认 0 真人，就调用同一个重启脚本；有人或人数未知时延期。查看状态：

```bash
systemctl status l4d2 l4d2-content-watch.timer
journalctl -u l4d2 -t l4d2-restart --since today
sudo cat /var/lib/l4d2-restart/last-change.diff
```

具备 SourceMod `m`（RCON）管理标志的管理员也可以在游戏内执行：

```text
!restart 原因
!restartserver 原因
```

服务器广播提示后立即正常退出，systemd 自动拉起。该插件故意不使用会受空服休眠影响的倒计时，也不执行 shell、不持有 sudo、不能运行任意主机命令。
