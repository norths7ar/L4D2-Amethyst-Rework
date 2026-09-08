#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <builtinvotes>
#undef REQUIRE_PLUGIN
#include <player_manager>
#include <caster_system>

#define TEAM_SPECTATORS 1
#define TEAM_SURVIVORS 2
#define MAX_FOOTER_LEN 65

bool g_readyPhase;
bool g_forceStarted;
int g_loadingTimeout[MAXPLAYERS + 1];
int g_countdownRemaining;
bool g_godMode;
ArrayList g_footer;
bool g_panelHidden[MAXPLAYERS + 1];
float g_panelStarted;
char g_pauseInitiator[MAX_NAME_LENGTH];
bool g_directorHeld;
bool g_savedMobRunning;
float g_savedMobRemaining;
bool g_frozenByReady[MAXPLAYERS + 1];
MoveType g_previousMoveType[MAXPLAYERS + 1];

bool g_isPaused;
bool g_adminPause;
bool g_pendingAdminPause;
bool g_internalPauseCommand;
bool g_voteListener;
bool g_playerReady[MAXPLAYERS + 1];
int g_pauseDelayRemaining;

ConVar g_svPausable;
ConVar g_svNoclipDuringPause;
ConVar g_pauseDelay;
ConVar g_unpauseDelay;
ConVar g_readyBlips;
ConVar g_readyEnabled;
ConVar g_readyCountdownCvar;
ConVar g_loadingTimeoutCvar;
ConVar g_pauseEnabled;
Handle g_forwardInitiatePre;
Handle g_forwardInitiate;
Handle g_forwardCountdownPre;
Handle g_forwardCountdown;
Handle g_forwardLivePre;
Handle g_forwardLive;
Handle g_forwardCancelled;
Handle g_forwardPlayerReady;
Handle g_forwardPlayerUnready;
Handle g_forwardPause;
Handle g_forwardUnpause;
Handle g_loadingTimer;
Handle g_countdownTimer;
Handle g_panelTimer;
Handle g_pauseDelayTimer;
Handle g_deferredPauseTimer;

#include "ready_pause/panel.inc"

