#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
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
bool g_startAreaUnavailable;
bool g_returnPending[MAXPLAYERS + 1];
bool g_returnAttempted[MAXPLAYERS + 1];
bool g_hasStartPosition[MAXPLAYERS + 1];
float g_startPosition[MAXPLAYERS + 1][3];
float g_nextStartAreaNotice;
Handle g_boundaryTimer;
int g_loadingTimeout[MAXPLAYERS + 1];
int g_countdownRemaining;
bool g_godMode;
ArrayList g_footer;
bool g_panelHidden[MAXPLAYERS + 1];
float g_panelStarted;
char g_pauseInitiator[MAX_NAME_LENGTH];
bool g_directorHeld;
int g_countdownParticipant[MAXPLAYERS + 1]; // Client serials captured when the start countdown begins.
Handle g_teamTimer[MAXPLAYERS + 1];
Handle g_enginePauseTimer;
bool g_enginePaused;

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
ConVar l4d_ready_enable_sound, l4d_ready_notify_sound, l4d_ready_countdown_sound, l4d_ready_live_sound;
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
#include "ready_pause/sound.inc"

public Plugin myinfo =
{
	name = "Coop ready and pause",
	author = "CanadaRox, 海洋空氣, norths7ar",
	description = "Per-player readiness, loading gate and start/resume countdowns",
	version = "1.2.0"
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
	l4d_ready_enable_sound = CreateConVar("l4d_ready_enable_sound", "1", "Enable ready sounds.", _, true, 0.0, true, 1.0);
	l4d_ready_notify_sound = CreateConVar("l4d_ready_notify_sound", DEFAULT_NOTIFY_SOUND, "Ready status sound, relative to sound/.");
	l4d_ready_countdown_sound = CreateConVar("l4d_ready_countdown_sound", DEFAULT_COUNTDOWN_SOUND, "Start countdown sound, relative to sound/.");
	l4d_ready_live_sound = CreateConVar("l4d_ready_live_sound", DEFAULT_LIVE_SOUND, "Round live sound, relative to sound/.");
	g_svPausable = FindConVar("sv_pausable");
	g_svNoclipDuringPause = FindConVar("sv_noclipduringpause");
	g_pauseDelay = CreateConVar("sm_pausedelay", "0", "Seconds before a normal coop pause begins.", _, true, 0.0);
	g_unpauseDelay = CreateConVar("sm_unpausedelay", "3", "Ready countdown before a pause ends.", _, true, 0.0);
	g_readyBlips = CreateConVar("sm_pause_ready_blips", "1", "Play a countdown sound before the round starts.", _, true, 0.0, true, 1.0);
	g_readyEnabled = CreateConVar("ready_enabled", "1", "Wait for returning survivors and each current survivor's readiness before starting.", _, true, 0.0, true, 1.0);
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
}

public void OnMapStart()
{
	g_readyPhase = false;
	SetReadyProtection(false);
	g_directorHeld = false;
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	CancelTimer(g_boundaryTimer);
	g_footer.Clear();
	for (int client = 1; client <= MaxClients; client++)
	{
		CancelTimer(g_teamTimer[client]);
		g_countdownParticipant[client] = 0;
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
	}
	PrecacheSound("ui/beep_error01.wav");
	PrecacheSounds();
	ResetPauseState(false);
	// Mode loads and the first map must also enter ready-up, not only restarts.
	BeginReadyPhase();
}

public void OnMapEnd()
{
	ToggleVoteCommandListener(false);
	ReleaseDirector();
	SetReadyProtection(false);
	SetSurvivorsFrozen(false);
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	CancelTimer(g_boundaryTimer);
	ResetPauseState(true);
	g_readyPhase = false;
}

public void OnPluginEnd()
{
	CancelTimer(g_boundaryTimer);
	ToggleVoteCommandListener(false);
	ReleaseDirector();
	SetReadyProtection(false);
	SetSurvivorsFrozen(false);
	ResetPauseState(true);
}

public void OnConfigsExecuted()
{
	PrecacheSounds();
	// A mode may load this plugin on an already running map. OnMapStart and
	// round_start establish the phase; the completed config batch reapplies the
	// engine hold without clearing player readiness or dispatching Live twice.
	if (g_readyPhase && g_readyEnabled.BoolValue)
	{
		SetReadyProtection(true);
		HoldDirector();
	}
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
	CancelTimer(g_teamTimer[client]);
	// Retain the captured serial until this countdown ends, even if a slot is reused.
	g_returnPending[client] = false;
	g_returnAttempted[client] = false;
	g_hasStartPosition[client] = false;
	g_loadingTimeout[client] = 0;
	g_panelHidden[client] = false;
	g_playerReady[client] = false;
	g_panelButtonTime[client] = GetEngineTime();
	if (g_isPaused && !IsFakeClient(client)) PrintToChatAll("%t", "PausePlayerJoined", client);
}

