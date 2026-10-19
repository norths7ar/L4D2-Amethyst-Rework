#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#undef REQUIRE_EXTENSIONS
#include <actions>
#define REQUIRE_EXTENSIONS
#include <ai_diagnostics>

native bool IsInPause();
// Optional: ai_tank owns only its bounded obstacle jump/local recovery windows.
native bool AI_Tank_IsMovementOwned(int client);
// Optional command-ownership handoff; true means it already issued RESET.
native bool SI_AntiRetreat_YieldMovement(int client, float seconds);

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define FIRST_NORMAL_SI 1
#define LAST_NORMAL_SI 6
#define PROGRESS_SAMPLES 64

ConVar g_cvEnable;
ConVar g_cvStuckTime;
ConVar g_cvMoveTolerance;
ConVar g_cvAttempts;
ConVar g_cvRetryDelay;
ConVar g_cvTankEnable;
ConVar g_cvTankTime;
ConVar g_cvTankMinDistance;
ConVar g_cvRepath;
ConVar g_cvDiagnostics;

float g_lastOrigin[MAXPLAYERS + 1][3];
float g_lastProgress[MAXPLAYERS + 1];
float g_lastCombatInput[MAXPLAYERS + 1];
float g_lastMoveInput[MAXPLAYERS + 1];
float g_nextAttempt[MAXPLAYERS + 1];
int g_tankVictim[MAXPLAYERS + 1];
int g_siVictim[MAXPLAYERS + 1];
bool g_repathTried[MAXPLAYERS + 1];
bool g_loopStalled[MAXPLAYERS + 1];
float g_loopOrigin[MAXPLAYERS + 1][3];
float g_sampleOrigin[MAXPLAYERS + 1][PROGRESS_SAMPLES][3];
float g_sampleTime[MAXPLAYERS + 1][PROGRESS_SAMPLES];
float g_sampleTravel[MAXPLAYERS + 1][PROGRESS_SAMPLES];
int g_sampleCount[MAXPLAYERS + 1], g_sampleHead[MAXPLAYERS + 1];
float g_travel[MAXPLAYERS + 1];
char g_actionName[MAXPLAYERS + 1][ACTION_NAME_LENGTH];
char g_diagReason[MAXPLAYERS + 1][64];
char g_diagAction[MAXPLAYERS + 1][ACTION_NAME_LENGTH];
float g_nextDiag[MAXPLAYERS + 1], g_nextActionSample[MAXPLAYERS + 1];
bool g_retryNotified[MAXPLAYERS + 1];
bool g_centerShown[MAXPLAYERS + 1];
char g_centerNotice[192];
float g_centerNoticeUntil;
bool g_paused;
float g_pauseStarted;