public Plugin myinfo =
{
	name = "Coop ready and pause",
	author = "CanadaRox, 海洋空氣, norths7ar",
	description = "Per-player readiness, loading gate and start/resume countdowns",
	version = "1.1.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
	CreateNative("GetFooterStringAtIndex", NativeGetFooterStringAtIndex);
	CreateNative("FindIndexOfFooterString", NativeFindFooterString);
	CreateNative("EditFooterStringAtIndex", NativeEditFooterString);
	CreateNative("AddStringToReadyFooter", NativeAddFooterString);
	CreateNative("IsInReady", NativeIsInReady);
	CreateNative("IsReady", NativeIsReady);
	CreateNative("ToggleReadyPanel", NativeToggleReadyPanel);
	CreateNative("IsInPause", NativeIsInPause);
	RegPluginLibrary("readyup");
	RegPluginLibrary("pause");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("ready_pause.phrases");
	g_footer = new ArrayList(ByteCountToCells(MAX_FOOTER_LEN));
	SetupReadyPanel();
	g_svPausable = FindConVar("sv_pausable");
	g_svNoclipDuringPause = FindConVar("sv_noclipduringpause");
	g_pauseDelay = CreateConVar("sm_pausedelay", "0", "Seconds before a normal coop pause begins.", _, true, 0.0);
	g_unpauseDelay = CreateConVar("sm_unpausedelay", "3", "Ready countdown before a pause ends.", _, true, 0.0);
	g_readyBlips = CreateConVar("sm_pause_ready_blips", "1", "Play a countdown sound before unpausing.", _, true, 0.0, true, 1.0);
	g_readyEnabled = CreateConVar("ready_enabled", "1", "Require loading completion and every survivor's readiness before starting.", _, true, 0.0, true, 1.0);
	g_readyCountdownCvar = CreateConVar("ready_countdown", "3", "Seconds after all survivors are ready before starting.", _, true, 0.0);
	g_loadingTimeoutCvar = CreateConVar("ready_loading_timeout", "90", "Seconds before an unresponsive loading client is kicked.", _, true, 0.0);
	g_pauseEnabled = CreateConVar("pause_enabled", "1", "Enable the pause commands.", _, true, 0.0, true, 1.0);
	HookConVarChange(g_readyEnabled, OnReadyEnabledChanged);
	HookConVarChange(g_pauseEnabled, OnPauseEnabledChanged);
	g_forwardInitiatePre = new GlobalForward("OnReadyUpInitiatePre", ET_Ignore);
	g_forwardInitiate = new GlobalForward("OnReadyUpInitiate", ET_Ignore);
	g_forwardCountdownPre = new GlobalForward("OnRoundLiveCountdownPre", ET_Ignore);
	g_forwardCountdown = new GlobalForward("OnRoundLiveCountdown", ET_Ignore);
	g_forwardLivePre = new GlobalForward("OnRoundIsLivePre", ET_Ignore);
	g_forwardLive = new GlobalForward("OnRoundIsLive", ET_Ignore);
	g_forwardCancelled = new GlobalForward("OnReadyCountdownCancelled", ET_Ignore, Param_Cell, Param_String);
	g_forwardPlayerReady = new GlobalForward("OnPlayerReady", ET_Ignore, Param_Cell);
	g_forwardPlayerUnready = new GlobalForward("OnPlayerUnready", ET_Ignore, Param_Cell);
	g_forwardPause = new GlobalForward("OnPause", ET_Ignore);
	g_forwardUnpause = new GlobalForward("OnUnpause", ET_Ignore);

	RegConsoleCmd("sm_ready", CommandReady, "Mark yourself ready to start or resume.");
	RegConsoleCmd("sm_r", CommandReady, "Mark yourself ready to start or resume.");
	RegConsoleCmd("sm_unpause", CommandReady, "Mark yourself ready to start or resume.");
	RegConsoleCmd("sm_unready", CommandUnready, "Cancel your ready status.");
	RegConsoleCmd("sm_ur", CommandUnready, "Cancel your ready status.");
	RegConsoleCmd("sm_nr", CommandUnready, "Cancel your ready status.");
	RegConsoleCmd("sm_toggleready", CommandToggleReady, "Toggle your ready status.");
	RegConsoleCmd("sm_pause", CommandPause, "Pause the game.");
	RegConsoleCmd("sm_p", CommandPause, "Pause the game.");
	RegConsoleCmd("sm_pausepanel", CommandShowPausePanel, "Show the coop pause panel.");
	RegConsoleCmd("sm_return", CommandReturn, "Return to the saferoom during the ready phase.");
	RegConsoleCmd("sm_show", CommandShowPanel, "Show the ready or pause panel.");
	RegConsoleCmd("sm_hide", CommandHidePanel, "Hide the ready or pause panel.");
	RegAdminCmd("sm_forcepause", CommandForcePause, ADMFLAG_BAN, "Pause until an admin unpauses.");
	RegAdminCmd("sm_forceunpause", CommandForceUnpause, ADMFLAG_BAN, "Unpause regardless of ready status.");
	RegAdminCmd("sm_forcestart", CommandForceStart, ADMFLAG_BAN, "Start the Coop round regardless of the loading gate.");
	RegAdminCmd("sm_fs", CommandForceStart, ADMFLAG_BAN, "Start the Coop round regardless of the loading gate.");

	AddCommandListener(BlockEngineUnpause, "unpause");
	AddCommandListener(BlockEngineUnpause, "pause");
	AddCommandListener(ForwardSay, "say");
	AddCommandListener(ForwardTeamSay, "say_team");
	HookEvent("round_start", EventRoundBoundary, EventHookMode_Pre);
	HookEvent("round_end", EventRoundBoundary, EventHookMode_PostNoCopy);
	HookEvent("player_team", EventPlayerTeam, EventHookMode_Post);
	HookEvent("player_hurt", EventPlayerHurt, EventHookMode_Post);
	HookEvent("weapon_fire", EventWeaponFire, EventHookMode_Post);
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client)) SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamageGodMode);
}

public void OnMapStart()
{
	g_readyPhase = false;
	g_godMode = false;
	g_directorHeld = false;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	g_footer.Clear();
	for (int client = 1; client <= MaxClients; client++)
	{
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
	}
	PrecacheSound("npc/virgil/c3end52.wav");
	PrecacheSound("ui/beep_error01.wav");
	PrecacheSound("player/survivor/voice/coach/worldc2m2b06.wav");
	PrecacheSound("buttons/blip2.wav");
	ResetPauseState(false);
	// Mode loads and the first map must also enter ready-up, not only restarts.
	BeginReadyPhase();
}

public void OnMapEnd()
{
	ToggleVoteCommandListener(false);
	ReleaseDirector();
	SetSurvivorsFrozen(false);
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	ResetPauseState(true);
	g_readyPhase = false;
}

public void OnPluginEnd()
{
	ToggleVoteCommandListener(false);
	ReleaseDirector();
	SetSurvivorsFrozen(false);
	ResetPauseState(true);
}

public void OnConfigsExecuted()
{
	// A mode may load this plugin on an already running map. OnMapStart and
	// round_start establish the phase; the completed config batch reapplies the
	// engine hold without clearing player readiness or dispatching Live twice.
	if (g_readyPhase && g_readyEnabled.BoolValue) HoldDirector();
}