public void OnClientDisconnect(int client)
{
	CancelTimer(g_teamTimer[client]);
	if (!IsHumanSurvivor(client)) return;
	if (!g_readyPhase || IsCountdownParticipant(client)) CancelCountdown(client, "PlayerDisconnected");
	SetPlayerReady(client, false);
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
	// Do not teleport or issue client commands inside the Director detour.
	// A failed boundary can fire again before the original call has unwound.
	if (!g_startAreaUnavailable && client > 0 && client <= MaxClients)
		g_returnPending[client] = true;
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
	SetReadyProtection(false);
	CancelTimer(g_loadingTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	CancelTimer(g_boundaryTimer);
	SetSurvivorsFrozen(false);
	ReleaseDirector();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS) continue;
		SetEntProp(client, Prop_Data, "m_idrowndmg", 0);
		SetEntProp(client, Prop_Data, "m_idrownrestored", 0);
	}
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
	SetReadyProtection(false);
	SetSurvivorsFrozen(false);
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	CancelTimer(g_boundaryTimer);
	g_readyPhase = false;
	return Plugin_Continue;
}

void BeginReadyPhase()
{
	// Keep the pre-live lifecycle active even when the loading gate is disabled.
	// Consumers still receive OnRoundIsLive on the first real saferoom exit.
	g_readyPhase = true;
	g_startAreaUnavailable = false;
	g_nextStartAreaNotice = 0.0;
	g_forceStarted = false;
	SetReadyProtection(g_readyEnabled.BoolValue);
	g_countdownRemaining = 0;
	g_panelStarted = GetEngineTime();
	CancelTimer(g_loadingTimer);
	CancelTimer(g_countdownTimer);
	CancelTimer(g_panelTimer);
	CancelTimer(g_readyPanelCommandTimer);
	CancelTimer(g_boundaryTimer);
	SetSurvivorsFrozen(false);
	for (int client = 1; client <= MaxClients; client++)
	{
		CancelTimer(g_teamTimer[client]);
		g_countdownParticipant[client] = 0;
		g_loadingTimeout[client] = 0;
		g_panelHidden[client] = false;
		SetPlayerReady(client, false);
		g_returnPending[client] = false;
		g_returnAttempted[client] = false;
		g_hasStartPosition[client] = false;
	}
	if (!g_readyEnabled.BoolValue) { ToggleVoteCommandListener(false); ReleaseDirector(); return; }
	ToggleVoteCommandListener(true);
	// Same engine countdown suppression as competitive readyup/game.inc.
	CreateTimer(0.3, TimerHoldDirector, _, TIMER_FLAG_NO_MAPCHANGE);
	InvokeForward(g_forwardInitiatePre);
	g_footer.Clear();
	InvokeForward(g_forwardInitiate);
	g_boundaryTimer = CreateTimer(0.1, TimerReadyBoundary, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
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
	g_directorHeld = true;
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
	L4D2_CTimerStart(L4D2CT_MobSpawnTimer, GetRandomMobSpawnInterval());
}

// Competitive Rework readyup/game.inc; difficulty-specific engine intervals.
static float GetRandomMobSpawnInterval()
{
	static ConVar s_cvMinInterval, s_cvMaxInterval;

	static ConVar z_difficulty;
	static char s_sDifficulty[10] = "normal";

	if (L4D2_HasConfigurableDifficultySetting())
	{
		if (z_difficulty == null)
			z_difficulty = FindConVar("z_difficulty");

		char buffer[10];
		z_difficulty.GetString(buffer, sizeof(buffer));
		for (int i = 0; buffer[i]; i++) buffer[i] = CharToLower(buffer[i]);

		if (strcmp(buffer, "impossible") == 0)
			strcopy(buffer, sizeof(buffer), "expert");

		if (strcmp(buffer, s_sDifficulty) != 0)
		{
			strcopy(s_sDifficulty, sizeof(s_sDifficulty), buffer);

			s_cvMinInterval = null;
			s_cvMaxInterval = null;
		}
	}

	if (s_cvMinInterval == null)
	{
		char buffer[64];
		FormatEx(buffer, sizeof(buffer), "z_mob_spawn_min_interval_%s", s_sDifficulty);
		s_cvMinInterval = FindConVar(buffer);
		FormatEx(buffer, sizeof(buffer), "z_mob_spawn_max_interval_%s", s_sDifficulty);
		s_cvMaxInterval = FindConVar(buffer);
	}

	if (s_cvMinInterval == null || s_cvMaxInterval == null)
	{
		ThrowError("Missing convars for mob spawn interval!");
	}

	SetRandomSeed(GetTime());
	return GetRandomFloat(s_cvMinInterval.FloatValue, s_cvMaxInterval.FloatValue);
}

void SetReadyProtection(bool enabled)
{
	if (!enabled && !g_godMode) return;
	g_godMode = enabled;
	FindConVar("god").SetBool(enabled, .notify = false);
	FindConVar("sv_infinite_primary_ammo").SetBool(enabled, .notify = false);
}

void SetSurvivorsFrozen(bool frozen)
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS) SetReadyFrozen(client, frozen);
}