public Plugin myinfo =
{
	name = "SI Unstuck",
	author = "OpenAI",
	description = "Moves a stuck live AI special infected to a safe hidden nav position",
	version = "1.3.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	MarkNativeAsOptional("IsInPause");
	MarkNativeAsOptional("AI_Tank_IsMovementOwned");
	MarkNativeAsOptional("SI_AntiRetreat_YieldMovement");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("si_unstuck_enable", "1", "Enable stuck AI SI relocation", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvStuckTime = CreateConVar("si_unstuck_time", "4.0", "Stationary time before relocation", FCVAR_NONE, true, 1.0);
	g_cvMoveTolerance = CreateConVar("si_unstuck_move_tolerance", "24.0", "Distance which counts as movement", FCVAR_NONE, true, 1.0);
	g_cvAttempts = CreateConVar("si_unstuck_attempts", "12", "Hidden spawn positions tested per relocation", FCVAR_NONE, true, 1.0);
	g_cvRetryDelay = CreateConVar("si_unstuck_retry_delay", "2.0", "Delay after no safe destination was found", FCVAR_NONE, true, 0.1);
	g_cvTankEnable = CreateConVar("tank_unstuck_enable", "0", "Enable stuck AI Tank relocation independently of normal SI", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvTankTime = CreateConVar("tank_unstuck_time", "8.0", "Tank stationary time before checking for safe relocation", FCVAR_NONE, true, 1.0);
	g_cvTankMinDistance = CreateConVar("tank_unstuck_min_distance", "300.0", "Minimum Tank destination distance from every living survivor", FCVAR_NONE, true, 100.0);
	g_cvRepath = CreateConVar("si_unstuck_repath", "1", "Try one native RESET per stationary normal SI episode before hidden relocation", _, true, 0.0, true, 1.0);
	g_cvDiagnostics = CreateConVar("si_unstuck_diagnostics_interval", "2.0", "Normal SI movement snapshot interval; 0 disables periodic snapshots, not state events", _, true, 0.0);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	CreateTimer(0.5, Timer_Monitor, _, TIMER_REPEAT);
	if (GetFeatureStatus(FeatureType_Native, "ActionsManager.Iterator") == FeatureStatus_Available)
	{
		for (int client = 1; client <= MaxClients; client++)
			if (IsNormalBot(client)) ActionsManager.Iterator(client, HookExistingAction);
	}
}

public void OnMapStart()
{
	g_paused = false;
	g_centerNoticeUntil = 0.0;
	for (int client = 1; client <= MaxClients; client++)
	{
		ResetTracking(client);
		ResetObservation(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_centerShown[client] = false;
	ResetTracking(client);
	ResetObservation(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		ResetTracking(client);
		ResetObservation(client);
		g_nextAttempt[client] = GetGameTime() + g_cvStuckTime.FloatValue;
		if (IsNormalBot(client))
		{
			float position[3];
			GetClientAbsOrigin(client, position);
			char detail[160];
			FormatEx(detail, sizeof(detail), "class=%d pos=%.1f,%.1f,%.1f enabled=%d",
				GetEntProp(client, Prop_Send, "m_zombieClass"), position[0], position[1], position[2], g_cvEnable.BoolValue);
			AIDiag_TryEvent(client, "si_spawn", detail);
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (IsWatchdogPaused()) return Plugin_Continue;
	if (IsEligibleSI(client) && (buttons & (IN_ATTACK | IN_ATTACK2)))
	{
		g_lastCombatInput[client] = GetGameTime();
	}
	if (IsEligibleSI(client) && ((buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP))
		|| (FloatAbs(vel[0]) > 1.0 || FloatAbs(vel[1]) > 1.0)))
	{
		g_lastMoveInput[client] = GetGameTime();
	}
	return Plugin_Continue;
}

public Action Timer_Monitor(Handle timer)
{
	if (IsWatchdogPaused()) return Plugin_Continue;
	float now = GetGameTime();
	int countdown;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleSI(client))
		{
			if (IsNormalBot(client)) ReportState(client, "skip_disabled");
			ResetTracking(client);
			continue;
		}

		float origin[3];
		bool tank = GetEntProp(client, Prop_Send, "m_zombieClass") == 8;
		float stuckTime = tank ? g_cvTankTime.FloatValue : g_cvStuckTime.FloatValue;
		GetClientAbsOrigin(client, origin);
		bool loop = !tank && RecordProgressSample(client, origin, now, stuckTime);
		bool moved = g_lastProgress[client] == 0.0 || GetVectorDistance(origin, g_lastOrigin[client]) >= g_cvMoveTolerance.FloatValue;
		if (moved && !loop)
		{
			CopyVector(origin, g_lastOrigin[client]);
			g_lastProgress[client] = now;
			g_retryNotified[client] = false;
			g_repathTried[client] = false;
			if (!tank) ReportState(client, "moving");
			continue;
		}

		if (IsBusySI(client, now))
		{
			CopyVector(origin, g_lastOrigin[client]);
			g_lastProgress[client] = now;
			g_retryNotified[client] = false;
			g_repathTried[client] = false;
			ClearProgressSamples(client);
			if (!tank) ReportState(client, "skip_busy_native_action");
			continue;
		}
		// A short out-and-back loop must not keep refreshing the 24-unit step
		// anchor forever. The bounded history also rejects long legitimate detours.
		if (loop && g_lastProgress[client] > now - stuckTime)
			g_lastProgress[client] = now - stuckTime;

		bool chase = tank && IsLivingSurvivor(GetClientOfUserId(g_tankVictim[client]));
		if (tank && now - g_lastProgress[client] >= 2.0
			&& !g_retryNotified[client] && (chase || now - g_lastMoveInput[client] <= 1.0))
		{
			int remaining = RoundToCeil(stuckTime - (now - g_lastProgress[client]));
			if (remaining > 0 && (countdown == 0 || remaining < countdown)) countdown = remaining;
		}

		if (now < g_nextAttempt[client] || now - g_lastProgress[client] < stuckTime)
		{
			if (!tank && now - g_lastProgress[client] < stuckTime) ReportState(client, "stationary");
			continue;
		}

		// No input alone is not evidence of being stuck: preserve idle ambushers
		// unless their current hull is embedded or no survivor route can be built.
		// A Tank with a live chase target is not an idle ambusher.
		// Rate-limit the path query as well as failed destination searches.
		bool moveInput = now - g_lastMoveInput[client] <= 1.0;
		bool embedded = false, path = false;
		if (!chase && !moveInput)
		{
			embedded = IsCurrentHullEmbedded(client, origin);
			if (!embedded) path = HasPathToSurvivors(origin);
		}
		// No-input recovery needs positive pursuit evidence, not just a nav route.
		// Unknown/idle ambush actions remain observation-only. Confirmed attack
		// positioning gets a longer stationary window before a bounded RESET.
		bool pursuit = !tank && HasPursuitIntent(client);
		if (!chase && !moveInput && !embedded && path
			&& (!pursuit || (!loop && now - g_lastProgress[client] < stuckTime * 2.0)))
		{
			if (!tank) ReportState(client, pursuit ? "skip_no_input_confirming_pursuit" : "skip_idle_nav_connected");
			g_nextAttempt[client] = now + g_cvRetryDelay.FloatValue;
			continue;
		}

		if (!tank && g_cvRepath.BoolValue && !g_repathTried[client])
		{
			// This timer is outside Actions propagation. No MOVE, teleport, jump
			// injection or generic injury suppression: let native AI rebuild first.
			g_repathTried[client] = true;
			if (!YieldRetreatMovement(client)) L4D2_CommandABot(client, 0, BOT_CMD_RESET);
			g_nextAttempt[client] = now + g_cvRetryDelay.FloatValue;
			ReportState(client, loop ? "loop_repath_reset_issued" : "repath_reset_issued");
			continue;
		}

		// A Tank stuck in a visible gap must still be rescued. Only its destination
		// must be hidden; retain the existing unseen-origin rule for normal SI.
		bool visible = !tank && !IsPositionHidden(origin);
		if (visible || !TryRelocate(client, origin))
		{
			if (!tank) ReportState(client, visible ? "skip_origin_visible" : "skip_no_safe_destination");
			g_nextAttempt[client] = now + g_cvRetryDelay.FloatValue;
			if (tank && !g_retryNotified[client])
			{
				NotifySurvivors("Tank 暂无安全传送位置，正在重试");
				g_retryNotified[client] = true;
			}
			continue;
		}

		if (tank) NotifySurvivors("Tank 已传送脱困");
		else ReportState(client, "relocated_hidden");
		g_retryNotified[client] = false;
		GetClientAbsOrigin(client, g_lastOrigin[client]);
		g_lastProgress[client] = now;
		g_nextAttempt[client] = now + stuckTime;
		g_repathTried[client] = false;
		ClearProgressSamples(client);
	}
	ShowTankCountdown(countdown);
	return Plugin_Continue;
}

public Action L4D2_OnChooseVictim(int client, int &target)
{
	if (IsNormalBot(client)) g_siVictim[client] = IsLivingSurvivor(target) ? GetClientUserId(target) : 0;
	if (client > 0 && client <= MaxClients && IsClientInGame(client)
		&& GetEntProp(client, Prop_Send, "m_zombieClass") == 8)
		g_tankVictim[client] = IsLivingSurvivor(target) ? GetClientUserId(target) : 0;
	return Plugin_Continue;
}

bool IsLivingSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client);
}

void NotifySurvivors(const char[] message)
{
	// One result notice takes priority over countdowns, without delaying rescue.
	strcopy(g_centerNotice, sizeof(g_centerNotice), message);
	g_centerNoticeUntil = GetGameTime() + 3.0;
}

void ShowTankCountdown(int remaining)
{
	bool notice = GetGameTime() < g_centerNoticeUntil;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client)) continue;
		bool show = (notice || remaining > 0) && GetClientTeam(client) == TEAM_SURVIVOR;
		if (show && notice) PrintCenterText(client, "%s", g_centerNotice);
		else if (show) PrintCenterText(client, "Tank 卡住，预计 %d 秒后尝试传送", remaining);
		else if (g_centerShown[client]) PrintCenterText(client, "");
		g_centerShown[client] = show;
	}
}