public void OnReadyEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_readyPhase) BeginReadyPhase();
}

public void OnPauseEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!convar.BoolValue && (g_isPaused || g_pauseDelayTimer != null || g_deferredPauseTimer != null)) ResetPauseState(true);
}

public void OnClientPutInServer(int client)
{
	g_frozenByReady[client] = false;
	g_loadingTimeout[client] = 0;
	g_panelHidden[client] = false;
	g_playerReady[client] = false;
	g_panelButtonTime[client] = GetEngineTime();
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamageGodMode);
	if (g_isPaused && !IsFakeClient(client)) PrintToChatAll("%t", "PausePlayerJoined", client);
}

public void OnClientDisconnect(int client)
{
	if (!IsHumanSurvivor(client)) return;
	CancelCountdown(client, "PlayerDisconnected");
}

public void OnClientDisconnect_Post(int client)
{
	g_loadingTimeout[client] = 0;
	g_playerReady[client] = false;
	if (g_isPaused) CreateTimer(0.1, TimerReevaluatePause, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
	if (!g_readyPhase) return Plugin_Continue;
	if (!g_readyEnabled.BoolValue) return Plugin_Continue;
	CreateTimer(0.1, TimerHoldDirector, _, TIMER_FLAG_NO_MAPCHANGE);
	ReturnToSaferoom(client);
	if (client > 0 && IsClientInGame(client)) EmitSoundToClient(client, "ui/beep_error01.wav");
	return Plugin_Handled;
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	// Disabled ready-up keeps the original first-exit notification.
	if (!g_readyPhase || g_readyEnabled.BoolValue) return;
	StartRound();
}

void StartRound()
{
	if (!g_readyPhase) return;
	InvokeForward(g_forwardLivePre);
	g_readyPhase = false;
	ToggleVoteCommandListener(false);
	g_godMode = false;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	SetSurvivorsFrozen(false);
	ReleaseDirector();
	InvokeForward(g_forwardLive);
}

public Action EventRoundBoundary(Event event, const char[] name, bool dontBroadcast)
{
	if (StrEqual(name, "round_start"))
	{
		ResetPauseState(true);
		BeginReadyPhase();
		return Plugin_Continue;
	}
	ResetPauseState(true);
	ToggleVoteCommandListener(false);
	ReleaseDirector();
	SetSurvivorsFrozen(false);
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	g_readyPhase = false;
	g_godMode = false;
	return Plugin_Continue;
}

void BeginReadyPhase()
{
	// Keep the pre-live lifecycle active even when the loading gate is disabled.
	// Consumers still receive OnRoundIsLive on the first real saferoom exit.
	g_readyPhase = true;
	g_forceStarted = false;
	g_godMode = g_readyEnabled.BoolValue;
	g_countdownRemaining = 0;
	g_panelStarted = GetEngineTime();
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	SetSurvivorsFrozen(false);
	for (int client = 1; client <= MaxClients; client++)
	{
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
		g_playerReady[client] = false;
	}
	if (!g_readyEnabled.BoolValue) { ToggleVoteCommandListener(false); ReleaseDirector(); return; }
	ToggleVoteCommandListener(true);
	// Same engine countdown suppression as competitive readyup/game.inc.
	CreateTimer(0.3, TimerHoldDirector, _, TIMER_FLAG_NO_MAPCHANGE);
	InvokeForward(g_forwardInitiatePre);
	g_footer.Clear();
	InvokeForward(g_forwardInitiate);
	g_loadingTimer = CreateTimer(1.0, TimerLoading, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	InitReadyPanel();
	RenderPanel();
	g_panelTimer = CreateTimer(1.0, TimerRefreshPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerHoldDirector(Handle timer)
{
	if (g_readyPhase && g_readyEnabled.BoolValue) HoldDirector();
	return Plugin_Stop;
}

void HoldDirector()
{
	// Rework readyup/game.inc holds both countdowns. Preserve the Director's
	// actual mob interval here: AstRedux's VScript may override the stock CVar.
	if (!g_directorHeld)
	{
		g_savedMobRunning = L4D2_CTimerHasStarted(L4D2CT_MobSpawnTimer);
		g_savedMobRemaining = L4D2_CTimerGetRemainingTime(L4D2CT_MobSpawnTimer);
		g_directorHeld = true;
	}
	else if (L4D2_CTimerGetRemainingTime(L4D2CT_MobSpawnTimer) < 90000.0)
	{
		// The map or VScript installed a new interval after our first hold.
		g_savedMobRunning = L4D2_CTimerHasStarted(L4D2CT_MobSpawnTimer);
		g_savedMobRemaining = L4D2_CTimerGetRemainingTime(L4D2CT_MobSpawnTimer);
	}
	FindConVar("sb_stop").SetBool(true, .notify = false);
	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 99999.9);
	L4D2_CTimerStart(L4D2CT_MobSpawnTimer, 99999.9);
}

void ReleaseDirector()
{
	if (!g_directorHeld) return;
	g_directorHeld = false;
	FindConVar("sb_stop").SetBool(false, .notify = false);
	L4D2_CTimerStart(L4D2CT_VersusStartTimer, FindConVar("versus_force_start_time").FloatValue);
	if (g_savedMobRunning) L4D2_CTimerStart(L4D2CT_MobSpawnTimer, g_savedMobRemaining > 0.0 ? g_savedMobRemaining : 0.0);
	else L4D2_CTimerInvalidate(L4D2CT_MobSpawnTimer);
}

void SetSurvivorsFrozen(bool frozen)
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client)) SetReadyFrozen(client, frozen && GetClientTeam(client) == TEAM_SURVIVORS);
}

