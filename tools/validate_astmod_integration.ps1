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

$requiredPaths = @(
    "addons/amethyst.vpk",
    "addons/sourcemod/configs/cfgs.txt",
    "addons/sourcemod/configs/hostname/hostname.txt",
    "addons/sourcemod/plugins/optional/amethyst/versus_coop_mode.smx",
    "addons/sourcemod/plugins/optional/amethyst/ACS.smx",
    "addons/sourcemod/plugins/optional/amethyst/vote.smx",
    "addons/sourcemod/plugins/optional/amethyst/sceneprocessor.smx",
    "addons/sourcemod/scripting/ACS.sp",
    "addons/sourcemod/scripting/AI_HardSI.sp",
    "addons/sourcemod/scripting/challenge.sp",
    "addons/sourcemod/scripting/vote.sp",
    "cfg/cfgogl/astmod/amethyst.cfg",
    "cfg/cfgogl/astmod/confogl.cfg",
    "cfg/cfgogl/astmod/confogl_off.cfg",
    "cfg/cfgogl/astmod/confogl_plugins.cfg",
    "cfg/cfgogl/astmod/plugins_1.cfg",
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astmod/plugins_3.cfg",
    "cfg/cfgogl/astmod/mapinfo.txt",
    "cfg/cfgogl/astmod/shared_cvars.cfg",
    "cfg/cfgogl/astflex/astflex.cfg",
    "cfg/cfgogl/astflex/confogl.cfg",
    "cfg/cfgogl/astflex/confogl_off.cfg",
    "cfg/cfgogl/astflex/confogl_plugins.cfg",
    "cfg/cfgogl/astflex/mapinfo.txt",
    "cfg/cfgogl/astflex/plugins_1.cfg",
    "cfg/cfgogl/astflex/plugins_2.cfg",
    "cfg/cfgogl/astflex/plugins_3.cfg",
    "cfg/cfgogl/astflex/shared_cvars.cfg",
    "cfg/astmod_test.cfg",
    "cfg/sourcemod/difficulty_adjustment_system",
    "cfg/sourcemod/difficulty_adjustment_system/easy_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/normal_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/hard_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/impossible_lite.cfg",
    "cfg/stripper/amethyst",
    "scripts/vscripts/amethyst.nut"
)

foreach ($relativePath in $requiredPaths) {
    Assert-Path $relativePath
}

$pluginLoadConfigRelatives = @(
    "cfg/cfgogl/astmod/plugins_1.cfg",
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astmod/plugins_3.cfg",
    "cfg/cfgogl/astflex/plugins_1.cfg",
    "cfg/cfgogl/astflex/plugins_2.cfg",
    "cfg/cfgogl/astflex/plugins_3.cfg"
)
$pluginLoadConfigs = $pluginLoadConfigRelatives | ForEach-Object { Join-Path $Root $_ }
$loadPattern = '^\s*sm plugins load\s+([^\s]+)'

foreach ($match in Select-String -LiteralPath $pluginLoadConfigs -Pattern $loadPattern) {
    $plugin = $match.Matches[0].Groups[1].Value -replace '/', '\'
    $pluginPath = Join-Path $Root "addons/sourcemod/plugins/$plugin"
    if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
        Add-Failure "Active plugin load has no file: $plugin"
    }
}

foreach ($pluginConfig in @(
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astflex/plugins_2.cfg"
)) {
    Assert-NotContains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/amethyst/clip_removal\.smx\s*$' `
        "Unverified clip_removal plugin is still active"
    Assert-NotContains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/amethyst/l4d2_smg_reload_tweak\.smx\s*$' `
        "AstMod SMG reload plugin would override the Zonemod weapon values"
    Assert-NotContains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/amethyst/l4d2_(weapon_attributes|static_shotgun_spread)\.smx\s*$' `
        "AstMod still loads an older isolated weapon-parameter plugin"
    Assert-Contains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/l4d2_weapon_attributes\.smx\s*$' `
        "AstMod does not share Zonemod's weapon-attributes implementation"
    Assert-Contains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/l4d2_static_shotgun_spread\.smx\s*$' `
        "AstMod does not share Zonemod's static-shotgun-spread implementation"
}