public void OnPluginEnd()
{
	g_centerNoticeUntil = 0.0;
	ShowTankCountdown(0);
}

public void OnPause() { SetWatchdogPaused(true); }
public void OnUnpause() { SetWatchdogPaused(false); }

bool IsWatchdogPaused()
{
	if (GetFeatureStatus(FeatureType_Native, "IsInPause") == FeatureStatus_Available)
		SetWatchdogPaused(IsInPause());
	else SetWatchdogPaused(false);
	return g_paused;
}

void SetWatchdogPaused(bool paused)
{
	if (g_paused == paused) return;
	float now = GetGameTime();
	if (paused) g_pauseStarted = now;
	else
	{
		// Game time may freeze with the engine, but can advance during a logical
		// pause. Exclude only the elapsed game time, without restarting the 8s.
		float elapsed = now - g_pauseStarted;
		if (g_centerNoticeUntil > g_pauseStarted) g_centerNoticeUntil += elapsed;
		for (int client = 1; client <= MaxClients; client++)
		{
			if (g_lastProgress[client] > 0.0) g_lastProgress[client] += elapsed;
			if (g_lastCombatInput[client] > 0.0) g_lastCombatInput[client] += elapsed;
			if (g_lastMoveInput[client] > 0.0) g_lastMoveInput[client] += elapsed;
			if (g_nextAttempt[client] > 0.0) g_nextAttempt[client] += elapsed;
			if (g_nextDiag[client] > 0.0) g_nextDiag[client] += elapsed;
			for (int sample = 0; sample < g_sampleCount[client]; sample++)
				g_sampleTime[client][sample] += elapsed;
		}
	}
	g_paused = paused;
}