void SetReadyFrozen(int client, bool frozen)
{
	if (frozen)
	{
		MoveType current = GetEntityMoveType(client);
		// If a map intro releases its own freeze during our countdown, remember
		// the new movement type instead of restoring the intro's old NONE state.
		if (!g_frozenByReady[client] || current != MOVETYPE_NONE) g_previousMoveType[client] = current;
		g_frozenByReady[client] = true;
		SetEntityMoveType(client, MOVETYPE_NONE);
	}
	else if (g_frozenByReady[client])
	{
		g_frozenByReady[client] = false;
		SetEntityMoveType(client, g_previousMoveType[client]);
	}
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	// readyup.sp: activity only controls the panel's [AFK] marker.
	if (g_readyPhase && IsClientInGame(client) && !IsFakeClient(client))
	{
		static int iLastMouse[MAXPLAYERS+1][2];
		// Mouse Movement Check
		if (mouse[0] != iLastMouse[client][0] || mouse[1] != iLastMouse[client][1])
		{
			iLastMouse[client][0] = mouse[0];
			iLastMouse[client][1] = mouse[1];
			g_panelButtonTime[client] = GetEngineTime();
		}
		else if (buttons || impulse) g_panelButtonTime[client] = GetEngineTime();
	}
	// Map intros can undo the initial freeze (see competitive readyup.sp).
	if (g_countdownTimer != null && IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS)
		if (g_readyPhase) SetReadyFrozen(client, true);
}

public Action EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && !IsFakeClient(client)) g_panelButtonTime[client] = GetEngineTime();
	if (client > 0 && IsClientInGame(client) && event.GetInt("team") != TEAM_SURVIVORS) SetReadyFrozen(client, false);
	bool participantChanged = event.GetInt("team") == TEAM_SURVIVORS || event.GetInt("oldteam") == TEAM_SURVIVORS;
	if (client > 0 && !IsFakeClient(client) && g_readyPhase && participantChanged)
	{
		g_playerReady[client] = false;
		CancelCountdown(client, "TeamChanged");
	}
	if (client > 0 && !IsFakeClient(client) && g_isPaused && participantChanged)
	{
		g_playerReady[client] = false;
		CancelCountdown(0, "ReadinessChanged");
		CreateTimer(0.1, TimerReevaluatePause, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action TimerLoading(Handle timer)
{
	if (!g_readyPhase || !g_readyEnabled.BoolValue)
	{
		g_loadingTimer = null;
		return Plugin_Stop;
	}
	HoldDirector();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client) || IsClientInGame(client) || IsFakeClient(client)) continue;
		if (g_loadingTimeoutCvar.IntValue > 0 && ++g_loadingTimeout[client] >= g_loadingTimeoutCvar.IntValue)
		{
			char reason[128];
			FormatEx(reason, sizeof(reason), "%T", "LoadingTimeout", client);
			KickClient(client, reason);
		}
	}
	EvaluateStartReady();
	return Plugin_Continue;
}

void EvaluateStartReady()
{
	if (!g_readyPhase || !g_readyEnabled.BoolValue || g_forceStarted) return;
	if (!AllClientsLoaded() || !AllSurvivorsReady()) CancelCountdown(0, "ReadinessChanged");
	else StartCountdown();
}

