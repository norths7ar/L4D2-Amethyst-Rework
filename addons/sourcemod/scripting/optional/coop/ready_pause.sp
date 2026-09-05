#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define TEAM_SPECTATORS 1
#define TEAM_SURVIVORS 2
#define MAX_FOOTER_LEN 65

bool g_readyPhase;
bool g_countdownFinished;
bool g_loading[MAXPLAYERS + 1];
int g_loadingTimeout[MAXPLAYERS + 1];
int g_readyCountdown;
int g_readyCountdownTotal;
int g_generation;
bool g_godMode;
ArrayList g_footer;
bool g_panelHidden[MAXPLAYERS + 1];

bool g_isPaused;
bool g_adminPause;
bool g_pendingAdminPause;
bool g_internalPauseCommand;
bool g_playerReady[MAXPLAYERS + 1];
int g_pauseDelayRemaining;
int g_unpauseCountdown;

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
Handle g_readyTimer;
Handle g_readyPanelTimer;
Handle g_pauseDelayTimer;
Handle g_deferredPauseTimer;
Handle g_unpauseTimer;
Handle g_pausePanelTimer;

public Plugin myinfo =
{
	name = "Coop ready and pause",
	author = "CanadaRox, 海洋空氣, norths7ar",
	description = "Automatic Coop loading gate, countdown and per-player pause readiness",
	version = "1.0.0"
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
	g_svPausable = FindConVar("sv_pausable");
	g_svNoclipDuringPause = FindConVar("sv_noclipduringpause");
	g_pauseDelay = CreateConVar("sm_pausedelay", "0", "Seconds before a normal coop pause begins.", _, true, 0.0);
	g_unpauseDelay = CreateConVar("sm_unpausedelay", "5", "Ready countdown before a coop pause ends.", _, true, 0.0);
	g_readyBlips = CreateConVar("sm_pause_ready_blips", "1", "Play a countdown sound before unpausing.", _, true, 0.0, true, 1.0);
	g_readyEnabled = CreateConVar("coop_ready_enabled", "1", "Enable the automatic Coop loading gate.", _, true, 0.0, true, 1.0);
	g_readyCountdownCvar = CreateConVar("coop_ready_countdown", "10", "Seconds in the automatic Coop start countdown.", _, true, 0.0);
	g_loadingTimeoutCvar = CreateConVar("coop_ready_loading_timeout", "90", "Seconds before an unresponsive loading client is kicked.", _, true, 0.0);
	g_pauseEnabled = CreateConVar("coop_pause_enabled", "1", "Enable the Coop pause commands.", _, true, 0.0, true, 1.0);
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

	RegConsoleCmd("sm_ready", CommandReady, "Mark yourself ready for a coop pause.");
	RegConsoleCmd("sm_r", CommandReady, "Mark yourself ready for a coop pause.");
	RegConsoleCmd("sm_unpause", CommandReady, "Mark yourself ready for a coop pause.");
	RegConsoleCmd("sm_unready", CommandUnready, "Cancel your pause ready status.");
	RegConsoleCmd("sm_ur", CommandUnready, "Cancel your pause ready status.");
	RegConsoleCmd("sm_nr", CommandUnready, "Cancel your pause ready status.");
	RegConsoleCmd("sm_toggleready", CommandToggleReady, "Toggle your pause ready status.");
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
	AddCommandListener(ForwardSay, "say");
	AddCommandListener(ForwardTeamSay, "say_team");
	HookEvent("round_start", EventRoundBoundary, EventHookMode_PostNoCopy);
	HookEvent("round_end", EventRoundBoundary, EventHookMode_PostNoCopy);
	HookEvent("player_team", EventPlayerTeam, EventHookMode_Post);
	HookEvent("player_hurt", EventPlayerHurt, EventHookMode_Post);
	HookEvent("weapon_fire", EventWeaponFire, EventHookMode_Post);
}