void SetReadyFrozen(int client, bool frozen)
{
	// Competitive Rework readyup/player.inc: release to the team's normal movement.
	SetEntityMoveType(client, frozen ? MOVETYPE_NONE : (GetClientTeam(client) == TEAM_SPECTATORS ? MOVETYPE_NOCLIP : MOVETYPE_WALK));
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_readyPhase || !g_readyEnabled.BoolValue || !g_startAreaUnavailable
		|| !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS || !IsPlayerAlive(client)) return Plugin_Continue;
	// Suppress voluntary movement, not gravity, moving platforms or map teleports.
	vel[0] = 0.0;
	vel[1] = 0.0;
	vel[2] = 0.0;
	buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP);
	return Plugin_Changed;
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
		if (g_readyPhase && !g_startAreaUnavailable)
		{
			MoveType movement = GetEntityMoveType(client);
			if (movement != MOVETYPE_NONE && movement != MOVETYPE_NOCLIP) SetReadyFrozen(client, true);
		}
}

public Action EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || IsFakeClient(client)) return Plugin_Continue;
	g_panelButtonTime[client] = GetEngineTime();
	if (!g_readyPhase && !g_isPaused) return Plugin_Continue;
	if (g_teamTimer[client] == null)
	{
		DataPack pack;
		g_teamTimer[client] = CreateDataTimer(0.1, TimerPlayerTeam, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(event.GetInt("oldteam"));
	}
	return Plugin_Continue;
}

public Action TimerPlayerTeam(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int oldTeam = pack.ReadCell();
	if (client <= 0 || !IsClientInGame(client)) return Plugin_Stop;
	g_teamTimer[client] = null;
	int team = GetClientTeam(client);
	if (team == oldTeam) return Plugin_Stop;
	if (team == TEAM_SPECTATORS && oldTeam == TEAM_SURVIVORS) SetReadyFrozen(client, false);
	if (!g_readyPhase && !g_isPaused) return Plugin_Stop;
	if (team == TEAM_SURVIVORS || oldTeam == TEAM_SURVIVORS)
	{
		SetPlayerReady(client, false);
		if (g_isPaused || IsCountdownParticipant(client)) CancelCountdown(client, "TeamChanged");
		if (g_isPaused) EvaluatePauseReady();
	}
	return Plugin_Stop;
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
	if (g_countdownRemaining > 0)
	{
		if (!AllSurvivorsReady()) CancelCountdown(0, "ReadinessChanged");
		return;
	}
	if (ReturningSurvivorsRestored() && AllSurvivorsReady()) StartCountdown();
}

