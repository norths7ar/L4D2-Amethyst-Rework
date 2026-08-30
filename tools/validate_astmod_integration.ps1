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

function Get-KeyValuesSectionContent {
    param(
        [string]$RelativePath,
        [string]$SectionName
    )

    $path = Join-Path $Root $RelativePath
    $lines = Get-Content -LiteralPath $path -Encoding utf8
    $sectionPattern = '^\s*"' + [regex]::Escape($SectionName) + '"\s*$'
    $sectionLine = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match $sectionPattern) {
            $sectionLine = $index
            break
        }
    }
    if ($sectionLine -lt 0) {
        return $null
    }

    $depth = 0
    $opened = $false
    $content = [System.Collections.Generic.List[string]]::new()
    for ($index = $sectionLine + 1; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $depth += ([regex]::Matches($line, '\{')).Count
        if ($depth -gt 0) {
            $opened = $true
        }
        $depth -= ([regex]::Matches($line, '\}')).Count
        $content.Add($line)
        if ($opened -and $depth -eq 0) {
            return $content -join "`n"
        }
    }
    return $null
}

$requiredPaths = @(
    "addons/astmod.vpk",
    "assets/astmod_vpk/addoninfo.txt",
    "assets/astmod_vpk/scripts/gamemodes.txt",
    "addons/sourcemod/configs/cfgs.txt",
    "addons/sourcemod/configs/astredux_profiles.cfg",
    "addons/sourcemod/plugins/optional/pause.smx",
    "addons/sourcemod/plugins/optional/astmod/versus_coop_mode.smx",
    "addons/sourcemod/plugins/optional/astmod/wave_spawner.smx",
    "addons/sourcemod/plugins/optional/astmod/ACS.smx",
    "addons/sourcemod/plugins/optional/astmod/vote.smx",
    "addons/sourcemod/plugins/optional/astmod/sceneprocessor.smx",
    "addons/sourcemod/plugins/optional/astredux/astredux_profile_controller.smx",
    "addons/sourcemod/plugins/optional/astredux/astredux_autowipe.smx",
    "addons/sourcemod/plugins/optional/astredux/challenge.smx",
    "addons/sourcemod/scripting/ACS.sp",
    "addons/sourcemod/scripting/AI_HardSI.sp",
    "addons/sourcemod/scripting/challenge.sp",
    "addons/sourcemod/scripting/pause.sp",
    "addons/sourcemod/scripting/wave_spawner.sp",
    "addons/sourcemod/scripting/astredux_challenge.sp",
    "addons/sourcemod/scripting/astredux_autowipe.sp",
    "addons/sourcemod/scripting/astredux_profile_controller.sp",
    "addons/sourcemod/scripting/vote.sp",
    "cfg/cfgogl/astmod/astmod.cfg",
    "cfg/cfgogl/astmod/confogl.cfg",
    "cfg/cfgogl/astmod/confogl_off.cfg",
    "cfg/cfgogl/astmod/confogl_plugins.cfg",
    "cfg/cfgogl/astmod/plugins_1.cfg",
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astmod/plugins_3.cfg",
    "cfg/cfgogl/astmod/mapinfo.txt",
    "cfg/cfgogl/astmod/shared_cvars.cfg",
    "cfg/cfgogl/astredux/astredux.cfg",
    "cfg/cfgogl/astredux/confogl.cfg",
    "cfg/cfgogl/astredux/confogl_off.cfg",
    "cfg/cfgogl/astredux/confogl_plugins.cfg",
    "cfg/cfgogl/astredux/mapinfo.txt",
    "cfg/cfgogl/astredux/plugins_1.cfg",
    "cfg/cfgogl/astredux/plugins_2.cfg",
    "cfg/cfgogl/astredux/plugins_3.cfg",
    "cfg/cfgogl/astredux/shared_cvars.cfg",
    "cfg/cfgogl/astflex/astflex.cfg",
    "cfg/cfgogl/astflex/confogl.cfg",
    "cfg/cfgogl/astflex/confogl_off.cfg",
    "cfg/cfgogl/astflex/confogl_plugins.cfg",
    "cfg/cfgogl/astflex/mapinfo.txt",
    "cfg/cfgogl/astflex/plugins_1.cfg",
    "cfg/cfgogl/astflex/plugins_2.cfg",
    "cfg/cfgogl/astflex/plugins_3.cfg",
    "cfg/cfgogl/astflex/shared_cvars.cfg",
    "cfg/competitive_shared.cfg",
    "cfg/generalfixes.cfg",
    "cfg/astmod_test.cfg",
    "cfg/sourcemod/difficulty_adjustment_system",
    "cfg/sourcemod/difficulty_adjustment_system/easy_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/normal_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/hard_lite.cfg",
    "cfg/sourcemod/difficulty_adjustment_system/impossible_lite.cfg",
    "cfg/stripper/astmod",
    "scripts/vscripts/astmod.nut",
    "scripts/vscripts/astredux.nut",
    "tools/build_astmod_vpk.ps1"
)

