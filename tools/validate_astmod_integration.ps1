[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

# Check integration inputs and load relationships, not SourcePawn implementation
# details or gameplay tuning. AstFlex is paused and is outside this check.
$modes = @('astmod', 'astredux', 'public_coop')
$failures = [System.Collections.Generic.List[string]]::new()
$commandsByPath = @{}

function Assert-Path {
    param([string]$RelativePath)
    if (-not (Test-Path -LiteralPath (Join-Path $Root $RelativePath))) {
        $failures.Add("Missing required path: $RelativePath")
    }
}

function Get-ConfigCommands {
    param([string]$RelativePath)
    if (-not $commandsByPath.ContainsKey($RelativePath)) {
        $path = Join-Path $Root $RelativePath
        $commandsByPath[$RelativePath] = @()
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $failures.Add("Missing config: $RelativePath")
            return
        }
        $commandsByPath[$RelativePath] = @(Get-Content -LiteralPath $path -Encoding utf8 | ForEach-Object {
            $command = ($_ -replace '\s*//.*$', '').Trim()
            if ($command -and -not $command.StartsWith(';')) { $command }
        })
    }
    $commandsByPath[$RelativePath]
}

function Get-PluginLoads {
    param([string]$RelativePath, [string[]]$Parents = @())
    if ($RelativePath -in $Parents) {
        $failures.Add("Config exec cycle: $(($Parents + $RelativePath) -join ' -> ')")
        return
    }
    foreach ($command in Get-ConfigCommands $RelativePath) {
        if ($command -match '^sm\s+plugins\s+load\s+"?([^"\s]+)"?\s*$') {
            $Matches[1]
        }
        elseif ($command -match '^exec\s+"?([^"\s]+\.cfg)"?\s*$') {
            Get-PluginLoads "cfg/$($Matches[1])" ($Parents + $RelativePath)
        }
    }
}

function Assert-KeyValuesBraceBalance {
    param([string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Assert-Path $RelativePath
        return
    }
    $depth = 0
    # Ignore quoted values (including translation placeholders) and comments.
    $tokens = [regex]::Matches([IO.File]::ReadAllText($path), '"(?:\\.|[^"\\])*"|//[^\r\n]*|[{}]')
    foreach ($token in $tokens) {
        if ($token.Value -eq '{') { $depth++ }
        elseif ($token.Value -eq '}') { $depth-- }
        if ($depth -lt 0) { break }
    }
    if ($depth -ne 0) { $failures.Add("Unbalanced KeyValues braces: $RelativePath") }
}

foreach ($path in @(
    'addons/astmod.vpk',
    'assets/astmod_vpk/scripts/gamemodes.txt',
    'addons/sourcemod/extensions/imatchext.autoload',
    'addons/sourcemod/extensions/imatchext.ext.2.l4d2.so',
    'addons/sourcemod/extensions/langparser.ext.2.l4d2.so',
    'addons/sourcemod/gamedata/imatchext.txt',
    'addons/sourcemod/gamedata/fix_exec_config_unicode.txt',
    'scripts/vscripts/astmod.nut',
    'scripts/vscripts/astredux.nut',
    'cfg/stripper/astredux'
)) { Assert-Path $path }

$pluginListPaths = @('cfg/generalfixes.cfg', 'cfg/competitive_shared.cfg', 'cfg/sharedplugins.cfg')
$pluginListPaths += Get-ChildItem -LiteralPath (Join-Path $Root 'cfg/cfgogl') -Recurse -File |
    Where-Object { $_.Name -like 'plugins_*.cfg' -or $_.Name -in @('shared_plugins.cfg', 'sharedplugins.cfg', 'confogl_plugins.cfg', 'generalfixes.cfg') } |
    ForEach-Object { [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') } |
    Where-Object { $_ -notlike 'cfg/cfgogl/astflex/*' }
$pluginListPaths = @($pluginListPaths | Sort-Object -Unique)
$activeLoads = 0
foreach ($list in $pluginListPaths) {
    foreach ($command in Get-ConfigCommands $list) {
        if ($command -match '^sm\s+plugins\s+load\s+"?([^"\s]+)"?\s*$') {
            $activeLoads++
            Assert-Path "addons/sourcemod/plugins/$($Matches[1])"
        }
        elseif ($command -match '^exec\s+"?([^"\s]+\.cfg)"?\s*$') {
            Assert-Path "cfg/$($Matches[1])"
        }
        elseif ($command -notmatch '^sm\s+plugins\s+') {
            $failures.Add("Non-plugin command in ${list}: $command")
        }
    }
}

$modePlugins = @{}
foreach ($mode in $modes) {
    foreach ($name in @("$mode.cfg", 'confogl.cfg', 'confogl_plugins.cfg', 'confogl_off.cfg', 'shared_cvars.cfg', 'mapinfo.txt')) {
        Assert-Path "cfg/cfgogl/$mode/$name"
    }
    $modePlugins[$mode] = @(Get-PluginLoads "cfg/cfgogl/$mode/confogl_plugins.cfg")
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root "cfg/cfgogl/$mode") -Filter '*.cfg' -File) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        foreach ($command in Get-ConfigCommands $relative) {
            if ($command -match '^exec\s+"?([^"\s]+\.cfg)"?\s*$') {
                Assert-Path "cfg/$($Matches[1])"
            }
            if ($command -match '^sm\s+plugins\s+(load_unlock|unload_all|load_lock|refresh)\b') {
                $failures.Add("Mode bypasses framework plugin lifecycle: ${relative}: $command")
            }
        }
    }
}

