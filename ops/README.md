# 服务器运行与重启

服务器采用单所有者模型：`ecs-user` 是 SSH/SFTP 维护账户，`l4d2` 是游戏进程账户，两者同属 `l4d2` 组。`/home/l4d2/server` 是唯一运行目录，`/home/l4d2/integration` 是 Git 管理内容的部署来源；不再使用 release tree、overlay 或 VPK 投递目录。

## 目录结构

- `linux/`：Linux 服务端安装脚本、运维命令、systemd 服务和测试。
- `windows/`：Windows 本地操作入口，通过 SSH 调用服务端命令。

## 维护入口

Windows 的更新入口是 `ops/windows/02-apply-content-and-restart.cmd`，远端执行 `sudo l4d2-update-and-restart`：它校验 Git checkout 的分支和工作树，只做 fast-forward 更新，将 Git 跟踪的 `addons/`、`cfg/`、`scripts/` 部署到游戏目录，再复用内容校验和重启。01 只检查内容，03 只重启；两者都不执行 Git。

测试期默认开启 `srcds_run -debug`，异常退出报告写入 `$SERVER_ROOT/debug.log`；完整 backtrace 还要求启动脚本能取得 core，系统将 core 转交 Apport 时不能仅凭 `-debug` 认定回溯可用。性能观测由 `l4d2-observe.service` 与 `server_observe.smx` 共同提供，按日保留正常和卡顿时段，默认 7 天，不再按大小裁剪基线。指标、标记和报告命令见 [服务器操作](../docs/server-operations.md#性能观测)。

`sudo l4d2-restart-now [原因]` 在 systemd journal 中记录操作者、地图和真人数，然后通过 systemd 重启并等待健康检查。它适合已经有人等着玩的情况。

VPK 或 SMX 上传完成后，显式执行：

```bash
sudo l4d2-content-apply
```

该命令按文件大小和修改时间复用 `/var/cache/l4d2/vpk-campaigns.json` 中的成功校验结果，扫描 `left4dead2/addons/` 根目录，仅对新增或变化的 VPK 完整读取并校验，并要求第三方战役提供 AstMod/AstRedux 所需的 Versus 章节定义。全部校验成功后合并仓库清单与云服旧清单，再执行一次正常重启：官图段使用仓库版本；第三方战役先按仓库顺序和名字排列，仓库外已有地图保留历史顺序和名字，本次新发现的地图按标题排序后追加，已删除 VPK 对应战役移除。02 部署不会直接覆盖或删除云服 `missioncycle.txt`，而是与直接内容应用一样，使用 `CHECKOUT_ROOT`（默认 `/home/l4d2/integration`）中的仓库清单完成合并。`--check` 只显示清单差异，不修改清单、不重启，但会更新校验缓存。Git 跟踪的 CFG、管理员、公告和 Stripper 文件应在仓库中维护；未跟踪的服务器私有文件和第三方内容仍可直接维护。

游戏内 `!restart [原因]` 和 `!restartserver [原因]` 由 `server_restart.smx` 提供，需要 SourceMod 的 `m`（RCON）管理标志。插件记录管理员身份并广播提示，然后立即执行正常 `quit`；systemd 的 `Restart=always` 负责重新拉起，不向游戏进程开放 sudo。这里故意不用 SourceMod timer，避免空服休眠让倒计时挂起。

## 安装与检查

从旧运维链首次切换时，新 helper 尚未安装，先手动完成一次 bootstrap：

```bash
cd /home/l4d2/integration
git fetch origin main
git merge --ff-only origin/main
sudo ./ops/linux/install.sh
sudo l4d2-content-apply --check
sudo l4d2-content-apply
systemctl status l4d2
journalctl -u l4d2 -t l4d2-restart --since today
```

此后 Git 更新、运行文件部署、内容检查和重启统一由 Windows 的 02 入口完成，不再重复手动 bootstrap。

安装脚本把 `ecs-user` 加入 `l4d2` 组，并让 `/home/l4d2/server` 保持组可写和目录 setgid。首次执行后重新连接 SSH/WinSCP，之后可直接维护未由 Git 跟踪的服务器内容。维护记录统一查看 systemd journal，不再维护文件 manifest、overlay baseline 或独立 history 文件。

Windows 下可直接运行 `ops/windows/` 中的三个 `.cmd` 入口，分别执行内容检查、内容应用并重启、仅重启服务器。它们只调用本机 SSH 配置中的 `l4d2-vps`，不保存服务器地址或密钥。

更新 helper 使用配置中的 `CHECKOUT_ROOT`、`CHECKOUT_BRANCH` 和 `CHECKOUT_REMOTE`，复用 `OWNER_USER` 与 `GAME_DIR`。首次部署没有 marker 时，以更新前的 checkout revision 作为部署基线；之后使用 `/var/lib/l4d2/last-deployed-revision`。它只删除基线到新 revision 间被 Git 删除或重命名的运行时路径，不使用 `rsync --delete`，未跟踪的本地服务器文件会保留。marker 仅在部署、内容校验和重启全部成功后更新；失败时 checkout 可能已更新，但不会被标记为已部署。