// Rework ordinary/forced starts share the same countdown. Pause uses the same
// per-survivor readiness and presentation; only its completion action differs.
void StartCountdown()
{
	if (g_countdownTimer != null) return;
	g_countdownRemaining = g_isPaused ? g_unpauseDelay.IntValue : g_readyCountdownCvar.IntValue;
	if (g_readyPhase)
	{
		InvokeForward(g_forwardCountdownPre);
		for (int client = 1; client <= MaxClients; client++)
			if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS && IsPlayerAlive(client)) ReturnToSaferoom(client);
		SetSurvivorsFrozen(true);
		InvokeForward(g_forwardCountdown);
	}
	if (g_countdownRemaining <= 0) FinishCountdown();
	else
	{
		ShowCountdown();
		g_countdownTimer = CreateTimer(1.0, TimerCountdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void ShowCountdown()
{
	PrintHintTextToAll("%t", g_isPaused ? "PauseCountdown" : "RoundCountdown", g_countdownRemaining);
	if (g_readyBlips.BoolValue) EmitSoundToAll("buttons/blip2.wav");
}

public Action TimerCountdown(Handle timer)
{
	if (!g_isPaused && !g_readyPhase) { g_countdownTimer = null; return Plugin_Stop; }
	if (!g_forceStarted && (!AllSurvivorsReady() || (g_readyPhase && !AllClientsLoaded()) || (g_isPaused && g_adminPause)))
	{
		g_countdownTimer = null;
		CancelCountdown(0, "ReadinessChanged");
		return Plugin_Stop;
	}
	if (--g_countdownRemaining <= 0)
	{
		g_countdownTimer = null;
		FinishCountdown();
		return Plugin_Stop;
	}
	ShowCountdown();
	return Plugin_Continue;
}

void FinishCountdown()
{
	g_countdownRemaining = 0;
	if (g_isPaused) EndPause();
	else
	{
		PrintHintTextToAll("%t", "RoundGo");
		char map[64];
		GetCurrentMap(map, sizeof(map));
		EmitSoundToAll(StrContains(map, "c2", false) == 0 || StrContains(map, "dkr", false) == 0 ? "player/survivor/voice/coach/worldc2m2b06.wav" : "npc/virgil/c3end52.wav");
		StartRound();
	}
	g_forceStarted = false;
}

void CancelCountdown(int client, const char[] reason)
{
	if (g_forceStarted || g_countdownRemaining <= 0) return;
	CancelTimer(g_countdownTimer);
	g_countdownRemaining = 0;
	PrintHintTextToAll("%t", "CountdownCancelled");
	if (g_readyPhase)
	{
		SetSurvivorsFrozen(false);
		Call_StartForward(g_forwardCancelled);
		Call_PushCell(client);
		Call_PushString(reason);
		Call_Finish();
	}
}
void ReturnToSaferoom(int client)
{
	if (client <= 0 || !IsClientInGame(client)) return;
	int flags = GetCommandFlags("warp_to_start_area");
	SetCommandFlags("warp_to_start_area", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "warp_to_start_area");
	SetCommandFlags("warp_to_start_area", flags);
	float velocity[3];
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", 0.0);
}

public Action OnTakeDamageGodMode(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	return g_godMode && victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == TEAM_SURVIVORS ? Plugin_Handled : Plugin_Continue;
}

public void EventPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!g_godMode || client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVORS) return;
	if (GetEntProp(client, Prop_Send, "m_isIncapacitated")) L4D_ReviveSurvivor(client);
	SetEntityHealth(client, 100);
	L4D_SetTempHealth(client, 0.0);
}

public void EventWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!g_godMode || client <= 0 || !IsClientInGame(client)) return;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon > 0 && GetEntProp(weapon, Prop_Send, "m_iClip1") >= 0)
		SetEntProp(weapon, Prop_Send, "m_iClip1", GetEntProp(weapon, Prop_Send, "m_iClip1") + 1);
}

