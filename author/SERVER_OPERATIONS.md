# 服务器操作

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

Windows 的唯一更新/部署入口是 `ops/windows/02-apply-content-and-restart.cmd`，远端执行 `sudo l4d2-update-and-restart`。命令要求 Git checkout 位于配置分支且工作树干净，fetch 后仅允许 fast-forward，并以 `OWNER_USER` 身份运行 Git；只部署 Git 跟踪的 `addons/`、`cfg/`、`scripts/` 到 `GAME_DIR`，不覆盖未跟踪文件，也不执行 `rsync --delete`。首次运行以更新前的 checkout revision 为基线，后续使用已成功部署的 revision；只按 Git revision 差异删除被删除或重命名的运行时路径。检查或重启失败时 marker 不更新，01 仍只检查内容，03 仍只重启。

文件仍然直接上传到游戏目录。整批 VPK/SMX 传完后先检查：

```bash
sudo l4d2-content-apply --check
```

确认结果后执行：

```bash
sudo l4d2-content-apply
```

命令会完整校验 VPK，扫描其中的战役任务，并要求第三方战役提供 AstMod/AstRedux 的 Versus 章节定义；随后只原子更新 `addons/sourcemod/configs/missioncycle.txt` 的“第三方战役”段，再重启一次。官图段长期固定；`!mapvote`、`!nextmap` 使用每个战役的第一关，`!chaptervote` 由 Mission Cache 读取当前战役的全部章节。任一 VPK 损坏、任务定义不完整或 ID/地图冲突时，命令失败，不改清单也不重启。

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