bool TryRelocate(int client, const float oldOrigin[3])
{
	int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	bool tank = zombieClass == 8;
	float maxs[3];
	GetClientMaxs(client, maxs);
	for (int attempt = 0; attempt < g_cvAttempts.IntValue; attempt++)
	{
		float destination[3];
		int anchor = GetRandomLivingSurvivor();
		if (anchor < 1 || !L4D_GetRandomPZSpawnPosition(anchor, zombieClass, 5, destination)
			|| GetVectorDistance(oldOrigin, destination) < 128.0
			|| !IsPositionHidden(destination, tank ? maxs[2] : 74.0)
			|| (tank && !IsTankDestinationFarEnough(destination))
			|| !IsSafeHull(client, destination)
			|| !HasPathToSurvivors(destination))
		{
			continue;
		}

		float zeroVelocity[3];
		bool reset = !tank && YieldRetreatMovement(client);
		TeleportEntity(client, destination, NULL_VECTOR, zeroVelocity);
		if (!tank)
		{
			char detail[192];
			FormatEx(detail, sizeof(detail), "from=%.1f,%.1f,%.1f to=%.1f,%.1f,%.1f",
				oldOrigin[0], oldOrigin[1], oldOrigin[2], destination[0], destination[1], destination[2]);
			AIDiag_TryEvent(client, "si_relocate", detail);
		}
		if (!reset) L4D2_CommandABot(client, 0, BOT_CMD_RESET);
		return true;
	}
	return false;
}

bool HasPathToSurvivors(const float destination[3])
{
	Address startArea = L4D_GetNearestNavArea(destination, 200.0, true, true, true, TEAM_INFECTED);
	if (startArea == Address_Null)
	{
		return false;
	}

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsClientInGame(survivor) || GetClientTeam(survivor) != TEAM_SURVIVOR || !IsPlayerAlive(survivor))
		{
			continue;
		}
		float survivorOrigin[3];
		GetClientAbsOrigin(survivor, survivorOrigin);
		Address endArea = L4D_GetNearestNavArea(survivorOrigin, 200.0, true, false, true, TEAM_INFECTED);
		if (endArea != Address_Null && L4D2_NavAreaBuildPath(startArea, endArea, 10000.0, TEAM_INFECTED, false))
		{
			return true;
		}
	}
	return false;
}

