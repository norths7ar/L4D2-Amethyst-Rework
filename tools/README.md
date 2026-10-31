# 本地地图准备

将地图文件夹、VPK 或 ZIP 拖到 `Prepare-CampaignVPKs.cmd`，也可以双击入口后输入路径。Windows 入口使用 PowerShell 7 和 uv，选择 Python 3.11 或更新版本；处理逻辑只使用 Python 标准库。

文件夹只扫描顶层 `.vpk`，不会递归处理备份和已有输出。扩展名是 VPK、实际内容是 ZIP 的文件会自动识别；普通 ZIP 可以单独拖入。ZIP 内有多个独立 VPK 时逐个输出，分卷包需先用 VPKEdit 合并为单文件包。

成品默认写入输入文件夹下的 `prepared-vpks`；单文件输入则写入其所在目录下的同名文件夹。原件保持不变，文件名不自动改动。上传成品目录中的 VPK 即可，`preparation-report.json` 供本地查看处理结果。

工具完整复制 `coop` 为缺失的 `versus`，已有 versus 保留；没有 coop 的 mission 会注明无法补齐并保留原有模式。mission 的注释、路径字符串和其他字段保持原样；明确缺少根对象或 modes 的末尾闭括号、根对象后多余的闭括号可自动修复。中间层级不明确、引号损坏等情况会报告文件名并继续处理其他输入。打包时校验 CRC，并比对未修改资源的内容哈希。

## 命令行

```powershell
pwsh -File tools/Prepare-CampaignVPKs.ps1 -InputPath 'E:/Maps/本次地图' -OutputDirectory 'E:/Maps/待上传'
```

重复运行时，同名且内容一致的成品会跳过；内容不同则提示检查。确认需要更新已有成品时添加 `-Overwrite`。该选项只允许覆盖成品，不能将输入文件作为输出覆盖。

也可以直接调用 Python 入口：

```text
python tools/prepare_campaign_vpks.py "E:/Maps/本次地图" --output "E:/Maps/待上传"
```

Python 入口对应的覆盖选项为 `--overwrite`。有文件处理失败时返回非零退出码，已成功生成的其他成品保留。
