[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($Root)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $Root = Split-Path -Parent $scriptDirectory
}

$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message)
}

function Assert-Path {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing required path: $RelativePath"
    }
}

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $Root $RelativePath
    if (-not (Select-String -LiteralPath $path -Pattern $Pattern -Quiet)) {
        Add-Failure "$Description ($RelativePath)"
    }
}

function Assert-NotContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $Root $RelativePath
    if (Select-String -LiteralPath $path -Pattern $Pattern -Quiet) {
        Add-Failure "$Description ($RelativePath)"
    }
}

function Assert-RawContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $Root $RelativePath
    $content = Get-Content -LiteralPath $path -Raw -Encoding utf8
    if ($content -notmatch $Pattern) {
        Add-Failure "$Description ($RelativePath)"
    }
}

function Assert-KeyValuesBraceBalance {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    $depth = 0
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $path -Encoding utf8) {
        $lineNumber++
        $content = $line -replace '//.*$', ''
        $depth += ([regex]::Matches($content, '\{')).Count
        $depth -= ([regex]::Matches($content, '\}')).Count
        if ($depth -lt 0) {
            Add-Failure "Unexpected closing brace in ${RelativePath}:$lineNumber"
            return
        }
    }

    if ($depth -ne 0) {
        Add-Failure "Unbalanced braces in $RelativePath (depth $depth)"
    }
}

function Assert-PluginListCommands {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $path -Encoding utf8) {
        $lineNumber++
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -match '^[\\/]*//' -or $trimmed.StartsWith(';')) {
            continue
        }

        $command = ($line -replace '\s*//.*$', '').Trim()
        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        if ($command -match '^sm\s+plugins\s+') {
            continue
        }

        if ($command -match '^exec\s+(\S+\.cfg)\s*$') {
            $execTarget = Join-Path $Root "cfg/$($Matches[1])"
            if (-not (Test-Path -LiteralPath $execTarget -PathType Leaf)) {
                Add-Failure "Missing exec target in plugin list ${RelativePath}:$lineNumber ($($Matches[1]))"
            }
            continue
        }

        Add-Failure "Non-plugin command in plugin list ${RelativePath}:$lineNumber ($command)"
    }
}

$modes = @("astmod", "astredux", "astflex")
$requiredPaths = @(
    "addons/astmod.vpk",
    "assets/astmod_vpk/addoninfo.txt",
    "assets/astmod_vpk/scripts/gamemodes.txt",
    "addons/sourcemod/configs/matchmodes.txt",
    "addons/sourcemod/configs/cfgs.txt",
    "addons/sourcemod/configs/advertisements.txt",
    "addons/sourcemod/configs/astredux_profiles.cfg",
    "cfg/generalfixes.cfg",
    "cfg/competitive_shared.cfg",
    "cfg/sharedplugins.cfg",
    "cfg/stripper/astmod",
    "scripts/vscripts/astmod.nut",
    "scripts/vscripts/astredux.nut",
    "tools/build_astmod_vpk.ps1"
)

foreach ($mode in $modes) {
    foreach ($file in @(
        "$mode.cfg",
        "confogl.cfg",
        "confogl_off.cfg",
        "confogl_plugins.cfg",
        "mapinfo.txt",
        "plugins_1.cfg",
        "plugins_2.cfg",
        "plugins_3.cfg",
        "shared_cvars.cfg"
    )) {
        $requiredPaths += "cfg/cfgogl/$mode/$file"
    }
}

foreach ($relativePath in $requiredPaths) {
    Assert-Path $relativePath
}

$pluginListPaths = @(
    "cfg/generalfixes.cfg",
    "cfg/competitive_shared.cfg",
    "cfg/sharedplugins.cfg"
)
$cfgoglRoot = Join-Path $Root "cfg/cfgogl"
$pluginListPaths += Get-ChildItem -LiteralPath $cfgoglRoot -Recurse -File |
    Where-Object { $_.Name -like "plugins_*.cfg" -or $_.Name -in @("shared_plugins.cfg", "confogl_plugins.cfg") } |
    ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') }
$pluginListPaths = $pluginListPaths | Sort-Object -Unique

foreach ($pluginListPath in $pluginListPaths) {
    Assert-PluginListCommands $pluginListPath
}