bool YieldRetreatMovement(int client)
{
	return GetFeatureStatus(FeatureType_Native, "SI_AntiRetreat_YieldMovement") == FeatureStatus_Available
		&& SI_AntiRetreat_YieldMovement(client, g_cvRetryDelay.FloatValue);
}

// Use the actual current hull, not the standing destination hull: a crouched
// Hunter under a low ceiling is not necessarily embedded. Ignore only self.
bool IsCurrentHullEmbedded(int client, const float position[3])
{
	float mins[3], maxs[3];
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);
	TR_TraceHullFilter(position, position, mins, maxs, MASK_PLAYERSOLID, TraceIgnoreSelf, client);
	return TR_StartSolid() || TR_AllSolid();
}

public bool TraceIgnoreSelf(int entity, int contentsMask, any client)
{
	return entity != client;
}

bool IsSafeHull(int client, const float position[3])
{
	float mins[3], maxs[3];
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);
	// A crouched Hunter must also be able to stand up at the destination.
	if (maxs[2] < 72.0) maxs[2] = 72.0;
	TR_TraceHullFilter(position, position, mins, maxs, MASK_PLAYERSOLID, TraceIgnoreSelf, client);
	return !TR_DidHit();
}

public bool TraceIgnorePlayers(int entity, int contentsMask)
{
	return entity < 1 || entity > MaxClients;
}

bool IsPositionHidden(const float position[3], float top = 74.0)
{
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsClientInGame(survivor) || GetClientTeam(survivor) != TEAM_SURVIVOR || !IsPlayerAlive(survivor))
		{
			continue;
		}
		float eye[3];
		GetClientEyePosition(survivor, eye);
		for (int height = 0; height < 3; height++)
		{
			float point[3];
			CopyVector(position, point);
			point[2] += height * (top - 2.0) / 2.0 + 2.0;
			TR_TraceRayFilter(eye, point, MASK_VISIBLE, RayType_EndPoint, TraceIgnorePlayers);
			if (!TR_DidHit()) return false;
		}
	}
	return true;
}

bool IsBusySI(int client, float now)
{
	bool tank = GetEntProp(client, Prop_Send, "m_zombieClass") == 8;
	if (tank)
	{
		if (GetFeatureStatus(FeatureType_Native, "AI_Tank_IsMovementOwned") == FeatureStatus_Available
			&& AI_Tank_IsMovementOwned(client)) return true;
		// anim_hulk sequence numbers: climbing/ladders, shoves, attacks/throws,
		// victory/rage and flinches. Never rescue a Tank during these actions.
		int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
		if ((sequence >= 2 && sequence <= 4) || (sequence >= 16 && sequence <= 31) || (sequence >= 33 && sequence <= 64)
			|| (GetEntityFlags(client) & FL_FROZEN)) return true;
	}
	// Other plugins may veto a Tank's attack request later in RunCmd. Its
	// actual attack animations above, not raw buttons, own the busy state.
	if ((!tank && now - g_lastCombatInput[client] < 1.0) || GetEntityMoveType(client) == MOVETYPE_LADDER)
	{
		return true;
	}

	if (!tank)
	{
		if (GetEntityFlags(client) & FL_FROZEN) return true;
		// Charge has already stopped during the queued-pummel transition, but
		// the Charger is still engine-owned and must not be reset/relocated.
		if (GetEntProp(client, Prop_Send, "m_zombieClass") == 6
			&& L4D2_GetQueuedPummelVictim(client) > 0) return true;
		int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
		if (ability > MaxClients && IsValidEntity(ability))
		{
			// Active ability flags outlive attack input. A cooldown timestamp does
			// not mean the ability is still executing, so do not use it here.
			static const char activeProps[][] = {
				"m_isCharging", "m_isLunging", "m_isLeaping", "m_isSpraying"
			};
			for (int i = 0; i < sizeof(activeProps); i++)
			{
				if (HasEntProp(ability, Prop_Send, activeProps[i])
					&& GetEntProp(ability, Prop_Send, activeProps[i]) != 0) return true;
			}
		}
	}

	static const char victimProps[][] = {
		"m_tongueVictim", "m_pounceVictim", "m_carryVictim", "m_pummelVictim", "m_jockeyVictim"
	};
	for (int i = 0; i < sizeof(victimProps); i++)
	{
		if (HasEntProp(client, Prop_Send, victimProps[i]) && GetEntPropEnt(client, Prop_Send, victimProps[i]) > 0)
		{
			return true;
		}
	}

	// CountdownTimer element 1 is the expiry timestamp (Left4DHooks), not duration.
	return HasEntProp(client, Prop_Send, "m_staggerTimer")
		&& GetEntPropFloat(client, Prop_Send, "m_staggerTimer", 1) > now;
}