public void OnMapStart()
{
	g_generation++;
	g_readyPhase = false;
	g_countdownFinished = true;
	g_godMode = false;
	g_readyCountdown = -1;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_readyTimer);
	CancelTimer(g_readyPanelTimer);
	g_footer.Clear();
	for (int client = 1; client <= MaxClients; client++)
	{
		g_loading[client] = true;
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
	}
	PrecacheSound("npc/virgil/c3end52.wav");
	PrecacheSound("ui/beep_error01.wav");
	PrecacheSound("player/survivor/voice/coach/worldc2m2b06.wav");
	PrecacheSound("buttons/blip2.wav");
	ResetPauseState(false);
}

public void OnMapEnd()
{
	g_generation++;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_readyTimer);
	CancelTimer(g_readyPanelTimer);
	ResetPauseState(true);
	g_readyPhase = false;
}

public void OnPluginEnd()
{
	ResetPauseState(true);
}

public void OnClientPutInServer(int client)
{
	g_loading[client] = !g_countdownFinished;
	g_loadingTimeout[client] = 0;
	g_panelHidden[client] = false;
	g_playerReady[client] = false;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamageGodMode);
	if (g_isPaused && !IsFakeClient(client)) PrintToChatAll("%t", "PausePlayerJoined", client);
}

