#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <sdktools>
#include <colors>

#define Z_TANK 8
#define TEAM_INFECTED 3

ConVar
	g_hBypassFlowDistance,
	g_hBypassExtraFlowDistance;

Handle
	g_hFlowCheckTimer;

float
	fFurthestFlow,
	fBypassFlow,
	fProgressFlowPercent,
	fPushWarningPercent;

bool
	announcedTankSpawn,
	announcedHordeResume,
	announcedHordeMax,
	tankInPlay,
	tankInPlayDelay;

bool manualStop, alarmHorde;

public Plugin myinfo = 
{
	name = "L4D2 Tank Horde Monitor",
	author = "Derpduck, Visor (l4d2_horde_equaliser)",
	description = "Automatic infinite-horde and manual horde control during tanks",
	version = "1.4.0",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

public void OnPluginStart()
{
	LoadTranslation("l4d2_tank_horde_monitor.phrases");
	RegAdminCmd("sm_stophorde", Command_StopHorde, ADMFLAG_CHEATS, "Stop new hordes during the current Tank fight");
	
	g_hBypassFlowDistance = FindConVar("director_tank_bypass_max_flow_travel");
	g_hBypassExtraFlowDistance = CreateConVar("l4d2_tank_bypass_extra_flow", "1500.0", "Extra allowed flow distance to bypass tanks during infinite events (0 = disabled)", FCVAR_NONE, true, 0.0);
	
	HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
	HookEvent("round_end", RoundEndEvent, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", TankSpawn, EventHookMode_PostNoCopy);
	HookEvent("player_death", TankDeath);
	HookEvent("triggered_car_alarm", CarAlarm, EventHookMode_PostNoCopy);
	HookEntityOutput("prop_car_alarm", "OnCarAlarmStart", CarAlarmOutput);
	HookEntityOutput("info_director", "OnPanicEventFinished", PanicFinished);
	HookEventEx("panic_event_finished", PanicFinishedEvent, EventHookMode_PostNoCopy);
}

Action Command_StopHorde(int client, int args)
{
	if (!FindTankClient()) {
		ReplyToCommand(client, "%t", "NoTank");
		return Plugin_Handled;
	}
	if (manualStop) {
		ReplyToCommand(client, "%t", "HordeStopped");
		return Plugin_Handled;
	}
	// Late loading has no tank_spawn event; otherwise keep the encounter baseline.
	if (!tankInPlay) {
		tankInPlay = true;
		fFurthestFlow = L4D2_GetFurthestSurvivorFlow();
		fBypassFlow = fFurthestFlow + g_hBypassFlowDistance.FloatValue;
	}
	manualStop = true;
	tankInPlayDelay = true;
	CPrintToChatAll("%t %t", "Tag", "HordeStopped");
	if (!announcedTankSpawn && !announcedHordeMax) {
		announcedTankSpawn = true;
		fProgressFlowPercent = GetFlowUntilBypass(L4D2_GetFurthestSurvivorFlow(), fBypassFlow);
		g_hFlowCheckTimer = CreateTimer(2.0, FlowCheckTimer, _, TIMER_REPEAT);
	}
	return Plugin_Handled;
}

void CarAlarm(Event event, const char[] name, bool dontBroadcast)
{
	alarmHorde = true;
}

void CarAlarmOutput(const char[] output, int caller, int activator, float delay)
{
	// The entity output marks the session early; the game event is a fallback.
	alarmHorde = true;
}

void PanicFinished(const char[] output, int caller, int activator, float delay)
{
	alarmHorde = false;
}

void PanicFinishedEvent(Event event, const char[] name, bool dontBroadcast)
{
	alarmHorde = false;
}

void RoundStartEvent(Event hEvent, const char[] name, bool dontBroadcast)
{
	ResetWarnings();
	TimerCleanUp();
	fBypassFlow = 0.0;
	fFurthestFlow = 0.0;
	fProgressFlowPercent = 0.0;
}

void RoundEndEvent(Event hEvent, const char[] name, bool dontBroadcast)
{
	ResetWarnings();
	TimerCleanUp();
	fBypassFlow = 0.0;
	fFurthestFlow = 0.0;
	fProgressFlowPercent = 0.0;
}

public void OnMapEnd()
{
	ResetWarnings();
	TimerCleanUp();
	fBypassFlow = 0.0;
	fFurthestFlow = 0.0;
	fProgressFlowPercent = 0.0;
}

void TankSpawn(Event event, const char[] name, bool dontBroadcast) 
{
	if (!tankInPlay){
		tankInPlay = true;

		// Find current highest flow, and where the bypass point is
		fFurthestFlow = L4D2_GetFurthestSurvivorFlow();
		fBypassFlow = fFurthestFlow + g_hBypassFlowDistance.FloatValue;

		if (!alarmHorde && IsInfiniteHordeActive() && !announcedTankSpawn){
			AnnounceTankSpawn();
		}
	}
}

void TankDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0 && IsInfected(client) && IsTank(client)) {
		CreateTimer(0.1, Timer_CheckTank, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnClientDisconnect(int client)
{
	// A Tank can leave without a player_death event.
	if (client > 0 && IsInfected(client) && IsTank(client)) {
		CreateTimer(0.1, Timer_CheckTank, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_CheckTank(Handle timer)
{
	int tankclient = FindTankClient();
	if (!tankclient || !IsPlayerAlive(tankclient)) {
		ResetWarnings();
		TimerCleanUp();
	}

	return Plugin_Stop;
}

void AnnounceTankSpawn()
{
	fProgressFlowPercent = GetFlowUntilBypass(fFurthestFlow, fBypassFlow);
	CPrintToChatAll("%t %t", "Tag", "TankPlay", fProgressFlowPercent);
	announcedTankSpawn = true;

	// Begin repeating flow checker
	g_hFlowCheckTimer = CreateTimer(2.0, FlowCheckTimer, _, TIMER_REPEAT);
}

Action FlowCheckTimer(Handle hTimer)
{
	if (!tankInPlay || announcedHordeResume || announcedHordeMax){
		g_hFlowCheckTimer = null;
		return Plugin_Stop;
	}

	if (alarmHorde) {
		return Plugin_Continue;
	}

	// Extra check to prevent rush warning misfiring if tank spawns on the same frame as a horde spawn
	if (!tankInPlayDelay){
		tankInPlayDelay = true;
	}

	// Return furthest achieved survivor flow
	fFurthestFlow = L4D2_GetFurthestSurvivorFlow();

	// Print warnings if approaching the bypass limit
	float fWarningPercent = GetFlowUntilBypass(fFurthestFlow, fBypassFlow);

	if (fProgressFlowPercent - fWarningPercent >= 1.0){
		fProgressFlowPercent = fWarningPercent;
		CPrintToChatAll("%t %t", "Tag", "UntilHordeStarts", fWarningPercent);
	}

	return Plugin_Continue;
}

public Action L4D_OnSpawnMob(int &amount)
{
	/////////////////////////////////////
	// - Called on Event Hordes.
	// - Called on Panic Event Hordes.
	// - Called on Natural Hordes.
	// - Called on Onslaught (Mini-finale or finale Scripts)

	// - Not Called on Boomer Hordes.
	// - Also called on z_spawn mob.
	////////////////////////////////////

	// Alarm and map waves share this entry point: exempt the whole panic session,
	// including overlapping map waves. Leave the shared pending queue untouched.
	if (alarmHorde) {
		return Plugin_Continue;
	}

	if (tankInPlay && (manualStop || IsInfiniteHordeActive())){
		// If survivors have already pushed past the extra bypass distance we can ignore this
		if (announcedHordeMax){
			return Plugin_Continue;
		} else {
			// Calculate how far survivors have pushed
			fFurthestFlow = L4D2_GetFurthestSurvivorFlow();
			float fPushAmount = (fFurthestFlow - fBypassFlow) / (g_hBypassFlowDistance.FloatValue + g_hBypassExtraFlowDistance.FloatValue);

			// Clamp values
			if (fPushAmount < 0.0){
				fPushAmount = 0.0;
			} else if (fPushAmount > 1.0){
				fPushAmount = 1.0;
			}

			// Have survivors pushed past the bypass point?
			if (!announcedHordeResume && tankInPlayDelay && fPushAmount >= 0.05){
				fPushWarningPercent = fPushAmount;
				int iPushPercent = RoundToNearest(fPushAmount * 100.0);
				CPrintToChatAll("%t %t", "Tag", "HordeResumed", iPushPercent);
				announcedHordeResume = true;
			}

			// Horde strength prints
			if (fPushAmount - fPushWarningPercent >= 0.20 && fPushAmount != 1.0 && announcedHordeResume){
				fPushWarningPercent = fPushAmount;
				int iPushPercent = RoundToNearest(fPushAmount * 100.0);
				CPrintToChatAll("%t %t", "Tag", "HordeStrength", iPushPercent);
			}

			// Have survivors have pushed past the extra distance we allow?
			if (fPushAmount == 1.0){
				CPrintToChatAll("%t %t", "Tag", "HordeVeryStrength");
				announcedHordeMax = true;
			}

			// Scale amount of horde per mob with how far survivors have pushed
			int iNewAmount = RoundToNearest(amount * fPushAmount);

			if (iNewAmount <= 0) {
				return Plugin_Handled;
			}
			if (iNewAmount == amount) {
				return Plugin_Continue;
			}
			amount = iNewAmount;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

bool IsInfiniteHordeActive()
{
	int countdown = GetHordeCountdown();
	return (countdown > -1 && countdown <= 10);
}

int GetHordeCountdown()
{
	return (CTimer_HasStarted(L4D2Direct_GetMobSpawnTimer())) ? RoundFloat(CTimer_GetRemainingTime(L4D2Direct_GetMobSpawnTimer())) : -1;
}

bool IsInfected(int client)
{
	return (IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED);
}

bool IsTank(int client)
{
	return (GetEntProp(client, Prop_Send, "m_zombieClass") == Z_TANK);
}

int FindTankClient()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsInfected(i) || !IsTank(i) || !IsPlayerAlive(i)) {
			continue;
		}
		
		return i; // Found tank, return
	}
	return 0;
}

float GetFlowUntilBypass(float fCurrentFlowValue, float fBypassFlowValue)
{
	float fCurrentFlowPercent = (fCurrentFlowValue / L4D2Direct_GetMapMaxFlowDistance());
	float fBypassFlowPercent = (fBypassFlowValue / L4D2Direct_GetMapMaxFlowDistance());
	float result = (fBypassFlowPercent - fCurrentFlowPercent) * 100;

	if (result < 0){
		result = 0.0;
	}

	return result;
}

void TimerCleanUp()
{
	if (g_hFlowCheckTimer != null){
		delete g_hFlowCheckTimer;
		g_hFlowCheckTimer = null;
	}
}

void ResetWarnings()
{
	manualStop = false;
	alarmHorde = false;
	tankInPlay = false;
	tankInPlayDelay = false;
	announcedTankSpawn = false;
	announcedHordeResume = false;
	announcedHordeMax = false;
	fPushWarningPercent = 0.0;
}

/**
 * Check if the translation file exists
 *
 * @param translation	Translation name.
 * @noreturn
 */
stock void LoadTranslation(const char[] translation)
{
	char
		sPath[PLATFORM_MAX_PATH],
		sName[64];

	FormatEx(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}