bool IsEligibleSI(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client)
		|| GetClientTeam(client) != TEAM_INFECTED || !IsPlayerAlive(client)
		|| GetEntProp(client, Prop_Send, "m_isGhost") != 0
		|| GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return false;
	}
	int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	return zombieClass == 8 ? g_cvTankEnable.BoolValue
		: g_cvEnable.BoolValue && zombieClass >= FIRST_NORMAL_SI && zombieClass <= LAST_NORMAL_SI;
}

bool IsTankDestinationFarEnough(const float position[3])
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client)) continue;
		float origin[3];
		GetClientAbsOrigin(client, origin);
		if (GetVectorDistance(position, origin) < g_cvTankMinDistance.FloatValue) return false;
	}
	return true;
}

void ResetTracking(int client)
{
	g_lastOrigin[client][0] = 0.0;
	g_lastOrigin[client][1] = 0.0;
	g_lastOrigin[client][2] = 0.0;
	g_lastProgress[client] = 0.0;
	g_lastCombatInput[client] = 0.0;
	g_lastMoveInput[client] = 0.0;
	g_nextAttempt[client] = 0.0;
	g_tankVictim[client] = 0;
	g_retryNotified[client] = false;
	g_siVictim[client] = 0;
	g_repathTried[client] = false;
	ClearProgressSamples(client);
}

bool IsNormalBot(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client)
		|| GetClientTeam(client) != TEAM_INFECTED || !IsPlayerAlive(client)
		|| GetEntProp(client, Prop_Send, "m_isGhost") != 0) return false;
	int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	return zombieClass >= FIRST_NORMAL_SI && zombieClass <= LAST_NORMAL_SI;
}

void ClearProgressSamples(int client)
{
	g_sampleCount[client] = 0;
	g_sampleHead[client] = 0;
	g_travel[client] = 0.0;
	g_loopStalled[client] = false;
}

bool RecordProgressSample(int client, const float origin[3], float now, float stuckTime)
{
	float tolerance = g_cvMoveTolerance.FloatValue;
	float radius = tolerance * 4.0;
	if (radius < 128.0) radius = 128.0;
	if (g_loopStalled[client])
	{
		// Do not count the next leg of the same pacing loop as fresh progress.
		// Clear only on escape, an engine-owned action, or lifecycle reset.
		if (GetVectorDistance(origin, g_loopOrigin[client]) <= radius) return true;
		ClearProgressSamples(client);
	}
	int head = g_sampleHead[client];
	if (g_sampleCount[client] > 0)
	{
		int previous = (head + PROGRESS_SAMPLES - 1) % PROGRESS_SAMPLES;
		g_travel[client] += GetVectorDistance(origin, g_sampleOrigin[client][previous]);
	}
	CopyVector(origin, g_sampleOrigin[client][head]);
	g_sampleTime[client][head] = now;
	g_sampleTravel[client][head] = g_travel[client];
	g_sampleHead[client] = (head + 1) % PROGRESS_SAMPLES;
	if (g_sampleCount[client] < PROGRESS_SAMPLES) g_sampleCount[client]++;
	float travelRequired = tolerance * 2.0;
	if (travelRequired < 128.0) travelRequired = 128.0;
	bool returned = false;
	for (int offset = 1; offset < g_sampleCount[client]; offset++)
	{
		int sample = (head + PROGRESS_SAMPLES - offset) % PROGRESS_SAMPLES;
		float age = now - g_sampleTime[client][sample];
		if (age > stuckTime * 2.0) break;
		float distance = GetVectorDistance(origin, g_sampleOrigin[client][sample]);
		// A large excursion is a real route/detour, not fence-side pacing.
		if (distance > radius) break;
		if (age >= stuckTime && distance < tolerance
			&& g_travel[client] - g_sampleTravel[client][sample] >= travelRequired) returned = true;
	}
	if (returned)
	{
		g_loopStalled[client] = true;
		CopyVector(origin, g_loopOrigin[client]);
	}
	return returned;
}

