# 服务器运行与重启

服务器采用单所有者模型：`ecs-user` 是 SSH/SFTP 维护账户，`l4d2` 是游戏进程账户，两者同属 `l4d2` 组。`/home/l4d2/server` 是配置、插件和 VPK 的唯一真实目录；不再使用 Git release、overlay 或 VPK 投递目录覆盖它。

## 两个维护入口

`sudo l4d2-restart-now [原因]` 在 systemd journal 中记录操作者、地图和真人数，然后通过 systemd 重启并等待健康检查。它适合已经有人等着玩的情况。

VPK 或 SMX 上传完成后，显式执行：

```bash
sudo l4d2-content-apply
```

该命令完整读取并校验 `left4dead2/addons/` 根目录的 VPK，并要求第三方战役提供 AstMod/AstRedux 所需的 Versus 章节定义。在全部校验成功后只重建 `missioncycle.txt` 的“第三方战役”段，然后执行一次正常重启。官图段、已有三方显示名和顺序不会被重新生成；新增战役追加，已删除 VPK 对应战役移除。`--check` 只显示清单差异，不写文件、不重启。CFG、管理员、服务器名、公告和 Stripper 文件继续由所有者直接维护。

游戏内 `!restart [原因]` 和 `!restartserver [原因]` 由 `server_restart.smx` 提供，需要 SourceMod 的 `m`（RCON）管理标志。插件记录管理员身份并广播提示，然后立即执行正常 `quit`；systemd 的 `Restart=always` 负责重新拉起，不向游戏进程开放 sudo。这里故意不用 SourceMod timer，避免空服休眠让倒计时挂起。

## 安装与检查

```bash
cd /home/l4d2/integration
sudo ./ops/install.sh
sudo l4d2-content-apply --check
sudo l4d2-content-apply
systemctl status l4d2
journalctl -u l4d2 -t l4d2-restart --since today
```

安装脚本把 `ecs-user` 加入 `l4d2` 组，并让 `/home/l4d2/server` 保持组可写和目录 setgid。首次执行后重新连接 SSH/WinSCP，之后可直接维护游戏目录。维护记录统一查看 systemd journal，不再维护 manifest、baseline 或独立 history 文件。

Windows 下可直接运行 `ops/windows/` 中的三个 `.cmd` 入口，分别执行内容检查、内容应用并重启、仅重启服务器。它们只调用本机 SSH 配置中的 `l4d2-vps`，不保存服务器地址或密钥。