public Action L4D_OnLedgeGrabbed(int client)
{
	if (g_readyPhase && g_readyEnabled.BoolValue && client > 0 && GetClientTeam(client) == TEAM_SURVIVORS)
	{
		L4D_ReviveSurvivor(client);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action CommandPause(int client, int args)
{
	if (!g_pauseEnabled.BoolValue || g_readyPhase || !IsHumanSurvivor(client) || g_isPaused || g_pauseDelayTimer != null || g_deferredPauseTimer != null) return Plugin_Handled;
	GetClientName(client, g_pauseInitiator, sizeof(g_pauseInitiator));
	g_pauseDelayRemaining = g_pauseDelay.IntValue;
	PrintToChatAll("%t", "PauseRequested", client);
	if (g_pauseDelayRemaining <= 0) AttemptPause(false);
	else g_pauseDelayTimer = CreateTimer(1.0, TimerPauseDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action CommandReturn(int client, int args)
{
	if (g_readyPhase && IsHumanSurvivor(client)) ReturnToSaferoom(client);
	return Plugin_Handled;
}

public Action TimerPauseDelay(Handle timer)
{
	if (--g_pauseDelayRemaining <= 0)
	{
		g_pauseDelayTimer = null;
		AttemptPause(false);
		return Plugin_Stop;
	}
	PrintToChatAll("%t", "PauseDelay", g_pauseDelayRemaining);
	return Plugin_Continue;
}

void AttemptPause(bool adminPause)
{
	if (g_isPaused) return;
	if (CanPauseNow())
	{
		g_pendingAdminPause = false;
		BeginPause(adminPause);
	}
	else
	{
		g_pendingAdminPause = adminPause;
		CancelTimer(g_deferredPauseTimer);
		g_deferredPauseTimer = CreateTimer(0.1, TimerDeferredPause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action TimerDeferredPause(Handle timer)
{
	if (!CanPauseNow()) return Plugin_Continue;
	g_deferredPauseTimer = null;
	bool adminPause = g_pendingAdminPause;
	g_pendingAdminPause = false;
	BeginPause(adminPause);
	return Plugin_Stop;
}

void BeginPause(bool adminPause)
{
	CancelTimer(g_pauseDelayTimer);
	CancelTimer(g_deferredPauseTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	g_isPaused = true;
	g_forceStarted = false;
	g_countdownRemaining = 0;
	g_panelStarted = GetEngineTime();
	g_adminPause = adminPause;
	g_pendingAdminPause = false;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_playerReady[client] = false;
		g_panelHidden[client] = false;
	}
	// pause.sp starts the refresh timer before issuing the engine pause.
	// Let that refresh send the first panel after the pause command completes.
	g_panelTimer = CreateTimer(1.0, TimerRefreshPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	if (!SetEnginePaused(true))
	{
		CancelTimer(g_panelTimer);
		g_isPaused = false;
		g_adminPause = false;
		g_pendingAdminPause = false;
		return;
	}
	PrintToChatAll("%t", adminPause ? "PauseAdmin" : "PauseStarted");
	ToggleVoteCommandListener(true);
	InvokeForward(g_forwardPause);
}

public Action CommandReady(int client, int args)
{
	if ((!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue)) || !IsHumanSurvivor(client)) return Plugin_Handled;
	if (!g_playerReady[client])
	{
		g_playerReady[client] = true;
		Call_StartForward(g_forwardPlayerReady);
		Call_PushCell(client);
		Call_Finish();
		PrintToChatAll("%t", "PlayerReady", client);
	}
	if (g_isPaused) EvaluatePauseReady();
	else EvaluateStartReady();
	RenderPanel();
	return Plugin_Handled;
}

public Action CommandUnready(int client, int args)
{
	if ((g_readyPhase || g_isPaused) && g_forceStarted)
	{
		if (!CheckCommandAccess(client, "sm_forcestart", ADMFLAG_BAN)) return Plugin_Handled;
		g_forceStarted = false;
		CancelCountdown(client, "PlayerUnready");
		for (int target = 1; target <= MaxClients; target++) g_playerReady[target] = false;
		RenderPanel();
		return Plugin_Handled;
	}
	if ((!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue)) || !IsHumanSurvivor(client)) return Plugin_Handled;
	if (g_playerReady[client])
	{
		g_playerReady[client] = false;
		Call_StartForward(g_forwardPlayerUnready);
		Call_PushCell(client);
		Call_Finish();
		PrintToChatAll("%t", "PlayerUnready", client);
	}
	CancelCountdown(client, "PlayerUnready");
	RenderPanel();
	return Plugin_Handled;
}

public Action CommandToggleReady(int client, int args)
{
	if (client <= 0 || client > MaxClients) return Plugin_Handled;
	return g_playerReady[client] ? CommandUnready(client, args) : CommandReady(client, args);
}

void ToggleVoteCommandListener(bool hook)
{
	if (g_voteListener == hook) return;
	if (hook) AddCommandListener(ReadyVoteCallback, "Vote");
	else RemoveCommandListener(ReadyVoteCallback, "Vote");
	g_voteListener = hook;
}

Action ReadyVoteCallback(int client, const char[] command, int argc)
{
	if (client <= 0 || (!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue))) return Plugin_Continue;
	if (BuiltinVote_IsVoteInProgress() && IsClientInBuiltinVotePool(client)) return Plugin_Continue;

	if (Game_IsVoteInProgress())
	{
		int voteTeam = Game_GetVoteTeam();
		if (voteTeam == -1 || voteTeam == GetClientTeam(client)) return Plugin_Continue;
	}

	char vote[8];
	GetCmdArg(1, vote, sizeof(vote));
	if (StrEqual(vote, "Yes", false)) CommandReady(client, 0);
	else if (StrEqual(vote, "No", false)) CommandUnready(client, 0);
	return Plugin_Continue;
}

void EvaluatePauseReady()
{
	if (!g_isPaused) return;
	int humans;
	for (int client = 1; client <= MaxClients; client++)
		if (IsHumanSurvivor(client)) humans++;
	if (humans == 0) { EndPause(); return; }
	if (g_forceStarted) return;
	if (!g_adminPause && AllSurvivorsReady()) StartCountdown();
	else CancelCountdown(0, "ReadinessChanged");
}

bool AllSurvivorsReady()
{
	int humans;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanSurvivor(client)) continue;
		humans++;
		if (!g_playerReady[client]) return false;
	}
	return humans > 0;
}

void EndPause()
{
	if (!g_isPaused) return;
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	bool changed = SetEnginePaused(false);
	g_isPaused = false;
	ToggleVoteCommandListener(false);
	g_adminPause = false;
	g_pendingAdminPause = false;
	g_forceStarted = false;
	g_countdownRemaining = 0;
	PrintHintTextToAll("%t", "PauseEnded");
	if (changed) InvokeForward(g_forwardUnpause);
}

public Action CommandForcePause(int client, int args)
{
	if (!g_pauseEnabled.BoolValue || g_readyPhase) return Plugin_Handled;
	if (client > 0) GetClientName(client, g_pauseInitiator, sizeof(g_pauseInitiator));
	else strcopy(g_pauseInitiator, sizeof(g_pauseInitiator), "Console");
	if (!g_isPaused) AttemptPause(true);
	else
	{
		g_adminPause = true;
		g_forceStarted = false;
		CancelCountdown(0, "ReadinessChanged");
		PrintToChatAll("%t", "PauseAdminTakeover");
	}
	return Plugin_Handled;
}

public Action CommandForceUnpause(int client, int args)
{
	CancelTimer(g_pauseDelayTimer);
	CancelTimer(g_deferredPauseTimer);
	g_pendingAdminPause = false;
	if (g_isPaused)
	{
		g_adminPause = false;
		g_forceStarted = true;
		StartCountdown();
		RenderPanel();
	}
	return Plugin_Handled;
}

public Action CommandForceStart(int client, int args)
{
	if (g_isPaused) return CommandForceUnpause(client, args);
	if (!g_readyPhase) return Plugin_Handled;
	g_forceStarted = true;
	StartCountdown();
	RenderPanel();
	return Plugin_Handled;
}

public Action CommandShowPausePanel(int client, int args)
{
	if (client > 0 && g_isPaused) { g_panelHidden[client] = false; RenderPanel(); }
	return Plugin_Handled;
}

public Action CommandShowPanel(int client, int args)
{
	if (client > 0)
	{
		g_panelHidden[client] = false;
		PrintToChat(client, "%t", "PanelShow");
		RenderPanel();
	}
	return Plugin_Handled;
}

public Action CommandHidePanel(int client, int args)
{
	if (client > 0)
	{
		g_panelHidden[client] = true;
		PrintToChat(client, "%t", "PanelHide");
	}
	return Plugin_Handled;
}

public Action TimerReevaluatePause(Handle timer)
{
	EvaluatePauseReady();
	return Plugin_Stop;
}

public Action TimerRefreshPanel(Handle timer)
{
	if (!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue))
	{
		g_panelTimer = null;
		return Plugin_Stop;
	}
	RenderPanel();
	return Plugin_Continue;
}

void RenderPanel()
{
	if (g_isPaused) UpdatePausePanel();
	else if (g_readyPhase && g_readyEnabled.BoolValue) UpdateReadyPanel();
}

bool SetEnginePaused(bool pause)
{
	if (g_svPausable == null) return false;
	bool old = g_svPausable.BoolValue;
	g_svPausable.BoolValue = true;
	g_internalPauseCommand = true;
	bool sent;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client)) continue;
		FakeClientCommand(client, pause ? "pause" : "unpause");
		sent = true;
		break;
	}
	g_internalPauseCommand = false;
	g_svPausable.BoolValue = old;
	if (g_svNoclipDuringPause != null)
		for (int client = 1; client <= MaxClients; client++)
			if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SPECTATORS) SendConVarValue(client, g_svNoclipDuringPause, pause ? "1" : "0");
	return sent;
}

