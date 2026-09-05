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
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('//') -or $trimmed.StartsWith(';')) {
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
    "addons/sourcemod/scripting/include/coop_player_manager.inc",
    "addons/sourcemod/scripting/include/profile_controller.inc",
    "addons/sourcemod/scripting/include/wave_spawner.inc",
    "addons/sourcemod/translations/imatchext.phrases.txt",
    "addons/sourcemod/translations/chi/imatchext.phrases.txt",
    "addons/sourcemod/translations/zho/imatchext.phrases.txt",
    "addons/sourcemod/translations/challenge.phrases.txt",
    "addons/sourcemod/translations/chi/challenge.phrases.txt",
    "addons/sourcemod/translations/coop_flow.phrases.txt",
    "addons/sourcemod/translations/chi/coop_flow.phrases.txt",
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp",
    "cfg/sourcemod/campaign_switcher.cfg",
    "addons/sourcemod/scripting/optional/astmod/jointeam.sp",
    "addons/sourcemod/scripting/optional/astmod/pause_coop.sp",
    "addons/sourcemod/scripting/optional/astmod/player_manager_compat.sp",
    "addons/sourcemod/scripting/optional/coop/player_manager.sp",
    "addons/sourcemod/scripting/optional/coop/ready_pause.sp",
    "addons/sourcemod/scripting/optional/coop/survivor_loadout.sp",
    "addons/sourcemod/scripting/optional/coop/admin_tools.sp",
    "addons/sourcemod/plugins/optional/coop/campaign_switcher.smx",
    "addons/sourcemod/plugins/optional/astmod/jointeam.smx",
    "addons/sourcemod/plugins/optional/astmod/pause_coop.smx",
    "addons/sourcemod/plugins/optional/astmod/player_manager_compat.smx",
    "addons/sourcemod/plugins/optional/coop/player_manager.smx",
    "addons/sourcemod/plugins/optional/coop/ready_pause.smx",
    "addons/sourcemod/plugins/optional/coop/survivor_loadout.smx",
    "addons/sourcemod/plugins/optional/coop/admin_tools.smx",
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

$requiredPaths += @(
    "cfg/cfgogl/public_coop/generalfixes.cfg",
    "cfg/cfgogl/public_coop/confogl_plugins.cfg",
    "cfg/cfgogl/public_coop/sharedplugins.cfg",
    "cfg/cfgogl/public_coop/shared_cvars.cfg",
    "cfg/cfgogl/public_coop/confogl.cfg",
    "cfg/cfgogl/public_coop/public_coop.cfg",
    "cfg/cfgogl/public_coop/confogl_off.cfg",
    "cfg/cfgogl/public_coop/mapinfo.txt"
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
    "cfg/sharedplugins.cfg",
    "cfg/cfgogl/public_coop/generalfixes.cfg",
    "cfg/cfgogl/public_coop/sharedplugins.cfg"
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

    Assert-Contains `
        "cfg/cfgogl/$mode/$mode.cfg" `
        '^\s*confogl_addcvar\s+sm_vscript_filename\s+\S+\s*$' `
        "$mode does not track its VScript filename as a match-scoped CVar"
    Assert-NotContains `
        "cfg/cfgogl/$mode/$mode.cfg" `
        '^\s*sm_cvar\s+sm_vscript_filename\b' `
        "$mode still sets its fixed VScript filename as a runtime-mutable CVar"

    $modePluginLists = 1..3 | ForEach-Object { Join-Path $Root "cfg/cfgogl/$mode/plugins_$_.cfg" }
    $modePluginParts = $modePluginLists | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding utf8 }
    $modePluginText = $modePluginParts -join "`n"
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+confoglcompmod\.smx\s*$') {
        Add-Failure "$mode does not load confoglcompmod.smx"
    }
    if ($modePluginText -notmatch '(?m)^\s*sm\s+plugins\s+load\s+match_vote\.smx\s*$') {
        Add-Failure "$mode does not load match_vote.smx"
    }
    if ($mode -eq "astmod") {
        foreach ($legacyPlugin in @("jointeam", "pause_coop")) {
            if ($modePluginText -notmatch "(?m)^\s*sm\s+plugins\s+load\s+optional/astmod/$legacyPlugin\.smx\s*`$") {
                Add-Failure "AstMod does not load its legacy $legacyPlugin.smx"
            }
        }
        foreach ($coopComponent in @("player_manager", "ready_pause", "survivor_loadout", "admin_tools")) {
            if ($modePluginText -match "(?m)^\s*sm\s+plugins\s+load\s+optional/coop/$coopComponent\.smx\s*`$") {
                Add-Failure "AstMod loads Redux/Flex component $coopComponent.smx"
            }
        }
    }
    else {
        foreach ($coopComponent in @("ready_pause", "player_manager", "survivor_loadout", "admin_tools")) {
            if ($modePluginText -notmatch "(?m)^\s*sm\s+plugins\s+load\s+optional/coop/$coopComponent\.smx\s*`$") {
                Add-Failure "$mode does not load Coop component $coopComponent.smx"
            }
        }
        foreach ($legacyLoad in @("optional/astmod/jointeam.smx", "optional/astmod/pause_coop.smx", "optional/coop/jointeam.smx", "optional/coop/pause_coop.smx", "optional/pause.smx", "optional/playermanagement.smx")) {
            if ($modePluginText -match ("(?m)^\s*sm\s+plugins\s+load\s+" + [regex]::Escape($legacyLoad) + "\s*`$")) {
                Add-Failure "$mode still loads incompatible player-flow plugin $legacyLoad"
            }
        }
    }
}