// Rework ordinary/forced starts share the same countdown. Pause uses the same
// per-survivor readiness and presentation; only its completion action differs.
void StartCountdown()
{
	if (g_countdownTimer != null) return;
	for (int client = 1; client <= MaxClients; client++)
		g_countdownParticipant[client] = IsHumanSurvivor(client) ? GetClientSerial(client) : 0;
	g_countdownRemaining = g_isPaused ? g_unpauseDelay.IntValue : g_readyCountdownCvar.IntValue;
	if (g_readyPhase)
	{
		InvokeForward(g_forwardCountdownPre);
		// Return before freezing, using the same observed and checked anchors as
		// !return / boundary enforcement, never warp_to_start_area spawn guesses.
		if (!g_startAreaUnavailable)
		{
			for (int client = 1; client <= MaxClients; client++)
			{
				if (!IsReadySurvivor(client)) continue;
				if (!MoveToReadyStart(client, false))
				{
					RestrictReadyMovement();
					break;
				}
			}
		}
		if (!g_startAreaUnavailable) SetSurvivorsFrozen(true);
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
	if (!g_isPaused && g_readyBlips.BoolValue) PlayCountdownSound();
}

public Action TimerCountdown(Handle timer)
{
	if (!g_isPaused && !g_readyPhase) { g_countdownTimer = null; return Plugin_Stop; }
	if (!g_forceStarted && (!AllSurvivorsReady() || (g_isPaused && g_adminPause)))
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
		PlayLiveSound();
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
	if (g_isPaused)
	{
		if (client > 0 && IsClientInGame(client)) PrintToChatAll("%t", "PauseCountdownCancelled", client);
		else PrintToChatAll("%t", "CountdownCancelled");
	}
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
	if (!g_startAreaUnavailable && client > 0 && client <= MaxClients)
		g_returnPending[client] = true;
}

bool IsReadySurvivor(int client)
{
	return IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS && IsPlayerAlive(client);
}

bool IsValidStartPosition(int client, float position[3])
{
	return L4D_IsPositionInFirstCheckpoint(position) && IsReturnPositionClear(client, position);
}

bool FindReadyReturnPosition(int client, float position[3])
{
	// Prefer this survivor's observed position; never guess an engine spawn point.
	if (g_hasStartPosition[client] && IsValidStartPosition(client, g_startPosition[client]))
	{
		position = g_startPosition[client];
		return true;
	}
	for (int other = 1; other <= MaxClients; other++)
	{
		if (!IsReadySurvivor(other) || !g_hasStartPosition[other]) continue;
		if (!IsValidStartPosition(client, g_startPosition[other])) continue;
		position = g_startPosition[other];
		return true;
	}
	return false;
}

void RestrictReadyMovement()
{
	if (g_startAreaUnavailable) return;
	g_startAreaUnavailable = true;
	SetSurvivorsFrozen(false);
	LogMessage("Starting checkpoint unavailable; restricting movement until ready");
	if (g_countdownRemaining <= 0) PrintToChatAll("%t", "ReadyStartAreaUnavailable");
	g_nextStartAreaNotice = GetEngineTime() + 30.0;
}

public Action TimerReadyBoundary(Handle timer)
{
	if (!g_readyPhase || !g_readyEnabled.BoolValue)
	{
		g_boundaryTimer = null;
		return Plugin_Stop;
	}
	if (g_startAreaUnavailable)
	{
		if (g_countdownRemaining > 0) g_nextStartAreaNotice = GetEngineTime() + 30.0;
		else if (GetEngineTime() >= g_nextStartAreaNotice)
		{
			PrintToChatAll("%t", "ReadyStartAreaUnavailable");
			g_nextStartAreaNotice = GetEngineTime() + 30.0;
		}
		return Plugin_Continue;
	}

	// Observe actual grounded starting positions before resolving any exits.
	// Airborne/script-controlled intros alone are not evidence of a bad checkpoint.
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsReadySurvivor(client) || !(GetEntityFlags(client) & FL_ONGROUND)) continue;
		float position[3];
		GetClientAbsOrigin(client, position);
		if (!IsValidStartPosition(client, position)) continue;
		if (!g_hasStartPosition[client]) g_startPosition[client] = position;
		g_hasStartPosition[client] = true;
		g_returnAttempted[client] = false;
	}
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!g_returnPending[client] || !IsReadySurvivor(client)) continue;
		// Allow map-controlled placement/falling to finish when no anchor exists.
		float destination[3];
		bool found = FindReadyReturnPosition(client, destination);
		if (!found && (!(GetEntityFlags(client) & FL_ONGROUND) || GetEntityMoveType(client) != MOVETYPE_WALK)) continue;
		if (!found || g_returnAttempted[client])
		{
			RestrictReadyMovement();
			break;
		}
		MoveToReadyStart(client, true);
	}
	return Plugin_Continue;
}

bool MoveToReadyStart(int client, bool notify)
{
	float destination[3], velocity[3];
	if (!FindReadyReturnPosition(client, destination)) return false;
	g_returnPending[client] = false;
	g_returnAttempted[client] = true;
	TeleportEntity(client, destination, NULL_VECTOR, velocity);
	SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", 0.0);
	if (notify) EmitSoundToClient(client, "ui/beep_error01.wav");
	return true;
}

bool IsReturnPositionClear(int client, const float position[3])
{
	float mins[3], maxs[3];
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);
	Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_PLAYERSOLID, ReturnPositionFilter);
	bool clear = !TR_StartSolid(trace) && !TR_AllSolid(trace) && !TR_DidHit(trace);
	delete trace;
	return clear;
}

