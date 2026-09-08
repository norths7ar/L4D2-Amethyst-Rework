#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define FIRST_NORMAL_SI 1
#define LAST_NORMAL_SI 6

ConVar g_cvEnable;
ConVar g_cvStuckTime;
ConVar g_cvMoveTolerance;
ConVar g_cvAttempts;
ConVar g_cvRetryDelay;

float g_lastOrigin[MAXPLAYERS + 1][3];
float g_lastProgress[MAXPLAYERS + 1];
float g_lastCombatInput[MAXPLAYERS + 1];
float g_lastMoveInput[MAXPLAYERS + 1];
float g_nextAttempt[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "SI Unstuck",
	author = "OpenAI",
	description = "Moves a stuck live AI special infected to a safe hidden nav position",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("si_unstuck_enable", "1", "Enable stuck AI SI relocation", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvStuckTime = CreateConVar("si_unstuck_time", "4.0", "Stationary time before relocation", FCVAR_NONE, true, 1.0);
	g_cvMoveTolerance = CreateConVar("si_unstuck_move_tolerance", "24.0", "Distance which counts as movement", FCVAR_NONE, true, 1.0);
	g_cvAttempts = CreateConVar("si_unstuck_attempts", "12", "Hidden spawn positions tested per relocation", FCVAR_NONE, true, 1.0);
	g_cvRetryDelay = CreateConVar("si_unstuck_retry_delay", "2.0", "Delay after no safe destination was found", FCVAR_NONE, true, 0.1);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	CreateTimer(0.5, Timer_Monitor, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		ResetTracking(client);
	}
}

public void OnClientDisconnect(int client)
{
	ResetTracking(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		ResetTracking(client);
		g_nextAttempt[client] = GetGameTime() + g_cvStuckTime.FloatValue;
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (IsEligibleSI(client) && (buttons & (IN_ATTACK | IN_ATTACK2)))
	{
		g_lastCombatInput[client] = GetGameTime();
	}
	if (IsEligibleSI(client) && (buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)))
	{
		g_lastMoveInput[client] = GetGameTime();
	}
	return Plugin_Continue;
}

public Action Timer_Monitor(Handle timer)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleSI(client))
		{
			ResetTracking(client);
			continue;
		}

		float origin[3];
		GetClientAbsOrigin(client, origin);
		// An idle ambusher is not stuck. Only accumulate stationary time while
		// NextBot is issuing movement input and failing to make progress.
		if (now - g_lastMoveInput[client] > 1.0)
		{
			CopyVector(origin, g_lastOrigin[client]);
			g_lastProgress[client] = now;
			continue;
		}
		if (g_lastProgress[client] == 0.0 || GetVectorDistance(origin, g_lastOrigin[client]) >= g_cvMoveTolerance.FloatValue)
		{
			CopyVector(origin, g_lastOrigin[client]);
			g_lastProgress[client] = now;
			continue;
		}

		if (IsBusySI(client, now))
		{
			CopyVector(origin, g_lastOrigin[client]);
			g_lastProgress[client] = now;
			continue;
		}

		if (now < g_nextAttempt[client] || now - g_lastProgress[client] < g_cvStuckTime.FloatValue)
		{
			continue;
		}

		if (!IsPositionHidden(origin) || !TryRelocate(client, origin))
		{
			g_nextAttempt[client] = now + g_cvRetryDelay.FloatValue;
			continue;
		}

		GetClientAbsOrigin(client, g_lastOrigin[client]);
		g_lastProgress[client] = now;
		g_nextAttempt[client] = now + g_cvStuckTime.FloatValue;
	}
	return Plugin_Continue;
}

bool TryRelocate(int client, const float oldOrigin[3])
{
	int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	for (int attempt = 0; attempt < g_cvAttempts.IntValue; attempt++)
	{
		float destination[3];
		int anchor = GetRandomLivingSurvivor();
		if (anchor < 1 || !L4D_GetRandomPZSpawnPosition(anchor, zombieClass, 5, destination)
			|| GetVectorDistance(oldOrigin, destination) < 128.0
			|| !IsPositionHidden(destination)
			|| !IsSafeHull(client, destination)
			|| !HasPathToSurvivors(destination))
		{
			continue;
		}

		float zeroVelocity[3];
		TeleportEntity(client, destination, NULL_VECTOR, zeroVelocity);
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

bool IsSafeHull(int client, const float position[3])
{
	float mins[3], maxs[3];
	GetClientMins(client, mins);
	GetClientMaxs(client, maxs);
	// A crouched Hunter must also be able to stand up at the destination.
	if (maxs[2] < 72.0) maxs[2] = 72.0;
	TR_TraceHull(position, position, mins, maxs, MASK_PLAYERSOLID);
	return !TR_DidHit();
}

public bool TraceIgnorePlayers(int entity, int contentsMask)
{
	return entity < 1 || entity > MaxClients;
}

bool IsPositionHidden(const float position[3])
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
			point[2] += height * 36.0 + 2.0;
			TR_TraceRayFilter(eye, point, MASK_VISIBLE, RayType_EndPoint, TraceIgnorePlayers);
			if (!TR_DidHit()) return false;
		}
	}
	return true;
}

bool IsBusySI(int client, float now)
{
	if (now - g_lastCombatInput[client] < 1.0 || GetEntityMoveType(client) == MOVETYPE_LADDER)
	{
		return true;
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
	return zombieClass >= FIRST_NORMAL_SI && zombieClass <= LAST_NORMAL_SI;
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