foreach ($relativePath in $requiredPaths) {
    Assert-Path $relativePath
}

$pluginLoadConfigRelatives = @(
    "cfg/cfgogl/astmod/plugins_1.cfg",
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astmod/plugins_3.cfg",
    "cfg/cfgogl/astredux/plugins_1.cfg",
    "cfg/cfgogl/astredux/plugins_2.cfg",
    "cfg/cfgogl/astredux/plugins_3.cfg",
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

if (Test-Path -LiteralPath (Join-Path $Root "addons/sourcemod/plugins/optional/astmod/clip_removal.smx")) {
    Add-Failure "Retired clip_removal.smx binary still exists"
}

foreach ($pluginConfig in @(
    "cfg/cfgogl/astmod/plugins_2.cfg",
    "cfg/cfgogl/astredux/plugins_2.cfg",
    "cfg/cfgogl/astflex/plugins_2.cfg"
)) {
    Assert-NotContains `
        $pluginConfig `
        'clip_removal\.smx' `
        "Retired clip_removal.smx reference still exists"
    Assert-NotContains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/astmod/l4d2_smg_reload_tweak\.smx\s*$' `
        "AstMod SMG reload plugin would override the Zonemod weapon values"
    Assert-NotContains `
        $pluginConfig `
        '^\s*sm plugins load\s+optional/astmod/l4d2_(weapon_attributes|static_shotgun_spread)\.smx\s*$' `
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
    "cfg/cfgogl/astmod/astmod.cfg",
    "cfg/cfgogl/astredux/astredux.cfg",
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
$modeConfigPaths = @("astmod", "astredux", "astflex") | ForEach-Object { Join-Path $Root "cfg/cfgogl/$_" }
$forbidden = Get-ChildItem -LiteralPath $modeConfigPaths -Filter "*.cfg" |
    Select-String -Pattern $forbiddenPattern
foreach ($match in $forbidden) {
    Add-Failure "Forbidden lifecycle command at $($match.Path):$($match.LineNumber)"
}

$competitiveOnlyPlugins = @(
    "optional/playermanagement.smx",
    "optional/l4d2_tank_props_glow.smx",
    "fixes/l4d2_shadow_removal.smx",
    "optional/nodeathcamskip.smx",
    "optional/l4d2_map_transitions.smx",
    "fixes/l4d2_fix_firsthit.smx",
    "fixes/annoyance_exploit_fixes.smx",
    "fixes/l4d2_fix_team_shuffle.smx",
    "fixes/l4d2_tank_spawn_antirock_protect.smx",
    "optional/l4d2_block_autoaim.smx",
    "anticheat/l4d2_noghostcheat.smx"
)
foreach ($plugin in $competitiveOnlyPlugins) {
    $escaped = [regex]::Escape($plugin)
    Assert-NotContains "cfg/generalfixes.cfg" $escaped "Competitive-only plugin remains in generalfixes: $plugin"
    Assert-Contains "cfg/competitive_shared.cfg" ('^\s*sm plugins load ' + $escaped + '\s*$') "Competitive shared layer is missing: $plugin"
}

Assert-Contains "cfg/generalfixes.cfg" '^\s*sm plugins load fixes/l4d_skip_intro\.smx\s*$' "General fixes layer is missing l4d_skip_intro.smx"
Assert-NotContains "cfg/competitive_shared.cfg" 'fixes/l4d_skip_intro\.smx' "l4d_skip_intro.smx is still duplicated in competitive_shared.cfg"

$competitiveModeConfigs = @(
    "cfg/cfgogl/acemodrv/shared_plugins.cfg",
    "cfg/cfgogl/apex/shared_plugins.cfg",
    "cfg/cfgogl/eq/shared_plugins.cfg",
    "cfg/cfgogl/neomod/shared_plugins.cfg",
    "cfg/cfgogl/nextmod/shared_plugins.cfg",
    "cfg/cfgogl/zonehunters/shared_plugins.cfg",
    "cfg/cfgogl/zonemod/shared_plugins.cfg",
    "cfg/cfgogl/zoneretro/shared_plugins.cfg",
    "cfg/cfgogl/deadman/confogl_plugins.cfg",
    "cfg/cfgogl/pmelite/confogl_plugins.cfg"
)
foreach ($config in $competitiveModeConfigs) {
    Assert-Contains $config '^\s*exec competitive_shared\.cfg\s*$' "Competitive mode does not load competitive_shared.cfg"
}

foreach ($mode in @("astmod", "astredux", "astflex")) {
    $pluginConfig = "cfg/cfgogl/$mode/plugins_1.cfg"
    Assert-Contains $pluginConfig '^\s*sm plugins load optional/astmod/jointeam\.smx\s*$' "Ast mode does not load jointeam"
    Assert-NotContains $pluginConfig 'playermanagement|hostname\.smx|l4d2_storm\.smx|optional/astmod/(pause|slots_vote|specrates|lerpmonitor|l4d_boss_vote)\.smx' "Ast mode loads a conflicting or obsolete private functional plugin"
    foreach ($sharedPlugin in @("lerpmonitor", "slots_vote", "specrates", "pause", "l4d_boss_vote")) {
        Assert-Contains $pluginConfig ('^\s*sm plugins load optional/' + $sharedPlugin + '\.smx\s*$') "Ast mode does not use the shared $sharedPlugin plugin"
    }
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
    "addons/sourcemod/configs/matchmodes.txt" `
    '^\s*"astredux"\s*$' `
    "AstRedux is not registered in matchmodes.txt"
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
    "cfg/cfgogl/astredux/confogl_off.cfg" `
    '^\s*pred_unload_plugins\s*$' `
    "AstRedux does not use predictable unloading"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^\s*sm plugins load confoglcompmod\.smx\s*$' `
    "AstRedux does not reload Competitive Rework Confogl"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^\s*sm plugins load match_vote\.smx\s*$' `
    "AstRedux does not reload the Competitive Rework match vote"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^\s*sm plugins load optional/astredux/astredux_profile_controller\.smx\s*$' `
    "AstRedux does not load its declarative profile controller"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    '^\s*sm plugins load optional/astredux/astredux_autowipe\.smx\s*$' `
    "AstRedux does not load its profile-controlled AutoWipe adapter"
Assert-Contains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    '^\s*sm plugins load optional/astredux/challenge\.smx\s*$' `
    "AstRedux does not load its profile-aware challenge build"
Assert-RawContains `
    "cfg/cfgogl/astredux/plugins_1.cfg" `
    '(?s)sm plugins load optional/astmod/wave_spawner\.smx.*?sm plugins load optional/astredux/challenge\.smx' `
    "AstRedux does not load wave_spawner before challenge"
foreach ($waveConfig in @(
    @{ Path = "cfg/cfgogl/astmod/plugins_1.cfg"; Challenge = "optional/astmod/challenge.smx" },
    @{ Path = "cfg/cfgogl/astredux/plugins_1.cfg"; Challenge = "optional/astredux/challenge.smx" },
    @{ Path = "cfg/cfgogl/astflex/plugins_1.cfg"; Challenge = "optional/astmod/challenge.smx" }
)) {
    Assert-RawContains `
        $waveConfig.Path `
        ('(?s)sm plugins load optional/astmod/wave_spawner\.smx.*?sm plugins load ' + [regex]::Escape($waveConfig.Challenge)) `
        "Ast mode does not load the common Wave Spawner before Challenge"
}
if (Test-Path -LiteralPath (Join-Path $Root "addons/sourcemod/scripting/astredux_wave_spawner.sp")) {
    Add-Failure "Obsolete AstRedux-specific Wave Spawner source still exists"
}
if (Test-Path -LiteralPath (Join-Path $Root "addons/sourcemod/plugins/optional/astredux/wave_spawner.smx")) {
    Add-Failure "Obsolete AstRedux-specific Wave Spawner binary still exists"
}
Assert-NotContains `
    "cfg/cfgogl/astredux/plugins_3.cfg" `
    '^\s*sm plugins load optional/astmod/difficulty_adjustment_system\.smx\s*$' `
    "AstRedux still loads the legacy AstMod DAS"
Assert-NotContains `
    "cfg/cfgogl/astredux/astredux.cfg" `
    '^\s*sm_weapon\s+melee\s+tankdamagemult\s+' `
    "AstRedux still delegates Tank melee damage to concrete weapon-attribute enumeration"
Assert-Contains `
    "cfg/cfgogl/astredux/astredux.cfg" `
    '^\s*confogl_addcvar l4d2_melee_damage_tank_nerf 0\s+' `
    "AstRedux does not disable the globally loaded melee damage nerf"
Assert-Contains `
    "cfg/cfgogl/astredux/shared_cvars.cfg" `
    '^\s*confogl_addcvar mp_gamemode "astredux"\s*$' `
    "AstRedux does not select its dedicated mutation"
Assert-Contains `
    "cfg/cfgogl/astredux/shared_cvars.cfg" `
    '^\s*confogl_addcvar stripper_cfg_path cfg/stripper/astmod\s*$' `
    "AstRedux scaffold does not explicitly reuse the Baseline Stripper tree"

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
    "cfg/cfgogl/astmod/astmod.cfg" `
    '^\s*sm_cvar ai_hardsi_enable 1\s*$' `
    "AstMod does not restore Hard SI AI to on"
Assert-Contains `
    "cfg/cfgogl/astredux/astredux.cfg" `
    '^\s*sm_cvar sm_vscript_filename astredux\.nut\s*$' `
    "AstRedux does not select its independent VScript"
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
    "The Ast gameplay menu does not expose the Hard SI AI vote"
Assert-Contains `
    "addons/sourcemod/configs/cfgs.txt" `
    '^\s*"sm_ast"\s*$' `
    "The !vote menu does not route to !ast"
Assert-RawContains `
    "addons/sourcemod/scripting/pause.sp" `
    '(?s)version = "6\.9\.0".*?RegConsoleCmd\("sm_p".*?RegConsoleCmd\("sm_pausepanel".*?CreateTimer\(0\.1, Pause_Timer' `
    "The shared Pause source does not contain the agreed Rework 6.9 and AstMod command merge"
Assert-Contains `
    "scripts/vscripts/astmod.nut" `
    'if \("update_diff" in g_ModeScript\)' `
    "The AstMod VScript does not guard its mode-switch reload callback"
Assert-Contains `
    "scripts/vscripts/astredux.nut" `
    'if \("update_diff" in g_ModeScript\)' `
    "The AstRedux VScript does not guard its mode-switch reload callback"
Assert-Contains `
    "scripts/vscripts/astredux.nut" `
    'Convars\.GetStr\("astredux_si_hunter_limit"\)' `
    "The AstRedux VScript does not consume the declarative SI composition"
Assert-NotContains `
    "scripts/vscripts/astredux.nut" `
    'das_fakedifficulty' `
    "The AstRedux VScript still depends on the legacy fake difficulty cvar"
Assert-RawContains `
    "scripts/vscripts/astredux.nut" `
    '(?s)function update_diff_old\(\).*?astredux_si_hunter_limit.*?astredux_si_preferred_direction' `
    "The AstRedux old-wave path does not reuse the declarative SI composition"
Assert-Contains "addons/sourcemod/scripting/wave_spawner.sp" 'CreateConVar\("ast_wave_override_active"' "The common Wave Spawner does not expose temporary override state"
Assert-Contains "addons/sourcemod/scripting/wave_spawner.sp" 'RegConsoleCmd\("sm_si"' "The common Wave Spawner does not own !si"
Assert-Contains "addons/sourcemod/scripting/wave_spawner.sp" 'SITimerNewVoteResultHandler' "The common Wave Spawner does not own the wave vote result"
Assert-NotContains `
    "addons/sourcemod/scripting/challenge.sp" `
    'CreateConVar\("ast_(wave_spawn|sitimer_new|silimit_new)"|RegConsoleCmd\("sm_si"' `
    "Challenge still duplicates Wave Spawner cvars or the !si command"
Assert-Contains `
    "addons/sourcemod/scripting/challenge.sp" `
    'RegConsoleCmd\("sm_ast"' `
    "Challenge does not expose the !ast gameplay entry"
Assert-Contains `
    "addons/sourcemod/scripting/challenge.sp" `
    'RegAdminCmd\("sm_astreset"' `
    "Challenge does not expose the admin reset command"
Assert-RawContains `
    "addons/sourcemod/scripting/challenge.sp" `
    '(?s)public Action OnInfectedDeath.*?isSurvivor\(attacker\).*?iKillCI\[attacker\]\+\+.*?iKillCI\[attacker\] % GetConVarInt\(hReammoCI\)' `
    "Challenge does not count common-infected kills for a survivor attacker"
Assert-NotContains `
    "addons/sourcemod/scripting/challenge.sp" `
    'GetClientOfUserId\(GetEventInt\(event, "infected_id"\)\)' `
    "Challenge still treats infected_death infected_id as a player userid"
Assert-RawContains `
    "addons/sourcemod/scripting/challenge.sp" `
    '(?s)public void OnConfigsExecuted\(\).*?Timer_ReapplyGameplayOverrides.*?public Action Timer_EmptyServerReset.*?ResetSettings\(false\)' `
    "Challenge does not preserve overrides across maps and reset them after the server empties"
Assert-RawContains `
    "addons/sourcemod/scripting/wave_spawner.sp" `
    '(?s)public void OnConfigsExecuted\(\).*?Timer_RewriteCfgConVar' `
    "Wave Spawner does not preserve its temporary override state across maps"
Assert-Contains "addons/sourcemod/scripting/wave_spawner.sp" 'RegServerCmd\("sm_ast_wave_reset_override"' "Wave Spawner does not expose its reset adapter"
Assert-NotContains `
    "addons/sourcemod/scripting/challenge.sp" `
    'sm_weather|sm_laser|Menu_Laser' `
    "Removed weather or laser controls remain in Challenge"
foreach ($legacyWaveState in @(
    'Waves\.SpawnedSICount',
    'Waves\.AliveSICount',
    'ResetWave'
)) {
    Assert-NotContains `
        "scripts/vscripts/astredux.nut" `
        ('^(?!\s*//).*' + $legacyWaveState) `
        "The AstRedux VScript still owns legacy plugin-wave runtime state: $legacyWaveState"
}
Assert-NotContains `
    "addons/sourcemod/scripting/astredux_profile_controller.sp" `
    'ast_humantankhp' `
    "The AstRedux profile controller still depends on dormant human-Tank health"
Assert-RawContains `
    "addons/sourcemod/scripting/astredux_autowipe.sp" `
    '(?s)if \(!g_bHasHealthSnapshot\[client\]\)\s*\{\s*continue;' `
    "AstRedux AutoWipe does not preserve directly incapacitated survivors without a control snapshot"