public bool ReturnPositionFilter(int entity, int contentsMask)
{
	return entity < 1 || entity > MaxClients;
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
		SetPlayerReady(client, false);
		g_panelHidden[client] = false;
	}
	// Rework pause.sp sends the initial panel before its delayed engine pause.
	ToggleVoteCommandListener(true);
	UpdatePausePanel();
	g_panelTimer = CreateTimer(1.0, TimerRefreshPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	g_enginePauseTimer = CreateTimer(0.1, TimerEnginePause, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerEnginePause(Handle timer)
{
	g_enginePauseTimer = null;
	if (!g_isPaused) return Plugin_Stop;
	if (!SetEnginePaused(true)) { ResetPauseState(false); return Plugin_Stop; }
	g_enginePaused = true;
	PrintToChatAll("%t", g_adminPause ? "PauseAdmin" : "PauseStarted");
	InvokeForward(g_forwardPause);
	return Plugin_Stop;
}

bool SetPlayerReady(int client, bool ready)
{
	bool previous = g_playerReady[client];
	g_playerReady[client] = ready;
	if (previous != ready)
	{
		Call_StartForward(ready ? g_forwardPlayerReady : g_forwardPlayerUnready);
		Call_PushCell(client);
		Call_Finish();
	}
	return previous;
}

public Action CommandReady(int client, int args)
{
	if ((!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue)) || !IsHumanSurvivor(client)) return Plugin_Handled;
	if (!g_playerReady[client])
	{
		SetPlayerReady(client, true);
		if (!g_isPaused) PlayNotifySound(client);
		PrintToChatAll("%t", "PlayerReady", client);
	}
	if (g_isPaused) EvaluatePauseReady();
	else EvaluateStartReady();
	RenderPanel();
	return Plugin_Handled;
}

public Action CommandUnready(int client, int args)
{
	if (!g_isPaused && !(g_readyPhase && g_readyEnabled.BoolValue)) return Plugin_Handled;
	bool admin = CheckCommandAccess(client, "sm_forcestart", ADMFLAG_BAN);
	if (g_forceStarted)
	{
		if (!admin) return Plugin_Handled;
		g_forceStarted = false;
		CancelCountdown(client, "PlayerUnready");
		for (int target = 1; target <= MaxClients; target++) SetPlayerReady(target, false);
	}
	else
	{
		if (!IsHumanSurvivor(client) && !admin) return Plugin_Handled;
		if (IsHumanSurvivor(client) && SetPlayerReady(client, false))
		{
			if (!g_isPaused) PlayNotifySound(client);
			PrintToChatAll("%t", "PlayerUnready", client);
		}
		if (g_isPaused || admin || IsCountdownParticipant(client)) CancelCountdown(client, "PlayerUnready");
	}
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

bool IsCountdownParticipant(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client)
		&& g_countdownParticipant[client] != 0 && g_countdownParticipant[client] == GetClientSerial(client);
}

bool AllSurvivorsReady()
{
	int humans;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_readyPhase && g_countdownRemaining > 0)
		{
			if (!g_countdownParticipant[client]) continue;
			if (!IsCountdownParticipant(client) || !IsHumanSurvivor(client)) return false;
		}
		else if (!IsHumanSurvivor(client)) continue;
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
	CancelTimer(g_enginePauseTimer);
	bool changed = g_enginePaused && SetEnginePaused(false);
	g_enginePaused = false;
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
		if (!IsClientInGame(client) || IsFakeClient(client)) continue;
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

bool ReturningSurvivorsRestored()
{
	// Only the previous chapter's outstanding survivor reservations hold start.
	return LibraryExists("player_manager")
		&& GetFeatureStatus(FeatureType_Native, "Coop_IsRosterStable") == FeatureStatus_Available
		&& Coop_IsRosterStable();
}

void ResetPauseState(bool unpause)
{
	for (int client = 1; client <= MaxClients; client++) CancelTimer(g_teamTimer[client]);
	ToggleVoteCommandListener(false);
	CancelTimer(g_enginePauseTimer);
	if (unpause && g_enginePaused) SetEnginePaused(false);
	g_enginePaused = false;
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
	for (int client = 1; client <= MaxClients; client++) SetPlayerReady(client, false);
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
	if (client < 1 || client > MaxClients) return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
	if (!IsClientInGame(client)) return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
	return g_playerReady[client];
}

int NativeToggleReadyPanel(Handle plugin, int params)
{
	if (!g_readyPhase && !g_isPaused) return false;
	bool show = GetNativeCell(1) != 0;
	int target = GetNativeCell(2);
	if (target > 0 && IsClientInGame(target))
	{
		bool old = g_panelHidden[target];
		g_panelHidden[target] = !show;
		if (show) RenderPanel();
		return old;
	}
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && !IsFakeClient(client)) g_panelHidden[client] = !show;
	if (show) RenderPanel();
	return true;
}