public Action BlockEngineUnpause(int client, const char[] command, int argc)
{
	if (g_internalPauseCommand) return Plugin_Continue;
	if (StrEqual(command, "pause")) return CommandPause(client, argc);
	return g_isPaused ? Plugin_Handled : Plugin_Continue;
}

public Action ForwardSay(int client, const char[] command, int argc)
{
	if (client > 0) g_panelButtonTime[client] = GetEngineTime();
	if (!g_isPaused || client <= 0) return Plugin_Continue;
	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (!message[0] || message[0] == '!' || message[0] == '/') return Plugin_Continue;
	PrintToChatAll("%t", "PauseChat", client, message);
	return Plugin_Handled;
}

public Action ForwardTeamSay(int client, const char[] command, int argc)
{
	if (client > 0) g_panelButtonTime[client] = GetEngineTime();
	if (!g_isPaused || client <= 0) return Plugin_Continue;
	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (!message[0] || message[0] == '!' || message[0] == '/') return Plugin_Continue;
	for (int target = 1; target <= MaxClients; target++)
		if (IsClientInGame(target) && GetClientTeam(target) == GetClientTeam(client)) PrintToChat(target, "%t", "PauseTeamChat", client, message);
	return Plugin_Handled;
}

bool CanPauseNow()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVORS) continue;
		if (GetEntProp(client, Prop_Send, "m_isIncapacitated") && GetEntProp(client, Prop_Send, "m_reviveOwner") > 0) return false;
		if (!GetEntProp(client, Prop_Send, "m_isIncapacitated") && GetEntProp(client, Prop_Send, "m_reviveTarget") > 0) return false;
	}
	return true;
}