bool HasPursuitIntent(int client)
{
	if (!IsLivingSurvivor(GetClientOfUserId(g_siVictim[client]))
		|| GetGameTime() > g_nextActionSample[client] + 1.0) return false;
	return StrEqual(g_actionName[client], "ChargerAttack")
		|| StrEqual(g_actionName[client], "SmokerMoveToAttackPosition")
		|| StrEqual(g_actionName[client], "BehaviorMoveTo");
}

public void HookExistingAction(BehaviorAction action)
{
	char name[ACTION_NAME_LENGTH];
	action.GetName(name, sizeof(name));
	OnActionCreated(action, action.Actor, name);
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	if (action == INVALID_ACTION || !IsNormalBot(actor)) return;
	// Observation only; the anti-retreat plugin owns action intervention.
	action.OnStartPost = ObserveActionStart;
	action.OnResumePost = ObserveActionStart;
	action.OnUpdatePost = ObserveActionUpdate;
}

public Action ObserveActionStart(BehaviorAction action, int actor, BehaviorAction prior, ActionResult result)
{
	if (IsNormalBot(actor)) ObserveAction(action, actor);
	return Plugin_Continue;
}

public Action ObserveActionUpdate(BehaviorAction action, int actor, float interval, ActionResult result)
{
	if (IsNormalBot(actor) && GetGameTime() >= g_nextActionSample[actor]) ObserveAction(action, actor);
	return Plugin_Continue;
}

void ObserveAction(BehaviorAction action, int client)
{
	// Only the active leaf represents movement intent, not its parent/root.
	if (action.IsSuspended || action.Child != INVALID_ACTION) return;
	g_nextActionSample[client] = GetGameTime() + 0.5;
	char name[ACTION_NAME_LENGTH];
	action.GetName(name, sizeof(name));
	if (StrEqual(name, g_actionName[client])) return;
	strcopy(g_actionName[client], sizeof(g_actionName[]), name);
	ReportState(client, "action_changed");
}

void ReportState(int client, const char[] reason)
{
	if (!IsNormalBot(client)) return;
	float now = GetGameTime();
	bool changed = !StrEqual(g_diagReason[client], reason) || !StrEqual(g_diagAction[client], g_actionName[client]);
	// Both state changes and snapshots have a per-client ceiling. A suppressed
	// change is retried next observation; identical skip reasons do not spam.
	if (now < g_nextDiag[client] || (!changed && g_cvDiagnostics.FloatValue == 0.0)) return;
	strcopy(g_diagReason[client], sizeof(g_diagReason[]), reason);
	strcopy(g_diagAction[client], sizeof(g_diagAction[]), g_actionName[client]);
	float interval = g_cvDiagnostics.FloatValue;
	if (interval < 1.0) interval = 1.0;
	g_nextDiag[client] = now + interval;
	float origin[3], velocity[3];
	GetClientAbsOrigin(client, origin);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
	char detail[384];
	FormatEx(detail, sizeof(detail), "reason=%s class=%d target=%d pos=%.1f,%.1f,%.1f speed=%.1f action=%s stalled=%.1f move_age=%.1f attack_age=%.1f repath=%d loop=%d",
		reason, GetEntProp(client, Prop_Send, "m_zombieClass"), GetClientOfUserId(g_siVictim[client]),
		origin[0], origin[1], origin[2], GetVectorLength(velocity), g_actionName[client],
		now - g_lastProgress[client], now - g_lastMoveInput[client], now - g_lastCombatInput[client], g_repathTried[client], g_loopStalled[client]);
	AIDiag_TryEvent(client, "si_unstuck", detail);
}

void ResetObservation(int client)
{
	g_actionName[client][0] = '\0';
	g_diagReason[client][0] = '\0';
	g_diagAction[client][0] = '\0';
	g_nextDiag[client] = 0.0;
	g_nextActionSample[client] = 0.0;
}

int GetRandomLivingSurvivor()
{
	int survivors[MAXPLAYERS + 1];
	int count;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client))
		{
			survivors[count++] = client;
		}
	}
	return count > 0 ? survivors[GetRandomInt(0, count - 1)] : -1;
}

void CopyVector(const float source[3], float destination[3])
{
	destination[0] = source[0];
	destination[1] = source[1];
	destination[2] = source[2];
}
