param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputPath,
    [string]$OutputDirectory,
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
if (-not $InputPath) {
    $InputPath = @((Read-Host '请输入地图文件夹、VPK 或 ZIP 路径').Trim('"'))
}
if (-not $InputPath -or [string]::IsNullOrWhiteSpace($InputPath[0])) {
    throw '未提供输入路径。'
}

$uvCommand = Get-Command uv -ErrorAction SilentlyContinue
$uvPath = if ($uvCommand) { $uvCommand.Source } else { Join-Path $env:USERPROFILE '.local/bin/uv.exe' }
if (-not (Test-Path -LiteralPath $uvPath -PathType Leaf)) {
    throw '找不到 uv。请先安装 uv，或使用 Python 3.11+ 运行 prepare_campaign_vpks.py。'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $repoRoot)
$env:UV_CACHE_DIR = Join-Path $workspaceRoot '.cache/uv'
$nativeArguments = @('run', '--no-project', '--python', '>=3.11', (Join-Path $PSScriptRoot 'prepare_campaign_vpks.py'))
if ($OutputDirectory) { $nativeArguments += @('--output', $OutputDirectory) }
if ($Overwrite) { $nativeArguments += '--overwrite' }
$nativeArguments += $InputPath
& $uvPath @nativeArguments
exit $LASTEXITCODE
