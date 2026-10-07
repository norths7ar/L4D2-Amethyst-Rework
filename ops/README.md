# 服务器运维工具

`linux/` 提供安装脚本、运维命令和 systemd 服务，`windows/` 提供 SSH 调用入口。日常更新、地图维护和排障见 [服务器操作](../docs/server-operations.md)。

## 安装与配置

服务器使用 `root` 维护与部署，`l4d2` 运行游戏。游戏安装在 `/home/l4d2/server`，仓库 checkout 位于 `/home/l4d2/integration`。主机需具备 Bash、Python 3、Git、rsync、flock、sudo，以及运行脚本使用的 systemd 和常规 Linux 工具；启用 `SRCDS_DEBUG` 时还需 gdb。

首次安装或更新运维工具时，先将 checkout 更新到已确认的版本，再执行：

```bash
cd /home/l4d2/integration
sudo ./ops/linux/install.sh
```

安装脚本更新 `/usr/local/sbin/`、`/usr/local/libexec/l4d2/` 下的工具和 `l4d2.service`，启用服务但不启动或重启游戏。现有 `/etc/l4d2-restart.conf` 不会被覆盖；首次安装使用 [配置示例](linux/l4d2-restart.conf.example)，以后新增配置需自行核对。

配置包含运行账户、目录、绑定地址、端口、起始地图、启动健康检查超时，以及 `CHECKOUT_ROOT`、`CHECKOUT_BRANCH`、`CHECKOUT_REMOTE`。实际更新来源以该配置为准。Windows 入口只引用本机 SSH 别名 `l4d2-coreyun`，不保存地址或密钥。

## 进程与重启

`l4d2.service` 负责游戏进程，使用 `Restart=always` 在正常退出或异常退出后重新拉起。`l4d2-run` 检查已有进程和端口占用，并提供本机控制台 FIFO。

`l4d2-restart-now` 记录操作者、地图、真人数和原因，立即重启并等待健康检查。游戏内重启插件只执行正常 `quit`，不持有 sudo 权限。

`SRCDS_DEBUG=1` 启用 `srcds_run -debug`，报告位置由 `SRCDS_DEBUG_LOG` 指定。完整回溯还要求可取得 core；仅有 debug 开关不保证系统未将 core 交给其他处理程序。

## 仓库部署与数据保护

`l4d2-update-and-restart` 以配置的仓库所有者身份运行 Git，要求指定分支、干净工作树和 fast-forward 更新。它只部署 Git 跟踪的 `addons/`、`cfg/`、`scripts/`，随后调用内容应用和重启。

- 删除只针对部署基线到新版本之间被 Git 删除或重命名的运行时路径，不使用全目录删除同步；未跟踪文件保留。
- SQLite 数据库及辅助文件、`cannounce_messages.txt` 在复制和删除阶段均排除。`missioncycle.txt` 交由地图内容处理，不直接覆盖或删除。
- 成功版本记录在 `/var/lib/l4d2/last-deployed-revision`；首次没有记录时以更新前 checkout 为基线。仅在部署、内容应用和重启全部成功后推进，失败时 checkout 可能已更新。
- Git 获取失败会重试，最终失败则跳过仓库部署，仍尝试应用已经上传的内容并重启，不推进部署记录。应分别判断仓库更新与内容应用的结果。

仓库内容部署不会安装 `ops/` 工具。涉及数据保护规则的工具更新应先安装，再执行内容部署。

## 地图内容处理

`l4d2-content-apply` 扫描游戏 `addons/` 根目录中的 VPK，校验战役定义及冲突，生成 `missioncycle.txt` 后重启。`--check` 只检查并展示差异，不修改清单、权限或重启，但会更新校验缓存。

工坊分包中的重复战役声明按 versus 小关卡名称及顺序比较；一致时合并为一项，不要求包名相同。相同战役 ID 的章节不一致或不同战役的章节部分重叠仍视为冲突，不收录受影响战役。

校验缓存位于 `/var/cache/l4d2/vpk-campaigns.json`，按大小和修改时间复用成功结果；分卷任一变化会重新检查整组。第三方战役需具备 Versus 章节定义，坏包和冲突战役会被跳过并从可选清单移除，其余有效战役仍会应用。

清单中的官图段来自仓库；第三方战役依次采用仓库顺序及译名、仓库外已有战役的历史顺序及名字、本次新发现战役的标题顺序。删除 VPK 后移除相应战役。仓库清单由 `CHECKOUT_ROOT` 定位，生成结果原子写入。

上传文件通常使用 644、目录使用 755。内容应用会为 addons 根目录 VPK 补齐读取权限，并以游戏账户检查可读性。