public void OnClientDisconnect_Post(int client)
{
	g_loading[client] = false;
	g_loadingTimeout[client] = 0;
	g_playerReady[client] = false;
	if (g_isPaused) CreateTimer(0.1, TimerReevaluatePause, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
	if (!g_readyPhase) return Plugin_Continue;
	if (!g_readyEnabled.BoolValue) return Plugin_Continue;
	if (!AllClientsLoaded())
	{
		ReturnToSaferoom(client);
		EmitSoundToClient(client, "ui/beep_error01.wav");
		PrintHintTextToAll("%t", "WaitingForPlayers");
		return Plugin_Handled;
	}
	if (!g_countdownFinished)
	{
		ReturnToSaferoom(client);
		EmitSoundToClient(client, "ui/beep_error01.wav");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	if (!g_readyPhase) return;
	InvokeForward(g_forwardLivePre);
	g_readyPhase = false;
	g_godMode = false;
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
	CancelTimer(g_loadingTimer);
	CancelTimer(g_readyTimer);
	CancelTimer(g_readyPanelTimer);
	g_readyPhase = false;
	return Plugin_Continue;
}

void BeginReadyPhase()
{
	// Keep the pre-live lifecycle active even when the loading gate is disabled.
	// Consumers still receive OnRoundIsLive on the first real saferoom exit.
	g_readyPhase = true;
	g_countdownFinished = !g_readyEnabled.BoolValue;
	g_godMode = g_readyEnabled.BoolValue;
	g_readyCountdown = -1;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_readyTimer);
	CancelTimer(g_readyPanelTimer);
	for (int client = 1; client <= MaxClients; client++)
	{
		g_loading[client] = true;
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
	}
	if (!g_readyEnabled.BoolValue) return;
	InvokeForward(g_forwardInitiatePre);
	InvokeForward(g_forwardInitiate);
	CancelTimer(g_loadingTimer);
	g_loadingTimer = CreateTimer(1.0, TimerLoading, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	RenderReadyPanel();
	g_readyPanelTimer = CreateTimer(1.0, TimerRefreshReadyPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && !IsFakeClient(client) && g_readyPhase)
	{
		CancelReadyCountdown(client, "TeamChanged");
		g_loading[client] = !IsClientInGame(client);
	}
	if (client > 0 && !IsFakeClient(client) && g_isPaused)
	{
		g_playerReady[client] = false;
		CreateTimer(0.1, TimerReevaluatePause, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action TimerLoading(Handle timer)
{
	if (!g_readyPhase || AllClientsLoaded())
	{
		g_loadingTimer = null;
		if (g_readyPhase && g_readyCountdown < 0)
		{
			g_readyCountdown = 0;
			g_readyCountdownTotal = g_readyCountdownCvar.IntValue;
			InvokeForward(g_forwardCountdownPre);
			InvokeForward(g_forwardCountdown);
			CancelTimer(g_readyTimer);
			g_readyTimer = CreateTimer(1.0, TimerReadyCountdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
		return Plugin_Stop;
	}
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client) || IsClientInGame(client) || IsFakeClient(client)) continue;
		if (g_loadingTimeoutCvar.IntValue > 0 && ++g_loadingTimeout[client] >= g_loadingTimeoutCvar.IntValue)
		{
			char reason[128];
			FormatEx(reason, sizeof(reason), "%T", "LoadingTimeout", client);
			KickClient(client, reason);
			g_loading[client] = false;
		}
	}
	return Plugin_Continue;
}

public Action TimerReadyCountdown(Handle timer)
{
	if (!g_readyPhase) { g_readyTimer = null; return Plugin_Stop; }
	if (g_readyCountdown++ >= g_readyCountdownTotal)
	{
		g_readyTimer = null;
		g_countdownFinished = true;
		PrintHintTextToAll("%t", "RoundGo");
		char map[64];
		GetCurrentMap(map, sizeof(map));
		EmitSoundToAll(StrContains(map, "c2", false) == 0 || StrContains(map, "dkr", false) == 0 ? "player/survivor/voice/coach/worldc2m2b06.wav" : "npc/virgil/c3end52.wav");
		return Plugin_Stop;
	}
	PrintHintTextToAll("%t", "RoundCountdown", g_readyCountdownTotal - g_readyCountdown);
	return Plugin_Continue;
}

void CancelReadyCountdown(int client, const char[] reason)
{
	if (!g_readyPhase || g_countdownFinished) return;
	if (g_readyTimer != null)
	{
		delete g_readyTimer;
		g_readyTimer = null;
		Call_StartForward(g_forwardCancelled);
		Call_PushCell(client);
		Call_PushString(reason);
		Call_Finish();
	}
	g_readyCountdown = -1;
	CancelTimer(g_loadingTimer);
	g_loadingTimer = CreateTimer(1.0, TimerLoading, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ReturnToSaferoom(int client)
{
	if (client <= 0 || !IsClientInGame(client)) return;
	int flags = GetCommandFlags("warp_to_start_area");
	SetCommandFlags("warp_to_start_area", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "warp_to_start_area");
	SetCommandFlags("warp_to_start_area", flags);
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
	if (g_readyPhase && client > 0 && GetClientTeam(client) == TEAM_SURVIVORS)
	{
		L4D_ReviveSurvivor(client);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action CommandPause(int client, int args)
{
	if (!g_pauseEnabled.BoolValue || g_readyPhase || !IsHumanSurvivor(client) || g_isPaused || g_pauseDelayTimer != null || g_deferredPauseTimer != null) return Plugin_Handled;
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
	CancelTimer(g_unpauseTimer);
	g_isPaused = true;
	g_adminPause = adminPause;
	g_pendingAdminPause = false;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_playerReady[client] = false;
		g_panelHidden[client] = false;
	}
	if (!SetEnginePaused(true))
	{
		g_isPaused = false;
		g_adminPause = false;
		g_pendingAdminPause = false;
		return;
	}
	PrintToChatAll("%t", adminPause ? "PauseAdmin" : "PauseStarted");
	RenderPausePanel();
	g_pausePanelTimer = CreateTimer(1.0, TimerRefreshPausePanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	InvokeForward(g_forwardPause);
}

public Action CommandReady(int client, int args)
{
	if (!g_isPaused || !IsHumanSurvivor(client)) return Plugin_Handled;
	if (!g_playerReady[client])
	{
		g_playerReady[client] = true;
		Call_StartForward(g_forwardPlayerReady);
		Call_PushCell(client);
		Call_Finish();
		PrintToChatAll("%t", "PlayerReady", client);
	}
	EvaluatePauseReady();
	RenderPausePanel();
	return Plugin_Handled;
}

public Action CommandUnready(int client, int args)
{
	if (!g_isPaused || !IsHumanSurvivor(client)) return Plugin_Handled;
	if (g_playerReady[client])
	{
		g_playerReady[client] = false;
		Call_StartForward(g_forwardPlayerUnready);
		Call_PushCell(client);
		Call_Finish();
		PrintToChatAll("%t", "PlayerUnready", client);
	}
	CancelPauseCountdown(client);
	RenderPausePanel();
	return Plugin_Handled;
}

public Action CommandToggleReady(int client, int args)
{
	return g_playerReady[client] ? CommandUnready(client, args) : CommandReady(client, args);
}

void EvaluatePauseReady()
{
	if (g_isPaused && !g_adminPause && AllSurvivorsPauseReady()) StartPauseCountdown();
}

bool AllSurvivorsPauseReady()
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

void StartPauseCountdown()
{
	if (g_unpauseTimer != null) return;
	g_unpauseCountdown = g_unpauseDelay.IntValue;
	if (g_unpauseCountdown <= 0) EndPause();
	else g_unpauseTimer = CreateTimer(1.0, TimerPauseCountdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerPauseCountdown(Handle timer)
{
	if (!g_isPaused || !AllSurvivorsPauseReady())
	{
		g_unpauseTimer = null;
		return Plugin_Stop;
	}
	if (--g_unpauseCountdown <= 0)
	{
		g_unpauseTimer = null;
		EndPause();
		return Plugin_Stop;
	}
	PrintToChatAll("%t", "PauseCountdown", g_unpauseCountdown);
	if (g_readyBlips.BoolValue) EmitSoundToAll("buttons/blip2.wav");
	RenderPausePanel();
	return Plugin_Continue;
}

void CancelPauseCountdown(int client)
{
	if (g_unpauseTimer == null) return;
	delete g_unpauseTimer;
	g_unpauseTimer = null;
	if (client > 0) PrintToChatAll("%t", "PauseCountdownCancelled", client);
}

void EndPause()
{
	if (!g_isPaused) return;
	CancelTimer(g_unpauseTimer);
	CancelTimer(g_pausePanelTimer);
	bool changed = SetEnginePaused(false);
	g_isPaused = false;
	g_adminPause = false;
	g_pendingAdminPause = false;
	PrintToChatAll("%t", "PauseEnded");
	if (changed) InvokeForward(g_forwardUnpause);
}

public Action CommandForcePause(int client, int args)
{
	if (!g_pauseEnabled.BoolValue || g_readyPhase) return Plugin_Handled;
	if (!g_isPaused) AttemptPause(true);
	else
	{
		g_adminPause = true;
		CancelPauseCountdown(0);
		PrintToChatAll("%t", "PauseAdminTakeover");
	}
	return Plugin_Handled;
}

public Action CommandForceUnpause(int client, int args)
{
	if (g_isPaused) EndPause();
	return Plugin_Handled;
}

public Action CommandForceStart(int client, int args)
{
	if (g_isPaused)
	{
		EndPause();
		return Plugin_Handled;
	}
	if (!g_readyPhase) return Plugin_Handled;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_readyTimer);
	CancelTimer(g_readyPanelTimer);
	g_countdownFinished = true;
	g_readyCountdown = g_readyCountdownTotal;
	RenderReadyPanel();
	return Plugin_Handled;
}

public Action CommandShowPausePanel(int client, int args)
{
	if (client > 0 && g_isPaused) { g_panelHidden[client] = false; RenderPausePanel(); }
	return Plugin_Handled;
}

public Action CommandShowPanel(int client, int args)
{
	if (client > 0)
	{
		g_panelHidden[client] = false;
		if (g_isPaused) RenderPausePanel();
		else if (g_readyPhase) RenderReadyPanel();
	}
	return Plugin_Handled;
}

public Action CommandHidePanel(int client, int args)
{
	if (client > 0) g_panelHidden[client] = true;
	return Plugin_Handled;
}

public Action TimerRefreshPausePanel(Handle timer)
{
	if (!g_isPaused) { g_pausePanelTimer = null; return Plugin_Stop; }
	RenderPausePanel();
	return Plugin_Continue;
}

public Action TimerReevaluatePause(Handle timer)
{
	EvaluatePauseReady();
	return Plugin_Stop;
}

public Action TimerRefreshReadyPanel(Handle timer)
{
	if (!g_readyPhase)
	{
		g_readyPanelTimer = null;
		return Plugin_Stop;
	}
	RenderReadyPanel();
	return Plugin_Continue;
}

void RenderReadyPanel()
{
	if (!g_readyPhase) return;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target) || IsFakeClient(target) || g_panelHidden[target]) continue;
		Panel panel = new Panel();
		char line[128];
		FormatEx(line, sizeof(line), "%T", "ReadyTitle", target);
		panel.SetTitle(line);
		bool loading;
		for (int client = 1; client <= MaxClients; client++)
			if (IsClientConnected(client) && !IsFakeClient(client) && g_loading[client]) loading = true;
		if (loading) FormatEx(line, sizeof(line), "%T", "ReadyLoading", target);
		else if (!g_countdownFinished) FormatEx(line, sizeof(line), "%T", "ReadyCountdown", target, g_readyCountdownTotal - g_readyCountdown);
		else FormatEx(line, sizeof(line), "%T", "ReadyGo", target);
		panel.DrawText(line);
		for (int i = 0; i < g_footer.Length; i++)
		{
			g_footer.GetString(i, line, sizeof(line));
			panel.DrawText(line);
		}
		panel.Send(target, PanelHandler, 2);
		delete panel;
	}
}

void RenderPausePanel()
{
	if (!g_isPaused) return;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target) || IsFakeClient(target) || g_panelHidden[target]) continue;
		Panel panel = new Panel();
		char line[128];
		FormatEx(line, sizeof(line), "%T", g_adminPause ? "PauseAdminTitle" : "PauseTitle", target);
		panel.SetTitle(line);
		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsHumanSurvivor(client)) continue;
			FormatEx(line, sizeof(line), "%T", g_playerReady[client] ? "PausePlayerReady" : "PausePlayerUnready", target, client);
			panel.DrawText(line);
		}
		if (g_unpauseTimer != null)
		{
			FormatEx(line, sizeof(line), "%T", "PauseCountdown", target, g_unpauseCountdown);
			panel.DrawText(line);
		}
		panel.Send(target, PanelHandler, 2);
		delete panel;
	}
}

public int PanelHandler(Menu menu, MenuAction action, int param1, int param2) { return 0; }

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
	return g_isPaused && !g_internalPauseCommand ? Plugin_Handled : Plugin_Continue;
}