$difficultyConfigs = Get-ChildItem -LiteralPath (
    Join-Path $Root "cfg/sourcemod/difficulty_adjustment_system"
) -Filter "*.cfg"
if (Select-String -LiteralPath $difficultyConfigs.FullName -Pattern '^\s*sm_cvar\s+l4d2_reload_speed_' -Quiet) {
    Add-Failure "Difficulty profiles still override the Zonemod-synchronized SMG reload values"
}

function Get-SharedWeaponSettings {
    param([string]$RelativePath)

    $weaponPattern = '^\s*(confogl_addcvar\s+sgspread_|sm_weapon\s+(smg|smg_silenced|shotgun_chrome|pumpshotgun)\s+)'
    $path = Join-Path $Root $RelativePath
    return Get-Content -LiteralPath $path -Encoding utf8 |
        ForEach-Object { ($_ -replace '//.*$', '').Trim() } |
        Where-Object { $_ -match $weaponPattern } |
        ForEach-Object { $_ -replace '\s+', ' ' } |
        Sort-Object
}

$zonemodWeaponSettings = Get-SharedWeaponSettings "cfg/cfgogl/zonemod/shared_settings.cfg"
foreach ($modeConfig in @(
    "cfg/cfgogl/astmod/amethyst.cfg",
    "cfg/cfgogl/astflex/astflex.cfg"
)) {
    $modeWeaponSettings = Get-SharedWeaponSettings $modeConfig
    if (Compare-Object -ReferenceObject $zonemodWeaponSettings -DifferenceObject $modeWeaponSettings) {
        Add-Failure "Shared SMG, pump shotgun, chrome shotgun, or spread settings differ from Zonemod: $modeConfig"
    }
    Assert-NotContains `
        $modeConfig `
        '^\s*sm_melee\s+' `
        "Legacy sm_melee commands are incompatible with Zonemod's weapon-attributes plugin"
}

$forbiddenPattern = '^\s*(sm plugins (load_unlock|unload_all|load_lock|refresh)|exec generalfixes\.cfg)'
$modeConfigPaths = @("astmod", "astflex") | ForEach-Object { Join-Path $Root "cfg/cfgogl/$_" }
$forbidden = Get-ChildItem -LiteralPath $modeConfigPaths -Filter "*.cfg" |
    Select-String -Pattern $forbiddenPattern
foreach ($match in $forbidden) {
    Add-Failure "Forbidden lifecycle command at $($match.Path):$($match.LineNumber)"
}

Assert-Contains `
    "addons/sourcemod/configs/matchmodes.txt" `
    '^\s*"astmod"\s*$' `
    "AstMod is not registered in matchmodes.txt"
Assert-Contains `
    "addons/sourcemod/configs/matchmodes.txt" `
    '^\s*"astflex"\s*$' `
    "AstFlex is not registered in matchmodes.txt"
Assert-Contains `
    "cfg/cfgogl/astmod/confogl_off.cfg" `
    '^\s*pred_unload_plugins\s*$' `
    "AstMod does not use predictable unloading"
Assert-Contains `
    "cfg/cfgogl/astmod/plugins_3.cfg" `
    '^\s*sm plugins load confoglcompmod\.smx\s*$' `
    "AstMod does not reload Competitive Rework Confogl"
Assert-Contains `
    "cfg/cfgogl/astmod/plugins_3.cfg" `
    '^\s*sm plugins load match_vote\.smx\s*$' `
    "AstMod does not reload the Competitive Rework match vote"

Assert-Contains `
    "cfg/cfgogl/astflex/confogl_off.cfg" `
    '^\s*pred_unload_plugins\s*$' `
    "AstFlex does not use predictable unloading"
Assert-Contains `
    "cfg/cfgogl/astflex/plugins_3.cfg" `
    '^\s*sm plugins load confoglcompmod\.smx\s*$' `
    "AstFlex does not reload Competitive Rework Confogl"
Assert-Contains `
    "cfg/cfgogl/astflex/plugins_3.cfg" `
    '^\s*sm plugins load match_vote\.smx\s*$' `
    "AstFlex does not reload the Competitive Rework match vote"
Assert-Contains `
    "cfg/cfgogl/astflex/astflex.cfg" `
    '^\s*sm_cvar ai_hardsi_enable 0\s*$' `
    "AstFlex does not default Hard SI AI to off"
Assert-Contains `
    "cfg/cfgogl/astflex/astflex.cfg" `
    '^\s*confogl_addcvar das_suffix "_lite"\s*$' `
    "AstFlex does not use the lite wave profiles"
Assert-Contains `
    "cfg/cfgogl/astmod/amethyst.cfg" `
    '^\s*sm_cvar ai_hardsi_enable 1\s*$' `
    "AstMod does not restore Hard SI AI to on"
Assert-Contains `
    "addons/sourcemod/scripting/ACS.sp" `
    '!IsMapValid\(strCampaignFirstMap\)' `
    "ACS does not filter unavailable campaign maps"
Assert-Contains `
    "addons/sourcemod/scripting/vote.sp" `
    '!IsMapValid\(sSectionName\)' `
    "The !vote menu does not filter unavailable campaign maps"
Assert-Contains `
    "addons/sourcemod/scripting/AI_HardSI.sp" `
    'CreateConVar\("ai_hardsi_enable"' `
    "AI_HardSI does not expose its master enable cvar"
Assert-Contains `
    "addons/sourcemod/scripting/challenge.sp" `
    'FindConVar\("ai_hardsi_enable"\)' `
    "The /tz menu does not expose the Hard SI AI vote"
Assert-Contains `
    "scripts/vscripts/amethyst.nut" `
    'if \("update_diff" in g_ModeScript\)' `
    "The AstMod VScript does not guard its mode-switch reload callback"

$zoneOfficialMaps = Get-ChildItem -LiteralPath (Join-Path $Root "cfg/stripper/zonemod/maps") -File |
    Where-Object { $_.Name -match '^c\d+m\d+.*\.cfg$' }
foreach ($zoneMap in $zoneOfficialMaps) {
    $astMap = Join-Path $Root "cfg/stripper/amethyst/maps/$($zoneMap.Name)"
    if (-not (Test-Path -LiteralPath $astMap -PathType Leaf)) {
        Add-Failure "AstMod is missing official Stripper map: $($zoneMap.Name)"
        continue
    }
    if ((Get-FileHash -LiteralPath $zoneMap.FullName).Hash -ne (Get-FileHash -LiteralPath $astMap).Hash) {
        Add-Failure "AstMod official Stripper map differs from Zonemod: $($zoneMap.Name)"
    }
}

$cfgsPath = Join-Path $Root "addons/sourcemod/configs/cfgs.txt"
if (Select-String -LiteralPath $cfgsPath -Pattern '^\s*"exec match/' -Quiet) {
    Add-Failure "Legacy confogl_autoloader mode entries remain in cfgs.txt"
}

Assert-KeyValuesBraceBalance "addons/sourcemod/configs/matchmodes.txt"
Assert-KeyValuesBraceBalance "addons/sourcemod/configs/cfgs.txt"

if ($failures.Count -gt 0) {
    Write-Host "AstMod integration validation failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }
    exit 1
}

$activeLoads = (
    Select-String -LiteralPath $pluginLoadConfigs -Pattern $loadPattern
).Count
Write-Host "AstMod integration validation passed." -ForegroundColor Green
Write-Host "Active plugin loads checked: $activeLoads"
Write-Host "Official Stripper maps checked: $($zoneOfficialMaps.Count)"
Write-Host "Core dedicated-server runtime validation passed; interactive menus and campaign completion remain pending."
