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

foreach ($removedPath in @(
    "addons/sourcemod/scripting/astredux_autowipe.sp",
    "addons/sourcemod/scripting/astredux_challenge.sp",
    "addons/sourcemod/scripting/astredux_profile_controller.sp",
    "addons/sourcemod/scripting/astredux_rules.sp",
    "addons/sourcemod/scripting/astredux_wave_spawner.sp",
    "addons/sourcemod/scripting/challenge.sp",
    "addons/sourcemod/plugins/optional/astredux/astredux_autowipe.smx",
    "addons/sourcemod/plugins/optional/astredux/astredux_profile_controller.smx",
    "addons/sourcemod/plugins/optional/astredux/astredux_rules.smx",
    "addons/sourcemod/plugins/optional/astredux/challenge.smx",
    "addons/sourcemod/plugins/optional/astredux/wave_spawner.smx"
)) {
    if (Test-Path -LiteralPath (Join-Path $Root $removedPath)) {
        Add-Failure "Removed component path still exists: $removedPath"
    }
}

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

function Assert-NotPath {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Failure "Obsolete path still exists: $RelativePath"
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
    "addons/sourcemod/configs/missioncycle.txt",
    "addons/sourcemod/configs/vote_menu.txt",
    "addons/sourcemod/configs/advertisements.txt",
    "addons/sourcemod/configs/astredux_profiles.cfg",
    "addons/sourcemod/extensions/imatchext.autoload",
    "addons/sourcemod/extensions/imatchext.ext.2.l4d2.so",
    "addons/sourcemod/extensions/langparser.ext.2.l4d2.so",
    "addons/sourcemod/gamedata/fix_exec_config_unicode.txt",
    "addons/sourcemod/gamedata/imatchext.txt",
    "addons/sourcemod/plugins/fix_exec_config_unicode.smx",
    "addons/sourcemod/plugins/server_restart.smx",
    "addons/sourcemod/scripting/fix_exec_config_unicode.sp",
    "addons/sourcemod/scripting/server_restart.sp",
    "addons/sourcemod/scripting/include/imatchext.inc",
    "addons/sourcemod/translations/imatchext.phrases.txt",
    "addons/sourcemod/translations/chi/imatchext.phrases.txt",
    "addons/sourcemod/translations/zho/imatchext.phrases.txt",
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp",
    "addons/sourcemod/scripting/optional/coop/pause_coop.sp",
    "addons/sourcemod/plugins/optional/coop/campaign_switcher.smx",
    "addons/sourcemod/plugins/optional/coop/pause_coop.smx",
    "addons/sourcemod/scripting/optional/coop/profile_controller.sp",
    "addons/sourcemod/scripting/optional/coop/wave_spawner.sp",
    "addons/sourcemod/scripting/optional/coop/tank_health.sp",
    "addons/sourcemod/scripting/optional/coop/tank_melee_damage.sp",
    "addons/sourcemod/scripting/optional/coop/witch_control.sp",
    "addons/sourcemod/scripting/optional/coop/smg_reload_control.sp",
    "addons/sourcemod/scripting/optional/coop/autowipe.sp",
    "addons/sourcemod/scripting/optional/coop/challenge.sp",
    "addons/sourcemod/scripting/optional/coop/kill_rewards.sp",
    "addons/sourcemod/scripting/optional/coop/si_damage_control.sp",
    "addons/sourcemod/scripting/optional/coop/use_action_speed.sp",
    "addons/sourcemod/scripting/optional/coop/script_reloader.sp",
    "addons/sourcemod/scripting/optional/astmod/challenge.sp",
    "addons/sourcemod/scripting/include/script_reloader.inc",
    "addons/sourcemod/plugins/optional/coop/profile_controller.smx",
    "addons/sourcemod/plugins/optional/coop/wave_spawner.smx",
    "addons/sourcemod/plugins/optional/coop/tank_health.smx",
    "addons/sourcemod/plugins/optional/coop/tank_melee_damage.smx",
    "addons/sourcemod/plugins/optional/coop/witch_control.smx",
    "addons/sourcemod/plugins/optional/coop/smg_reload_control.smx",
    "addons/sourcemod/plugins/optional/coop/autowipe.smx",
    "addons/sourcemod/plugins/optional/coop/challenge.smx",
    "addons/sourcemod/plugins/optional/coop/kill_rewards.smx",
    "addons/sourcemod/plugins/optional/coop/si_damage_control.smx",
    "addons/sourcemod/plugins/optional/coop/use_action_speed.smx",
    "addons/sourcemod/plugins/optional/astmod/challenge.smx",
    "cfg/generalfixes.cfg",
    "cfg/competitive_shared.cfg",
    "cfg/sharedplugins.cfg",
    "cfg/stripper/astredux",
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

Assert-NotPath "cfg/stripper/astmod"

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

Assert-Contains `
    "cfg/generalfixes.cfg" `
    '^\s*sm\s+plugins\s+load\s+fix_exec_config_unicode\.smx\s*$' `
    "Unicode cfg parsing is not restored after a Confogl reload"
Assert-Contains `
    "cfg/generalfixes.cfg" `
    '^\s*sm\s+plugins\s+load\s+server_restart\.smx\s*$' `
    "server_restart.smx is not in the all-mode generalfixes chain"

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
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+optional/coop/jointeam\.smx\s*$') {
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

Assert-Contains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    '^\s*sm\s+plugins\s+load\s+optional/coop/wave_spawner\.smx\s*$' `
    "AstRedux does not load the shared Coop Wave Spawner"
foreach ($component in @('tank_health', 'tank_melee_damage', 'witch_control', 'smg_reload_control')) {
    Assert-Contains `
        "cfg/cfgogl/astredux/plugins_1.cfg" `
        "^\s*sm\s+plugins\s+load\s+optional/coop/$component\.smx\s*$" `
        "AstRedux does not load Coop component $component"
}
foreach ($component in @('kill_rewards', 'si_damage_control', 'use_action_speed')) {
    Assert-Contains "cfg/cfgogl/astredux/plugins_1.cfg" "^\s*sm\s+plugins\s+load\s+optional/coop/$component\.smx\s*$" "AstRedux does not load Coop component $component"
}
$astReduxPluginText = Get-Content -LiteralPath (Join-Path $Root "cfg/cfgogl/astredux/plugins_1.cfg") -Raw -Encoding utf8
$challengeLoadIndex = $astReduxPluginText.IndexOf('sm plugins load optional/coop/challenge.smx', [StringComparison]::Ordinal)
foreach ($component in @('kill_rewards', 'si_damage_control', 'use_action_speed')) {
    $componentLoadIndex = $astReduxPluginText.IndexOf("sm plugins load optional/coop/$component.smx", [StringComparison]::Ordinal)
    if ($componentLoadIndex -lt 0 -or $challengeLoadIndex -lt 0 -or $componentLoadIndex -gt $challengeLoadIndex) {
        Add-Failure "AstRedux does not load Coop component $component before Challenge"
    }
}
Assert-NotContains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    'astredux_rules|astredux_tank_spawn_health|astredux_tank_melee_damage|astredux_tank_engine_scale|astredux_no_witch|astredux_smg_reload_duration|astredux_smg_silenced_reload_duration' `
    "AstRedux still references the removed rules component or legacy CVar names"

foreach ($componentPath in @(
    "addons/sourcemod/scripting/optional/coop/tank_health.sp",
    "addons/sourcemod/scripting/optional/coop/tank_melee_damage.sp",
    "addons/sourcemod/scripting/optional/coop/witch_control.sp",
    "addons/sourcemod/scripting/optional/coop/smg_reload_control.sp"
)) {
    Assert-NotContains $componentPath `
        'astredux_rules|astredux_tank_spawn_health|astredux_tank_melee_damage|astredux_tank_engine_scale|astredux_no_witch|astredux_smg_reload_duration|astredux_smg_silenced_reload_duration' `
        "Coop component still contains removed rules identifiers"
}
foreach ($profileKey in @('tank_spawn_health', 'tank_melee_damage', 'witch_block', 'smg_reload_duration', 'smg_silenced_reload_duration')) {
    Assert-Contains `
        "addons/sourcemod/configs/astredux_profiles.cfg" `
        ('"' + $profileKey + '"') `
        "AstRedux profile is missing component CVar $profileKey"
}
Assert-Contains `
    "cfg/cfgogl/astredux/astredux.cfg" `
    '^\s*confogl_addcvar\s+profile_controller_config\s+"configs/astredux_profiles\.cfg"\s*$' `
    "AstRedux does not configure the generic Profile Controller"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/profile_controller.sp" `
    '(?ms)HookConVarChange\(g_cvProfileConfig,\s*OnProfileConfigChanged\).*?public void OnConfigsExecuted\(\).*?TryInitializeProfiles\(\)' `
    "Profile Controller does not defer initialization behind the externally configured CVar"
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/profile_controller.sp" `
    'SetFailState\(' `
    "Profile Controller still fails the plugin when its deferred config is unavailable"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/wave_spawner.sp" `
    '(?ms)void ResetWaveNow\(\).*?!IsServerProcessing\(\).*?FindEntityByClassname\(-1,\s*"worldspawn"\).*?CreateEntityByName\(' `
    "Wave Spawner does not guard ResetWaveNow before creating the script entity"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^sm plugins load optional/coop/profile_controller\.smx$' `
    "AstRedux does not load the generic Profile Controller"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/challenge.sp" `
    'RegAdminCmd\("sm_reset"' `
    "Coop Challenge does not expose sm_reset"
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/challenge.sp" `
    'RegAdminCmd\("sm_astreset"' `
    "Coop Challenge still exposes the old sm_astreset command"
foreach ($baseline in @(
    '"vs_tank_damage" "24"',
    '"ast_pills_enabled" "0"',
    '"ast_pills_map_kill" "0"',
    '"kill_rewards_health_enable" "0"',
    '"kill_rewards_ammo_enable" "0"',
    '"si_damage_enable" "0"',
    '"si_damage_ratio_enable" "0"',
    '"si_damage_base" "12"',
    '"ast_maxinfected" "0"',
    '"ast_allowhumantank" "0"',
    '"ai_hardsi_enable" "1"'
)) {
    Assert-Contains "addons/sourcemod/configs/astredux_profiles.cfg" $baseline "AstRedux defaults is missing baseline $baseline"
}
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/challenge.sp" `
    'SetConVarBool\(hRatioDamage|SIDamage\(12\.0\)|SetConVarInt\(FindConVar\("vs_tank_damage"\), 24\)|SetConVarBool\(hRehealth|SetConVarBool\(hReammo' `
    "Coop Challenge ResetSettings still hardcodes gameplay baselines"
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/challenge.sp" `
    'HookEvent\("(?:player_death|infected_death|player_hurt|tongue_|charger_)|SDKHook|L4D2_OnStartUseAction_Post|\b(?:giveAmmo|GiveAmmo)\s*\(' `
    "Coop Challenge still contains extracted gameplay event or hook logic"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/kill_rewards.sp" `
    'HookEvent\("player_death"' `
    "Kill Rewards does not own special-infected death rewards"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/kill_rewards.sp" `
    'HookEvent\("infected_death"' `
    "Kill Rewards does not own common-infected death rewards"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/si_damage_control.sp" `
    'SDKHook\([^\r\n]*SDKHook_OnTakeDamage' `
    "SI Damage Control does not own its damage hook"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/si_damage_control.sp" `
    'HookEvent\("tongue_pull_stopped"' `
    "SI Damage Control does not own tongue-cut handling"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/use_action_speed.sp" `
    'L4D2_OnStartUseAction_Post\(' `
    "Use Action Speed does not own the use-action hook"
Assert-NotContains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    '^\s*sm\s+plugins\s+load\s+optional/astmod/wave_spawner\.smx\s*$' `
    "AstRedux still loads the AstMod Wave Spawner"