Assert-Contains "cfg/cfgogl/astflex/plugins_1.cfg" '^sm plugins load optional/astmod/player_manager_compat\.smx$' "AstFlex does not load the AstMod Challenge compatibility bridge"
Assert-NotContains "cfg/cfgogl/astredux/plugins_1.cfg" 'player_manager_compat\.smx' "AstRedux loads the AstFlex-only compatibility bridge"

$publicModeRoot = Join-Path $Root "cfg/cfgogl/public_coop"
foreach ($chunk in @("plugins_1.cfg", "plugins_2.cfg", "plugins_3.cfg", "shared_plugins.cfg")) {
    Assert-NotPath "cfg/cfgogl/public_coop/$chunk"
}
Assert-Contains "addons/sourcemod/configs/matchmodes.txt" '"public_coop"' "public_coop is not registered in matchmodes.txt"
Assert-Contains "addons/sourcemod/configs/matchmodes.txt" '"name"\s+"Public Coop - 纯净战役"' "public_coop display name is missing"
Assert-Contains "cfg/server.cfg" '^sm_cvar\s+confogl_match_autoload\s+"1"' "Server startup does not enable Confogl autoload"
Assert-Contains "cfg/server.cfg" '^sm_cvar\s+confogl_match_autoconfig\s+"public_coop"' "Server startup does not select public_coop for autoload"
Assert-Contains "addons/sourcemod/scripting/confoglcompmod/ReqMatch.sp" 'CreateConVarEx\("match_unload_when_empty",\s*"1"' "ReqMatch does not default to unloading match modes while empty"
Assert-Contains "addons/sourcemod/scripting/confoglcompmod/ReqMatch.sp" 'RM_hUnloadWhenEmpty\.BoolValue' "ReqMatch does not recheck match_unload_when_empty"
Assert-RawContains "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" 'CreateConVar\(\s*"campaign_empty_matchmode"' "Campaign Switcher does not expose the empty-server matchmode"
Assert-Contains "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" 'CommandExists\("sm_forcechangematch"\)' "Campaign Switcher does not check sm_forcechangematch availability"
Assert-Contains "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" 'ServerCommand\("sm_forcechangematch %s %s"' "Campaign Switcher does not load the configured matchmode before changing map"
Assert-Contains "cfg/sourcemod/campaign_switcher.cfg" '^campaign_empty_matchmode\s+"public_coop"' "Campaign Switcher config does not select public_coop"
Assert-Contains "cfg/cfgogl/public_coop/shared_cvars.cfg" '^confogl_addcvar\s+confogl_match_unload_when_empty\s+0' "public_coop does not track and reset its empty-server lifecycle override"
Assert-Contains "cfg/cfgogl/public_coop/shared_cvars.cfg" '^confogl_addcvar\s+mp_gamemode\s+coop' "public_coop does not use Coop"
Assert-Contains "cfg/cfgogl/public_coop/shared_cvars.cfg" '^confogl_addcvar\s+sv_gravity\s+800' "public_coop does not restore vanilla gravity"
Assert-Contains "cfg/cfgogl/public_coop/public_coop.cfg" '^confogl_setcvars\s*$' "public_coop registers CVar overrides but never applies them"
Assert-RawContains "cfg/cfgogl/public_coop/mapinfo.txt" '^\s*"MapInfo"\s*\{' "public_coop mapinfo does not use the empty MapInfo object"