$requiredPlugins = @{
    astmod = @('optional/astmod/jointeam.smx', 'optional/astmod/pause_coop.smx', 'optional/astmod/wave_spawner.smx')
    astredux = @('optional/coop/player_manager.smx', 'optional/coop/ready_pause.smx', 'optional/coop/survivor_loadout.smx', 'optional/coop/wave_spawner.smx', 'optional/coop/profile_controller.smx')
    public_coop = @('confoglcompmod.smx', 'optional/coop/campaign_switcher.smx')
}
foreach ($mode in $modes) {
    $loads = $modePlugins[$mode]
    foreach ($plugin in $requiredPlugins[$mode]) {
        if ($plugin -notin $loads) { $failures.Add("${mode}: missing required plugin $plugin") }
    }
    # Mutually exclusive implementations register overlapping commands/natives.
    foreach ($group in @(
        @('optional/coop/ready_pause.smx', 'optional/astmod/pause_coop.smx', 'optional/pause.smx'),
        @('optional/coop/player_manager.smx', 'optional/astmod/jointeam.smx', 'optional/playermanagement.smx'),
        @('optional/coop/ready_pause.smx', 'optional/competitive/readyup.smx'),
        @('optional/coop/ready_pause.smx', 'optional/astmod/jointeam.smx')
    )) {
        $present = @($group | Where-Object { $_ -in $loads })
        if ($present.Count -gt 1) { $failures.Add("${mode}: conflicting plugins: $($present -join ', ')") }
    }
    foreach ($wave in @('optional/coop/wave_spawner.smx', 'optional/astmod/wave_spawner.smx')) {
        if ($wave -notin $loads) { continue }
        $dependency = [Array]::IndexOf($loads, 'optional/coop/script_reloader.smx')
        if ($dependency -lt 0 -or $dependency -gt [Array]::IndexOf($loads, $wave)) {
            $failures.Add("${mode}: script_reloader must load before $wave")
        }
    }
}

$keyValuesFiles = @(
    'addons/sourcemod/configs/matchmodes.txt',
    'addons/sourcemod/configs/missioncycle.txt',
    'addons/sourcemod/configs/vote_menu.txt',
    'addons/sourcemod/configs/advertisements.txt',
    'addons/sourcemod/configs/astredux_profiles.cfg',
    'assets/astmod_vpk/scripts/gamemodes.txt'
)
# Resolve literal translation-file references; no source-variable or function-shape assertions.
foreach ($source in Get-ChildItem -LiteralPath (Join-Path $Root 'addons/sourcemod/scripting/optional/coop') -Filter '*.sp' -File) {
    foreach ($match in Select-String -LiteralPath $source.FullName -Pattern '^\s*LoadTranslations\("([^"\r\n]+)"\)' -AllMatches) {
        foreach ($reference in $match.Matches) {
            $filename = $reference.Groups[1].Value
            $keyValuesFiles += "addons/sourcemod/translations/$filename.txt"
            $localized = "addons/sourcemod/translations/chi/$filename.txt"
            if (Test-Path -LiteralPath (Join-Path $Root $localized)) { $keyValuesFiles += $localized }
        }
    }
}
$keyValuesFiles += $modes | ForEach-Object { "cfg/cfgogl/$_/mapinfo.txt" }
$keyValuesFiles = @($keyValuesFiles | Sort-Object -Unique)
foreach ($file in $keyValuesFiles) { Assert-KeyValuesBraceBalance $file }

$registry = Join-Path $Root 'addons/sourcemod/configs/matchmodes.txt'
if (Test-Path -LiteralPath $registry) {
    foreach ($mode in $modes) {
        if (-not (Select-String -LiteralPath $registry -Pattern ('^\s*"' + $mode + '"\s*$') -Quiet)) {
            $failures.Add("Matchmode is not registered: $mode")
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'Ast integration check failed:' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    exit 1
}
Write-Host 'Ast integration check passed.' -ForegroundColor Green
Write-Host "Plugin lists checked: $($pluginListPaths.Count); load commands: $activeLoads"
Write-Host "KeyValues files checked for brace balance: $($keyValuesFiles.Count)"
Write-Host 'This does not validate full KeyValues syntax, gameplay values, source/binary correspondence, or runtime behavior.'