$loadPattern = '^\s*sm\s+plugins\s+load\s+([^\s]+)'
$activeLoads = 0
foreach ($pluginListPath in $pluginListPaths) {
    $path = Join-Path $Root $pluginListPath
    foreach ($match in Select-String -LiteralPath $path -Pattern $loadPattern) {
        $activeLoads++
        $plugin = $match.Matches[0].Groups[1].Value.Trim('"')
        $pluginPath = Join-Path $Root "addons/sourcemod/plugins/$plugin"
        if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
            Add-Failure "Active plugin load has no file: $plugin (${pluginListPath}:$($match.LineNumber))"
        }
    }
}

$forbiddenLifecyclePattern = '^\s*sm\s+plugins\s+(load_unlock|unload_all|load_lock|refresh)\b|^\s*exec\s+generalfixes\.cfg\s*$'
foreach ($mode in $modes) {
    $modeRoot = Join-Path $Root "cfg/cfgogl/$mode"
    foreach ($match in Get-ChildItem -LiteralPath $modeRoot -Filter "*.cfg" -File |
        Select-String -Pattern $forbiddenLifecyclePattern) {
        Add-Failure "Forbidden framework lifecycle command at $([System.IO.Path]::GetRelativePath($Root, $match.Path)):$($match.LineNumber)"
    }

    $confoglPlugins = "cfg/cfgogl/$mode/confogl_plugins.cfg"
    Assert-RawContains `
        $confoglPlugins `
        '(?ms)^\s*exec\s+cfgogl/[^\s]+/plugins_1\.cfg\s*$.*?^\s*exec\s+cfgogl/[^\s]+/plugins_2\.cfg\s*$.*?^\s*exec\s+cfgogl/[^\s]+/plugins_3\.cfg\s*$' `
        "$mode plugin chunks are missing or out of order"

    Assert-Contains `
        "cfg/cfgogl/$mode/confogl_off.cfg" `
        '^\s*pred_unload_plugins\s*$' `
        "$mode does not use predictable plugin unloading"

    $modePluginLists = 1..3 | ForEach-Object { Join-Path $Root "cfg/cfgogl/$mode/plugins_$_.cfg" }
    $modePluginParts = $modePluginLists | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding utf8 }
    $modePluginText = $modePluginParts -join "`n"
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+confoglcompmod\.smx\s*$') {
        Add-Failure "$mode does not load confoglcompmod.smx"
    }
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+match_vote\.smx\s*$') {
        Add-Failure "$mode does not load match_vote.smx"
    }
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+optional/astmod/jointeam\.smx\s*$') {
        Add-Failure "$mode does not load jointeam.smx"
    }
    if ($modePluginText -match '(?m)^\s*sm\s+plugins\s+load\s+optional/playermanagement\.smx\s*$') {
        Add-Failure "$mode loads playermanagement.smx alongside jointeam.smx"
    }
}

foreach ($mode in $modes) {
    Assert-Contains `
        "addons/sourcemod/configs/matchmodes.txt" `
        ('^\s*"' + [regex]::Escape($mode) + '"\s*$') `
        "$mode is not registered in matchmodes.txt"
}

Assert-Contains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"astmod"\s*$' `
    "The VPK source does not define the astmod mutation"
Assert-Contains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"astredux"\s*$' `
    "The VPK source does not define the astredux mutation"
Assert-NotContains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"amethyst"\s*$' `
    "The legacy amethyst mutation remains in the VPK source"

$keyValuesFiles = @(
    "addons/sourcemod/configs/matchmodes.txt",
    "addons/sourcemod/configs/cfgs.txt",
    "addons/sourcemod/configs/advertisements.txt",
    "addons/sourcemod/configs/astredux_profiles.cfg"
)
foreach ($keyValuesFile in $keyValuesFiles) {
    Assert-KeyValuesBraceBalance $keyValuesFile
}

if ($failures.Count -gt 0) {
    Write-Host "Ast integration sanity check failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Ast integration sanity check passed." -ForegroundColor Green
Write-Host "Plugin lists checked: $($pluginListPaths.Count)"
Write-Host "Plugin load commands checked: $activeLoads"
Write-Host "KeyValues files checked: $($keyValuesFiles.Count)"
Write-Host "This static check does not verify gameplay values, source/binary correspondence, or runtime behavior."