public Action ForwardSay(int client, const char[] command, int argc)
{
	if (!g_isPaused) return Plugin_Continue;
	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (!message[0] || message[0] == '!' || message[0] == '/') return Plugin_Continue;
	PrintToChatAll("%t", "PauseChat", client, message);
	return Plugin_Handled;
}

public Action ForwardTeamSay(int client, const char[] command, int argc)
{
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
		if (!IsClientConnected(client) || IsFakeClient(client)) continue;
		if (!IsClientInGame(client)) return false;
		g_loading[client] = false;
	}
	return true;
}

void ResetPauseState(bool unpause)
{
	if (unpause && g_isPaused) SetEnginePaused(false);
	CancelTimer(g_pauseDelayTimer);
	CancelTimer(g_deferredPauseTimer);
	CancelTimer(g_unpauseTimer);
	CancelTimer(g_pausePanelTimer);
	g_isPaused = false;
	g_adminPause = false;
	g_pendingAdminPause = false;
	g_internalPauseCommand = false;
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

int NativeIsInReady(Handle plugin, int params) { return g_readyPhase; }
int NativeIsInPause(Handle plugin, int params) { return g_isPaused; }

int NativeIsReady(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)) return false;
	if (g_isPaused) return g_playerReady[client];
	return g_readyPhase && !g_loading[client] && GetClientTeam(client) != TEAM_SPECTATORS;
}

int NativeToggleReadyPanel(Handle plugin, int params)
{
	if (!g_readyPhase) return false;
	bool show = GetNativeCell(1) != 0;
	int target = GetNativeCell(2);
	if (target > 0 && IsClientInGame(target))
	{
		bool old = !g_panelHidden[target];
		g_panelHidden[target] = !show;
		if (show) { if (g_isPaused) RenderPausePanel(); else RenderReadyPanel(); }
		return old;
	}
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client)) g_panelHidden[client] = !show;
	if (show) { if (g_isPaused) RenderPausePanel(); else RenderReadyPanel(); }
	return true;
}