bool IsHumanSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}

bool AllClientsLoaded()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client) || IsFakeClient(client) || IsClientInKickQueue(client)) continue;
		if (!IsClientInGame(client)) return false;
	}
	return LibraryExists("player_manager")
		&& GetFeatureStatus(FeatureType_Native, "Coop_IsRosterStable") == FeatureStatus_Available
		&& Coop_IsRosterStable();
}

void ResetPauseState(bool unpause)
{
	ToggleVoteCommandListener(false);
	if (unpause && g_isPaused) SetEnginePaused(false);
	CancelTimer(g_pauseDelayTimer);
	CancelTimer(g_deferredPauseTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	g_isPaused = false;
	g_adminPause = false;
	g_pendingAdminPause = false;
	g_internalPauseCommand = false;
	g_forceStarted = false;
	g_countdownRemaining = 0;
	for (int client = 1; client <= MaxClients; client++) g_playerReady[client] = false;
}

void CancelTimer(Handle &timer)
{
	if (timer != null) { delete timer; timer = null; }
}

void InvokeForward(Handle targetForward)
{
	Call_StartForward(targetForward);
	Call_Finish();
}

int NativeAddFooterString(Handle plugin, int params)
{
	if (!g_readyPhase) return -1;
	char value[MAX_FOOTER_LEN];
	GetNativeString(1, value, sizeof(value));
	if (!value[0] || strlen(value) >= MAX_FOOTER_LEN) return -1;
	return g_footer.PushString(value);
}

int NativeEditFooterString(Handle plugin, int params)
{
	if (!g_readyPhase) return false;
	int index = GetNativeCell(1);
	if (index < 0 || index >= g_footer.Length) return false;
	char value[MAX_FOOTER_LEN];
	GetNativeString(2, value, sizeof(value));
	g_footer.SetString(index, value);
	return true;
}

int NativeFindFooterString(Handle plugin, int params)
{
	if (!g_readyPhase) return -1;
	char value[MAX_FOOTER_LEN];
	GetNativeString(1, value, sizeof(value));
	return g_footer.FindString(value);
}

int NativeGetFooterStringAtIndex(Handle plugin, int params)
{
	if (!g_readyPhase) return false;
	int index = GetNativeCell(1);
	if (index < 0 || index >= g_footer.Length) return false;
	char value[MAX_FOOTER_LEN];
	g_footer.GetString(index, value, sizeof(value));
	SetNativeString(2, value, GetNativeCell(3), true);
	return true;
}

int NativeIsInReady(Handle plugin, int params) { return g_readyPhase && g_readyEnabled.BoolValue; }
int NativeIsInPause(Handle plugin, int params) { return g_isPaused; }

int NativeIsReady(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)) return false;
	return (g_isPaused || g_readyPhase) && IsHumanSurvivor(client) && g_playerReady[client];
}

int NativeToggleReadyPanel(Handle plugin, int params)
{
	if (!g_readyPhase && !g_isPaused) return false;
	bool show = GetNativeCell(1) != 0;
	int target = GetNativeCell(2);
	if (target > 0 && IsClientInGame(target))
	{
		bool old = !g_panelHidden[target];
		g_panelHidden[target] = !show;
		if (show) RenderPanel();
		return old;
	}
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client)) g_panelHidden[client] = !show;
	if (show) RenderPanel();
	return true;
}