foreach ($disabledConfoglCvar in @(
    "confogl_boss_tank", "confogl_remove_escape_tank", "confogl_disable_tank_hordes", "confogl_block_punch_rock",
    "confogl_blockinfectedbots", "confogl_lock_boss_spawns", "confogl_reduce_finalespawnrange", "confogl_waterslowdown",
    "confogl_SM_enable", "confogl_enable_itemtracking", "confogl_replace_cssweapons", "confogl_remove_grenade",
    "confogl_remove_chainsaw", "confogl_remove_m60", "confogl_remove_statickits", "confogl_remove_defib",
    "confogl_remove_upg_explosive", "confogl_remove_upg_incendiary", "confogl_replace_tier2",
    "confogl_replace_tier2_finale", "confogl_replace_tier2_all", "confogl_limit_tier2",
    "confogl_limit_tier2_saferoom", "confogl_replace_startkits", "confogl_replace_finalekits",
    "confogl_remove_lasersight", "confogl_remove_saferoomitems"
)) {
    Assert-Contains `
        "cfg/cfgogl/public_coop/shared_cvars.cfg" `
        ("^confogl_addcvar\s+" + [regex]::Escape($disabledConfoglCvar) + "\s+0$") `
        "public_coop does not disable Confogl gameplay CVar $disabledConfoglCvar"
}

$publicGeneralFixes = "cfg/cfgogl/public_coop/generalfixes.cfg"
foreach ($requiredPlugin in @(
    "basebans.smx", "basecommands.smx", "basecomm.smx", "admin-flatfile.smx", "adminhelp.smx", "adminmenu.smx", "playercommands.smx",
    "left4dhooks.smx", "optional/predictable_unloader.smx", "fix_exec_config_unicode.smx", "server_restart.smx", "fixes/command_buffer.smx",
    "fixes/l4d_fix_deathfall_cam.smx", "fixes/l4d2_hltv_crash_fix.smx", "fixes/l4d2_null_cusercmd_fix.smx", "fixes/l4d2_fix_changelevel.smx"
)) {
    Assert-Contains $publicGeneralFixes ("^\s*sm\s+plugins\s+load\s+" + [regex]::Escape($requiredPlugin) + "\s*$") "public_coop generalfixes is missing $requiredPlugin"
}

$publicPluginText = Get-Content -LiteralPath (Join-Path $Root "cfg/cfgogl/public_coop/confogl_plugins.cfg") -Raw -Encoding utf8
Assert-Contains "cfg/cfgogl/public_coop/confogl_plugins.cfg" '^\s*sm\s+plugins\s+load\s+optional/l4d_cutscene_nodamage\.smx\s*$' "public_coop does not load cutscene no-damage protection"
Assert-Contains "cfg/cfgogl/public_coop/confogl_plugins.cfg" '^\s*sm\s+plugins\s+load\s+optional/coop/campaign_switcher\.smx\s*$' "public_coop does not load Campaign Switcher"
Assert-Contains "cfg/cfgogl/public_coop/confogl_plugins.cfg" '^\s*sm\s+plugins\s+load\s+confoglcompmod\.smx\s*$' "public_coop does not load confoglcompmod"
foreach ($forbiddenPublicPlugin in @("match_vote", "jointeam", "profile", "pause", "astmod", "astredux", "astflex", "vscript", "stripper")) {
    if ($publicPluginText -match $forbiddenPublicPlugin) {
        Add-Failure "public_coop loads forbidden plugin or Ast path: $forbiddenPublicPlugin"
    }
}
foreach ($forbiddenPublicPath in @("vscript", "stripper", "astmod", "astredux", "astflex")) {
    foreach ($match in Get-ChildItem -LiteralPath $publicModeRoot -File | Select-String -Pattern $forbiddenPublicPath) {
        Add-Failure "public_coop contains forbidden path $forbiddenPublicPath ($([System.IO.Path]::GetRelativePath($Root, $match.Path)):$($match.LineNumber))"
    }
}
$publicPluginAllowlist = @(
    "basebans.smx", "basecommands.smx", "basecomm.smx", "admin-flatfile.smx", "adminhelp.smx", "adminmenu.smx", "playercommands.smx",
    "left4dhooks.smx", "optional/predictable_unloader.smx", "fix_exec_config_unicode.smx", "server_restart.smx", "fixes/command_buffer.smx",
    "fixes/l4d_fix_deathfall_cam.smx", "fixes/l4d2_hltv_crash_fix.smx", "fixes/l4d2_null_cusercmd_fix.smx", "fixes/l4d2_fix_changelevel.smx",
    "optional/l4d_cutscene_nodamage.smx", "optional/coop/campaign_switcher.smx", "confoglcompmod.smx"
)
$publicLoads = @(
    Get-Content -LiteralPath (Join-Path $Root $publicGeneralFixes) -Encoding utf8
    Get-Content -LiteralPath (Join-Path $Root "cfg/cfgogl/public_coop/confogl_plugins.cfg") -Encoding utf8
) | ForEach-Object {
    if ($_ -match '^\s*sm\s+plugins\s+load\s+([^\s]+)\s*$') { $Matches[1] }
}
foreach ($publicLoad in $publicLoads) {
    if ($publicLoad -notin $publicPluginAllowlist) {
        Add-Failure "public_coop plugin is outside its allowlist: $publicLoad"
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
foreach ($waveProfileKey in @('wave_interval', 'wave_size', 'wave_hunter_limit', 'wave_smoker_limit', 'wave_boomer_limit', 'wave_spitter_limit', 'wave_jockey_limit', 'wave_charger_limit', 'wave_preferred_direction')) {
    Assert-Contains "addons/sourcemod/configs/astredux_profiles.cfg" ('"' + $waveProfileKey + '"') "AstRedux profile is missing direct Wave field $waveProfileKey"
}
Assert-NotContains "addons/sourcemod/configs/astredux_profiles.cfg" 'wave_default_(?:interval|size)' "AstRedux profile still uses obsolete Wave default keys"
Assert-RawContains "addons/sourcemod/scripting/optional/coop/profile_controller.sp" '(?ms)for \(int index = 0; index < cvarNames\.Length.*?Call_StartForward\(g_fwdProfilePreApply\)' "Profile pre-apply forward is not after CVar validation"
Assert-Contains "addons/sourcemod/scripting/optional/coop/profile_controller.sp" 'CreateNative\("ProfileController_GetCurrentProfile"' "Profile Controller does not expose current profile native"
Assert-Contains "addons/sourcemod/scripting/optional/coop/profile_controller.sp" 'CreateNative\("ProfileController_Reapply"' "Profile Controller does not expose synchronous reapply native"
Assert-Contains "addons/sourcemod/scripting/optional/coop/wave_spawner.sp" 'g_iSlotOverrideMask' "Wave Spawner does not maintain per-slot field masks"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'g_iPendingSlot' "Coop Challenge does not bind pending votes to profile slots"
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
Assert-Path "addons/sourcemod/scripting/optional/coop/mob_interval_limit.sp"
Assert-Path "addons/sourcemod/plugins/optional/coop/mob_interval_limit.smx"
Assert-Contains "addons/sourcemod/scripting/optional/coop/mob_interval_limit.sp" 'CreateConVar\("mob_spawn_limit_enabled",\s*"0"' "Mob limit default is not 0"
Assert-Contains "addons/sourcemod/scripting/optional/coop/mob_interval_limit.sp" 'if\s*\(!hMobLimitEnabled\.BoolValue\)\s*return\s+Plugin_Continue' "Mob limit hook does not gate disabled state"
Assert-Contains "cfg/cfgogl/astredux/astredux.cfg" '^\s*confogl_addcvar\s+mob_spawn_limit_enabled\s+0\s*$' "AstRedux does not configure mob limit default"
foreach ($legacyMode in @('astmod', 'astflex')) {
    Assert-Contains "cfg/cfgogl/$legacyMode/$legacyMode.cfg" '^\s*confogl_addcvar\s+mob_spawn_limit_enabled\s+1\s*$' "$legacyMode does not preserve the legacy mob limit behavior"
}
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'mob_limit' "Coop Challenge does not expose mob_limit menu item"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" '有限尸潮' "Coop Challenge does not name the mob limit toggle"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'TZ_CallVote\(client,\s*16' "Coop Challenge does not use target 16 for mob limit"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'g_iSlotOverrideMask\[slot\]' "Coop Challenge does not reapply per-profile overrides"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'pendingMobLimit\s*=\s*-1' "Coop Challenge does not clear pending mob limit votes"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'RegConsoleCmd\("sm_info"' "Coop Challenge does not expose sm_info"
Assert-Contains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'PrintOverrideDetails' "Coop Challenge info does not enumerate current overrides"
Assert-Contains "addons/sourcemod/scripting/include/wave_spawner.inc" 'WAVE_FIELD_INTERVAL' "Wave field mask constants are missing"
Assert-Contains "addons/sourcemod/scripting/optional/coop/wave_spawner.sp" 'CreateNative\("WaveSpawner_GetCurrentOverrideMask"' "Wave Spawner does not expose current override mask"
Assert-Contains "addons/sourcemod/translations/challenge.phrases.txt" 'InfoHeader' "Challenge info phrases are missing"
Assert-Contains "addons/sourcemod/translations/chi/challenge.phrases.txt" 'InfoHeader' "Chinese Challenge info phrases are missing"
foreach ($phraseFile in @(
    "addons/sourcemod/translations/challenge.phrases.txt",
    "addons/sourcemod/translations/chi/challenge.phrases.txt",
    "addons/sourcemod/translations/coop_flow.phrases.txt",
    "addons/sourcemod/translations/chi/coop_flow.phrases.txt"
)) {
    Assert-NotContains $phraseFile '^\s*"[^"]+"\s*\{\s+"' "Translation file uses an inline phrase section that SourceMod cannot parse: $phraseFile"
    Assert-NotContains $phraseFile '"#format"\s+"[^"]*\}\s+\{' "Translation #format placeholders are not comma-separated: $phraseFile"
}
Assert-RawContains "addons/sourcemod/scripting/optional/coop/wave_spawner.sp" '(?ms)#include <script_reloader>\s*#undef REQUIRE_PLUGIN\s*#include <profile_controller>' "Wave Spawner makes the late-loaded Profile Controller a hard dependency"
Assert-RawContains "addons/sourcemod/scripting/optional/coop/challenge.sp" '(?ms)#undef REQUIRE_PLUGIN\s*#include <profile_controller>\s*#include <wave_spawner>' "Coop Challenge does not mark its late/optional component natives optional"
Assert-Contains "addons/sourcemod/configs/astredux_profiles.cfg" '^\s*"mob_spawn_limit_enabled"\s+"0"\s*$' "AstRedux profile defaults do not reset mob limit"
Assert-NotContains "addons/sourcemod/scripting/optional/coop/challenge.sp" 'ResetConVar\(mobLimit|mobLimit\.(?:IntValue|BoolValue)\s*=\s*0' "Coop Challenge hardcodes the mob limit baseline"
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
    '"coop_player_infected_limit" "0"',
    '"coop_player_allow_human_tank" "0"',
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
    '^\s*sm\s+plugins\s+load\s+optional/(?:[^/\s]+/)*l4d2_jockey_skeet\.smx\s*$' `
    "AstRedux still loads a Jockey Skeet plugin"
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
    'if \(limit > 0\) eligible\.append' `
    "AstRedux does not restrict overflow slots to eligible SI classes"
Assert-Contains `
    "scripts/vscripts/astredux.nut" `
    'Fisher-Yates|order\.len\(\) - 1' `
    "AstRedux does not shuffle eligible overflow slots without replacement"
Assert-RawContains `
    "scripts/vscripts/astredux.nut" `
    '(?ms)function InitHUD\(\).*?if \(!\("HUD_TICKER" in this\)\) return;' `
    "AstRedux HUD refresh does not tolerate pre-scriptedmode reloads"
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
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    'CreateConVar\(\s*"campaign_empty_switch_delay"[\s\S]*?true,\s*1\.0' `
    "Campaign Switcher does not enforce its minimum empty-server delay"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    '(?ms)public void OnClientDisconnect_Post\(int client\).*?CountConnectedHumans\(\).*?g_emptyServerTimer != null.*?CreateTimer\(' `
    "Campaign Switcher does not schedule the empty-server transition from the last human disconnect"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    '(?ms)public Action Timer_ChangeToEmptyServerMap\(Handle timer\).*?CountConnectedHumans\(\).*?SelectRandomOfficialMap\(\).*?ForceChangeLevel\(' `
    "Campaign Switcher does not recheck emptiness before selecting an official campaign"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    '(?ms)public void OnClientConnected\(int client\).*?if\s*\(IsFakeClient\(client\)\).*?return;.*?CancelEmptyServerTimer\(\)' `
    "Campaign Switcher does not cancel the empty-server transition for a connecting human"
Assert-RawContains `
    "addons/sourcemod/scripting/optional/coop/campaign_switcher.sp" `
    '(?ms)int CountConnectedHumans\(\).*?IsClientConnected\(client\).*?!IsFakeClient\(client\)' `
    "Campaign Switcher does not count connected non-fake clients"
Assert-Contains `
    "cfg/sourcemod/campaign_switcher.cfg" `
    '^campaign_empty_switch_delay\s+"15\.0"\s*$' `
    "Campaign Switcher config does not set the documented default delay"
Assert-Contains `
    "cfg/server.cfg" `
    '^sv_hibernate_when_empty\s+"0"' `
    "Global server config does not keep empty-server timers advancing"
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
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'GlobalForward\("OnPause"' "Coop ready/pause does not publish the pause forward"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'GlobalForward\("OnUnpause"' "Coop ready/pause does not publish the unpause forward"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'RegPluginLibrary\("readyup"\)' "Coop ready/pause does not own the readyup library"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'RegPluginLibrary\("pause"\)' "Coop ready/pause does not own the pause library"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'CreateConVar\("coop_ready_enabled",\s*"1"' "Coop ready gate is not enabled by default"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'CreateConVar\("coop_pause_enabled",\s*"1"' "Coop pause is not enabled by default"
Assert-Contains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" 'if \(!g_readyEnabled\.BoolValue\) return Plugin_Continue' "Disabling the ready gate still blocks saferoom exit"
Assert-RawContains "addons/sourcemod/scripting/optional/coop/ready_pause.sp" '(?ms)void BeginReadyPhase\(\).*?g_readyPhase\s*=\s*true.*?g_countdownFinished\s*=\s*!g_readyEnabled\.BoolValue' "Ready-disabled mode does not preserve the pre-live lifecycle"

Assert-Contains "addons/sourcemod/scripting/optional/coop/player_manager.sp" 'AuthId_SteamID64' "Player Manager reservations do not use SteamID64"
Assert-Contains "addons/sourcemod/scripting/optional/coop/player_manager.sp" 'GetTime\(\)' "Player Manager reservations do not use wall-clock expiry"
Assert-Contains "addons/sourcemod/scripting/optional/coop/player_manager.sp" 'g_reservationGeneration' "Player Manager reservations do not track map generation"
Assert-Contains "addons/sourcemod/scripting/optional/coop/player_manager.sp" 'g_requestToken' "Player Manager delayed team requests are not invalidatable"
Assert-NotContains "addons/sourcemod/scripting/optional/coop/player_manager.sp" '\bGetGameTime\(' "Player Manager uses map-relative time for reservations"
Assert-Contains "addons/sourcemod/scripting/optional/coop/survivor_loadout.sp" 'CreateConVar\("coop_loadout_start_pills",\s*"1"' "Survivor Loadout does not expose starting pills"
Assert-Contains "addons/sourcemod/scripting/optional/coop/admin_tools.sp" 'RegAdminCmd\("sm_fuck"' "Coop Admin Tools does not own !fuck"
Assert-Contains "addons/sourcemod/scripting/optional/coop/admin_tools.sp" 'CleanupAiSpecialInfected\(' "Coop Admin Tools does not isolate its AI SI cleanup action"
Assert-NotPath "addons/sourcemod/scripting/optional/coop/si_cleanup.sp"
Assert-NotPath "addons/sourcemod/plugins/optional/coop/si_cleanup.smx"
Assert-NotPath "addons/sourcemod/scripting/optional/coop/jointeam.sp"
Assert-NotPath "addons/sourcemod/plugins/optional/coop/jointeam.smx"
Assert-NotPath "addons/sourcemod/scripting/optional/coop/pause_coop.sp"
Assert-NotPath "addons/sourcemod/plugins/optional/coop/pause_coop.smx"

foreach ($mode in @("astredux", "astflex")) {
    Assert-NotContains "cfg/cfgogl/$mode/$mode.cfg" '\bast_smacwelcome\b' "$mode still configures the AstMod-only fake SMAC welcome"
    Assert-Contains "cfg/cfgogl/$mode/$mode.cfg" '^\s*confogl_addcvar\s+coop_ready_enabled\s+1\s*$' "$mode does not enable the Coop ready lifecycle"
    Assert-Contains "cfg/cfgogl/$mode/$mode.cfg" '^\s*confogl_addcvar\s+coop_pause_enabled\s+1\s*$' "$mode does not enable Coop pause"
    Assert-Contains "cfg/cfgogl/$mode/$mode.cfg" '^\s*confogl_addcvar\s+coop_loadout_start_pills\s+1\s*$' "$mode does not preserve starting pills"
}

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
