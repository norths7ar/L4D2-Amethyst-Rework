# 服务器运行与重启

服务器采用单所有者模型：`ecs-user` 是 SSH/SFTP 维护账户，`l4d2` 是游戏进程账户，两者同属 `l4d2` 组。`/home/l4d2/server` 是唯一运行目录，`/home/l4d2/integration` 是 Git 管理内容的部署来源；不再使用 release tree、overlay 或 VPK 投递目录。

## 维护入口

Windows 的更新入口是 `ops/windows/02-apply-content-and-restart.cmd`，远端执行 `sudo l4d2-update-and-restart`：它校验 Git checkout 的分支和工作树，只做 fast-forward 更新，将 Git 跟踪的 `addons/`、`cfg/`、`scripts/` 部署到游戏目录，再复用内容校验和重启。01 只检查内容，03 只重启；两者都不执行 Git。

测试期默认开启 `srcds_run -debug`，非零退出后的 Source backtrace 写入 `$SERVER_ROOT/debug.log`。`l4d2-observe.service` 同时以低频滚动记录主机 CPU steal、内存、I/O pressure 和 `srcds_linux` 线程状态；检测到游戏子进程替换或持续 CPU steal 时，会把最近的基线与服务日志封存到 `/var/lib/l4d2-observe/incidents/`。默认保留 7 天；这些值可在 `/etc/l4d2-restart.conf` 调整。

`sudo l4d2-restart-now [原因]` 在 systemd journal 中记录操作者、地图和真人数，然后通过 systemd 重启并等待健康检查。它适合已经有人等着玩的情况。

VPK 或 SMX 上传完成后，显式执行：

```bash
sudo l4d2-content-apply
```

该命令完整读取并校验 `left4dead2/addons/` 根目录的 VPK，并要求第三方战役提供 AstMod/AstRedux 所需的 Versus 章节定义。在全部校验成功后只重建 `missioncycle.txt` 的“第三方战役”段，然后执行一次正常重启。官图段、已有三方显示名和顺序不会被重新生成；新增战役追加，已删除 VPK 对应战役移除。`--check` 只显示清单差异，不写文件、不重启。Git 跟踪的 CFG、管理员、公告和 Stripper 文件应在仓库中维护；未跟踪的服务器私有文件和第三方内容仍可直接维护。

游戏内 `!restart [原因]` 和 `!restartserver [原因]` 由 `server_restart.smx` 提供，需要 SourceMod 的 `m`（RCON）管理标志。插件记录管理员身份并广播提示，然后立即执行正常 `quit`；systemd 的 `Restart=always` 负责重新拉起，不向游戏进程开放 sudo。这里故意不用 SourceMod timer，避免空服休眠让倒计时挂起。

## 安装与检查

从旧运维链首次切换时，新 helper 尚未安装，先手动完成一次 bootstrap：

```bash
cd /home/l4d2/integration
git fetch origin main
git merge --ff-only origin/main
sudo ./ops/install.sh
sudo l4d2-content-apply --check
sudo l4d2-content-apply
systemctl status l4d2
journalctl -u l4d2 -t l4d2-restart --since today
```

此后 Git 更新、运行文件部署、内容检查和重启统一由 Windows 的 02 入口完成，不再重复手动 bootstrap。

安装脚本把 `ecs-user` 加入 `l4d2` 组，并让 `/home/l4d2/server` 保持组可写和目录 setgid。首次执行后重新连接 SSH/WinSCP，之后可直接维护未由 Git 跟踪的服务器内容。维护记录统一查看 systemd journal，不再维护文件 manifest、overlay baseline 或独立 history 文件。

Windows 下可直接运行 `ops/windows/` 中的三个 `.cmd` 入口，分别执行内容检查、内容应用并重启、仅重启服务器。它们只调用本机 SSH 配置中的 `l4d2-vps`，不保存服务器地址或密钥。

更新 helper 使用配置中的 `CHECKOUT_ROOT`、`CHECKOUT_BRANCH` 和 `CHECKOUT_REMOTE`，复用 `OWNER_USER` 与 `GAME_DIR`。首次部署没有 marker 时，以更新前的 checkout revision 作为部署基线；之后使用 `/var/lib/l4d2/last-deployed-revision`。它只删除基线到新 revision 间被 Git 删除或重命名的运行时路径，不使用 `rsync --delete`，未跟踪的本地服务器文件会保留。marker 仅在部署、内容校验和重启全部成功后更新；失败时 checkout 可能已更新，但不会被标记为已部署。