foreach ($legacyConfig in @(
    "cfg/cfgogl/astmod/astmod.cfg",
    "cfg/cfgogl/astmod/confogl_off.cfg",
    "cfg/cfgogl/astredux/astredux.cfg",
    "cfg/cfgogl/astredux/confogl_off.cfg",
    "cfg/cfgogl/astflex/astflex.cfg",
    "cfg/cfgogl/astflex/confogl_off.cfg"
)) {
    Assert-NotContains `
        $legacyConfig `
        'confogl_current_config' `
        "A custom mode still references the unloaded confogl_autoloader marker"
}
Assert-Contains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"astmod"\s*$' `
    "The AstMod VPK source does not define the astmod mutation"
Assert-Contains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"astredux"\s*$' `
    "The AstMod VPK source does not define the astredux bootstrap mutation"
Assert-NotContains `
    "assets/astmod_vpk/scripts/gamemodes.txt" `
    '^\s*"amethyst"\s*$' `
    "The legacy mutation ID remains in the AstMod VPK source"
Assert-Contains `
    "assets/astmod_vpk/addoninfo.txt" `
    '^addontitle\s+"AstMod"\s*$' `
    "The AstMod VPK addon title is not renamed"

$zoneOfficialMaps = Get-ChildItem -LiteralPath (Join-Path $Root "cfg/stripper/zonemod/maps") -File |
    Where-Object { $_.Name -match '^c\d+m\d+.*\.cfg$' }
foreach ($zoneMap in $zoneOfficialMaps) {
    $astMap = Join-Path $Root "cfg/stripper/astmod/maps/$($zoneMap.Name)"
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
Assert-KeyValuesBraceBalance "addons/sourcemod/configs/astredux_profiles.cfg"

foreach ($profile in @(
    @{ Players = 1; Health = 1200; WaveSize = 3; WaveInterval = "10.0" },
    @{ Players = 2; Health = 2550; WaveSize = 3; WaveInterval = "15.0" },
    @{ Players = 3; Health = 4500; WaveSize = 5; WaveInterval = "26.0" },
    @{ Players = 4; Health = 6750; WaveSize = 6; WaveInterval = "22.0" }
)) {
    $profileText = Get-KeyValuesSectionContent "addons/sourcemod/configs/astredux_profiles.cfg" "players_$($profile.Players)"
    $valuePattern = '(?s)"spawn_health"\s*"' + $profile.Health + '".*?"melee_damage"\s*"300".*?"wave_size"\s*"' + $profile.WaveSize + '".*?"wave_interval"\s*"' + [regex]::Escape($profile.WaveInterval) + '"'
    if ($null -eq $profileText -or $profileText -notmatch $valuePattern) {
        Add-Failure "AstRedux players_$($profile.Players) profile does not expose the expected Tank and SI values"
    }
}

foreach ($difficulty in @(
    @{ Name = "easy"; Timer = "10"; Limit = "3" },
    @{ Name = "normal"; Timer = "15"; Limit = "3" },
    @{ Name = "hard"; Timer = "26"; Limit = "5" },
    @{ Name = "impossible"; Timer = "22"; Limit = "6" }
)) {
    $config = "cfg/sourcemod/difficulty_adjustment_system/$($difficulty.Name).cfg"
    Assert-Contains $config ('^\s*sm_cvar ast_sitimer_new ' + $difficulty.Timer + '\s*$') "AstMod DAS does not use the 2.8.1 wave interval"
    Assert-Contains $config ('^\s*sm_cvar ast_silimit_new ' + $difficulty.Limit + '\s*$') "AstMod DAS does not use the 2.8.1 wave size"
}

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
Write-Host "Static validation passed; dedicated-server runtime, interactive menus, and campaign completion remain pending."
