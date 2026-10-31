# 服务器操作

日常维护入口如下；运维工具的安装、配置和部署规则见 [ops/README](../ops/README.md)。

## 更新与重启

Windows 通过本机 SSH 配置中的 `l4d2-coreyun` 连接服务器：

| 入口 | 用途 | 远端命令 |
| --- | --- | --- |
| `ops/windows/01-check-content.cmd` | 检查上传内容，不重启 | `sudo l4d2-content-apply --check` |
| `ops/windows/02-apply-content-and-restart.cmd` | 更新仓库、部署内容、检查地图并重启 | `sudo l4d2-update-and-restart` |
| `ops/windows/03-restart-server.cmd` | 仅重启 | `sudo l4d2-restart-now` |

02 会部署仓库文件，但不会更新已经安装到系统中的运维脚本；脚本有改动时先按 [安装与配置](../ops/README.md#安装与配置) 更新工具。执行后检查输出和服务状态；提示 Git 获取失败时，不要把随后成功的内容应用与重启当作仓库更新成功。

游戏内拥有 `m`（RCON）标志的管理员也可执行 `!restart 原因` 或 `!restartserver 原因`，广播后立即退出游戏进程，由 systemd 重新启动。

## 配置与地图维护

云服游戏目录为 `/home/l4d2/server/left4dead2/`。仓库跟踪的配置应在仓库修改，再通过 02 部署；直接修改运行目录中的同名文件，下次部署会覆盖。未跟踪的私有文件和第三方地图可以通过 SSH/SFTP 维护。

| 内容 | 游戏目录下的路径 |
| --- | --- |
| 管理员 | `addons/sourcemod/configs/admins_simple.ini` |
| 服务器名、密码与基础设置 | `cfg/server.cfg` |
| 模式、公告与插件配置 | `cfg/`、`addons/sourcemod/configs/` |
| Stripper 插件程序 | `addons/stripper/bin/` |
| Stripper 地图规则 | `cfg/stripper/astredux/`、`cfg/stripper/zonemod/` |
| 插件 | `addons/sourcemod/plugins/` |
| 第三方地图 VPK | `addons/` |

`stripper_cfg_path` 选择当前模式的规则目录；只读取该目录的全图规则和地图规则，不会自动叠加默认的 `addons/stripper/` 配置。

修改管理员后，可在服务器控制台执行 `sm_reloadadmins`；其他配置是否即时生效取决于插件及执行时机。SQLite 数据库和 `addons/sourcemod/data/cannounce_messages.txt` 是运行数据，不在仓库维护。

上传前可使用[本地地图准备工具](../tools/README.md)补齐缺失的 Versus 声明、处理误命名 ZIP 和明确的末尾括号问题。整批 VPK 上传完成后，先运行 01 检查，再执行 `sudo l4d2-content-apply` 应用地图清单并重启；若同时需要部署仓库改动，则运行 02。VPK 使用简短 ASCII 文件名，例如 `blackmist_re_v13.vpk`。第三方战役需提供 AstRedux 所需的 Versus 章节定义；坏包或冲突战役会被跳过，应查看输出确认结果。

地图菜单按新图、官图、旧图排列。没有新增地图时，最近一批新图保持在前；下一批加入后，上一批归入旧图。排序在内容应用时更新，单独运行 01 检查不会改变最近批次。

`addons/sourcemod/configs/map_rules.cfg` 是上述覆盖规则的例外：部署时自动合并，保留游戏内修改；同字段冲突时保留云服值并提示。无需为了防止覆盖而提前同步回仓库，需纳入仓库的调整仍应手动同步。字段和命令见 [地图规则配置](configuration/map-rules.md)。

空服自动换图依赖 `sv_hibernate_when_empty 0`，防止空服休眠暂停计时。游戏内地图选择与轮换行为见 [地图切换配置](astredux-design.md#地图切换)。

## 日志与排障

```bash
systemctl status l4d2
journalctl -u l4d2 --since today
journalctl -u l4d2 -t l4d2-restart --since today
```

SourceMod 日志位于游戏目录的 `addons/sourcemod/logs/`，引擎日志位于 `logs/`。启用崩溃诊断时另查 `/home/l4d2/server/debug.log`；报告是否包含完整回溯取决于 core 是否可用。

报错时记录时间、地图、模式和操作步骤，并保留对应日志。新增地图或更新插件后，实际验证模式加载、准备开局和换图；VPK 校验通过但游戏仍缺图时，检查引擎 `maps` 输出及 Campaign Switcher 日志。