Assert-NotContains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^\s*sm\s+plugins\s+load\s+optional/astmod/l4d2_jockey_skeet\.smx\s*$' `
    "AstRedux still loads the AstMod Jockey Skeet plugin"
foreach ($legacyPattern in @('\bWaves\b', 'update_diff_old', 'ast_wave_spawn', 'ast_sitimer(_new)?', 'ast_silimit_new')) {
    Assert-NotContains `
        "scripts/vscripts/astredux.nut" `
        $legacyPattern `
        "AstRedux VScript still contains legacy wave state: $legacyPattern"
}

foreach ($nativeCaller in @(
    "addons/sourcemod/scripting/optional/coop/wave_spawner.sp",
    "addons/sourcemod/scripting/optional/astmod/wave_spawner.sp"
)) {
    Assert-NotContains `
        $nativeCaller `
        'ServerCommand\("sm_reloadscript"\)' `
        "VScript reload caller still uses the console-command bridge"
    Assert-Contains `
        $nativeCaller `
        'VScript_Reload\(' `
        "VScript reload caller does not use the script_reloader native"
}

Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/script_reloader.sp" `
    'CreateNative\("VScript_Reload"' `
    "script_reloader does not publish its reload native"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/script_reloader.sp" `
    'GlobalForward\("VScript_OnReloaded"' `
    "script_reloader does not publish its completion forward"
Assert-Contains `
    "scripts/vscripts/astredux.nut" `
    'RandomInt\(0, limits\.len\(\) - 1\)' `
    "AstRedux does not distribute overflow slots equally across all SI classes"
Assert-NotContains `
    "scripts/vscripts/astredux.nut" `
    '\bscale\b' `
    "AstRedux still uses proportional SI limit scaling"

Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    '#include <imatchext>' `
    "Campaign Switcher does not use imatchext as its mission registry"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    'RegConsoleCmd\("sm_mapvote"' `
    "Campaign Switcher does not register sm_mapvote"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    'RegConsoleCmd\("sm_nextmap"' `
    "Campaign Switcher does not register sm_nextmap"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    'RegConsoleCmd\("sm_chaptervote"' `
    "Campaign Switcher does not register sm_chaptervote"
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    'sm_mapvotes' `
    "Campaign Switcher still exposes the retired sm_mapvotes command"
Assert-Contains `
    "addons/sourcemod/configs/vote_menu.txt" `
    '^\s*"sm_mapvote"\s*$' `
    "The flat !vote menu does not expose !mapvote"
Assert-Contains `
    "addons/sourcemod/configs/vote_menu.txt" `
    '^\s*"sm_chaptervote"\s*$' `
    "The flat !vote menu does not expose !chaptervote"
Assert-NotContains `
    "addons/sourcemod/configs/vote_menu.txt" `
    '"sm_slots"' `
    "The no-argument !slots item is still present in !vote"
Assert-NotContains `
    "addons/sourcemod/scripting/optional/coop/challenge.sp" `
    'weapon_allow_m2_hunter|推 Hunter 设定|特感加智' `
    "The supported !ast menu still contains deferred AstFlex controls"
foreach ($mode in @("astmod", "astredux", "astflex")) {
    Assert-NotContains `
        "cfg/cfgogl/$mode/$mode.cfg" `
        'weapon_allow_m2_hunter' `
        "$mode still configures a CVar not provided by the active Hunter plugin"
}
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/pause_coop.sp" `
    'CreateGlobalForward\("OnPause"' `
    "Coop pause does not publish the pause forward"
Assert-Contains `
    "addons/sourcemod/scripting/optional/coop/pause_coop.sp" `
    'CreateGlobalForward\("OnUnpause"' `
    "Coop pause does not publish the unpause forward"

foreach ($mode in @("astmod", "astredux")) {
    Assert-Contains `
        "cfg/cfgogl/$mode/plugins_1.cfg" `
        'sm plugins load optional/coop/pause_coop\.smx' `
        "$mode does not load the coop pause implementation"
    Assert-NotContains `
        "cfg/cfgogl/$mode/plugins_1.cfg" `
        'sm plugins load optional/pause\.smx' `
        "$mode still loads the generic pause implementation"
}
Assert-Contains `
    "cfg/cfgogl/astflex/plugins_1.cfg" `
    'sm plugins load optional/pause\.smx' `
    "AstFlex no longer loads the generic pause implementation"

foreach ($mode in $modes) {
    $pluginList = Join-Path $Root "cfg/cfgogl/$mode/plugins_1.cfg"
    $pluginText = Get-Content -LiteralPath $pluginList -Raw -Encoding utf8
    $reloaderIndex = $pluginText.IndexOf('sm plugins load optional/coop/script_reloader.smx', [StringComparison]::Ordinal)
    $wavePath = if ($mode -eq 'astredux') { 'optional/coop/wave_spawner.smx' } else { 'optional/astmod/wave_spawner.smx' }
    $waveIndex = $pluginText.IndexOf("sm plugins load $wavePath", [StringComparison]::Ordinal)
    if ($reloaderIndex -lt 0 -or $waveIndex -lt 0 -or $reloaderIndex -gt $waveIndex) {
        Add-Failure "$mode does not load script_reloader before its wave spawner"
    }
}

$keyValuesFiles = @(
    "addons/sourcemod/configs/matchmodes.txt",
    "addons/sourcemod/configs/missioncycle.txt",
    "addons/sourcemod/configs/vote_menu.txt",
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
