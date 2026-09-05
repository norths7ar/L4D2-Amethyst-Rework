#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define TEAM_SPECTATORS 1
#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3
#define MAX_RESERVATIONS 64
#define RESERVATION_TTL 120.0
#define RESERVATION_SURVIVOR 1
#define RESERVATION_SPECTATOR 2

ConVar g_maxSurvivors;
ConVar g_allowBotSurvivors;
ConVar g_slayBotTime;

bool g_roundLive;
Handle g_cleanupTimer;
bool g_transitionCaptured;
int g_generation;
int g_pendingReservation[MAXPLAYERS + 1];
int g_requestToken[MAXPLAYERS + 1];
char g_reservationSteam[MAX_RESERVATIONS][32];
int g_reservationRole[MAX_RESERVATIONS];
int g_reservationExpires[MAX_RESERVATIONS];
int g_reservationGeneration[MAX_RESERVATIONS];
bool g_reservationClaimed[MAX_RESERVATIONS];
StringMap g_reservations;

public Plugin myinfo =
{
	name = "Coop player manager",
	author = "海洋空氣, norths7ar",
	description = "Coop join, spectator, bot-slot and player-team lifecycle",
	version = "1.0.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
	CreateNative("Coop_GetHumanSurvivorCount", Native_GetHumanSurvivorCount);
	CreateNative("Coop_GetTotalSurvivorCount", Native_GetTotalSurvivorCount);
	CreateNative("Coop_IsHumanSurvivor", Native_IsHumanSurvivor);
	CreateNative("Coop_IsRoundLive", Native_IsRoundLive);
	CreateNative("Coop_ShouldKeepSurvivorBots", Native_ShouldKeepSurvivorBots);
	CreateNative("Coop_IsRosterStable", Native_IsRosterStable);
	RegPluginLibrary("player_manager");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("player_manager.phrases");
	g_reservations = new StringMap();
	CreateTimer(5.0, TimerReservationCleanup, _, TIMER_REPEAT);

	g_maxSurvivors = CreateConVar("human_survivor_limit", "4", "Maximum human survivor slots.");
	g_allowBotSurvivors = CreateConVar("keep_survivor_bots", "0", "Keep survivor bots after the round starts.");
	g_slayBotTime = CreateConVar("survivor_bot_cleanup_delay", "10.0", "Seconds before bots are slain after the last survivor leaves.");

	RegConsoleCmd("sm_join", CommandJoin, "Join the survivor team.");
	RegConsoleCmd("sm_joingame", CommandJoin, "Join the survivor team.");
	RegConsoleCmd("sm_jg", CommandJoin, "Join the survivor team.");
	RegConsoleCmd("sm_spectate", CommandSpectate, "Move to spectator.");
	RegConsoleCmd("sm_spec", CommandSpectate, "Move to spectator.");
	RegConsoleCmd("sm_s", CommandSpectate, "Move to spectator.");
	RegConsoleCmd("sm_away", CommandSpectate, "Move to spectator.");
	RegConsoleCmd("sm_kill", CommandKill, "Kill yourself.");
	RegConsoleCmd("sm_die", CommandKill, "Kill yourself.");
	RegConsoleCmd("sm_suicide", CommandKill, "Kill yourself.");
	RegConsoleCmd("sm_zs", CommandKill, "Kill yourself.");

	HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
	HookEvent("map_transition", EventMapTransition, EventHookMode_Post);
}

public void OnMapStart()
{
	g_generation++;
	g_roundLive = false;
	CancelBotCleanup();
	g_transitionCaptured = false;
	for (int client = 1; client <= MaxClients; client++)
		g_pendingReservation[client] = -1;
	SetServerInt("director_no_survivor_bots", 0);
	SetServerInt("survivor_limit", g_maxSurvivors.IntValue);
}

public void OnMapEnd()
{
	g_roundLive = false;
	CancelBotCleanup();
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client)) CancelBotCleanup();
	g_pendingReservation[client] = -1;
	g_requestToken[client]++;
}

public void OnClientPostAdminCheck(int client)
{
	// This callback runs after both entering the game and Steam authentication.
	if (!IsHumanClient(client)) return;
	g_pendingReservation[client] = FindReservation(client);
	if (ValidReservation(g_pendingReservation[client])) ScheduleReservationRestore(client, 0, g_reservationRole[g_pendingReservation[client]]);
}

public void OnClientDisconnect(int client)
{
	if (IsHumanClient(client))
	{
		// map_transition already captured the next-map role/generation. A later
		// disconnect must not overwrite that reservation with the old generation.
		if (!g_transitionCaptured) RememberRole(client);
		if (g_roundLive && GetHumanSurvivors() == 1)
			ScheduleBotCleanup();
	}
	g_pendingReservation[client] = -1;
}

public Action CommandJoin(int client, int args)
{
	int reservation = g_pendingReservation[client];
	bool returningSurvivor = ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SURVIVOR && !g_reservationClaimed[reservation];
	if (ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SPECTATOR) return Plugin_Handled;
	if (!IsHumanClient(client) || (!returningSurvivor && GetAdmissionCount(-1) >= g_maxSurvivors.IntValue))
		return Plugin_Handled;
	CancelBotCleanup();
	if (g_roundLive)
	{
		if (GetTotalSurvivors() > GetHumanSurvivors())
		{
			ScheduleMoveToSurvivors(client);
			return Plugin_Handled;
		}
		PrintToChat(client, "%t", "JoinAfterStart");
		return Plugin_Handled;
	}
	while (GetTotalSurvivors() < g_maxSurvivors.IntValue && SpawnSurvivorBot()) {}
	ScheduleMoveToSurvivors(client);
	return Plugin_Handled;
}

public Action CommandSpectate(int client, int args)
{
	if (!IsHumanClient(client)) return Plugin_Handled;
	g_requestToken[client]++;
	if (GetClientTeam(client) == TEAM_SPECTATORS)
	{
		FakeClientCommand(client, "jointeam %d", TEAM_INFECTED);
		DataPack pack;
		CreateDataTimer(0.1, TimerFinishSpectate, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetClientSerial(client));
		pack.WriteCell(g_generation);
		pack.WriteCell(g_requestToken[client]);
		return Plugin_Handled;
	}
	if (GetClientTeam(client) == TEAM_SURVIVORS && g_roundLive && GetHumanSurvivors() == 1)
		ScheduleBotCleanup();
	ChangeClientTeam(client, TEAM_SPECTATORS);
	if (GetClientTeam(client) == TEAM_SPECTATORS) ClaimReservation(client);
	PrintToChatAll("%t", "PlayerSpectated", client);
	return Plugin_Handled;
}

public Action CommandKill(int client, int args)
{
	if (client <= 0 || !IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Handled;
	if (!g_roundLive)
	{
		PrintToChat(client, "%t", "RoundNotStarted");
		return Plugin_Handled;
	}
	ForcePlayerSuicide(client);
	return Plugin_Handled;
}

public Action EventRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_roundLive = false;
	CancelBotCleanup();
	return Plugin_Continue;
}

public Action EventMapTransition(Event event, const char[] name, bool dontBroadcast)
{
	CaptureReservations();
	g_transitionCaptured = true;
	g_roundLive = false;
	return Plugin_Continue;
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	g_roundLive = true;
	ReconcileBots();
}

public void L4D2_OnEndVersusModeRound_Post()
{
	if (!g_allowBotSurvivors.BoolValue)
	{
		SetServerInt("director_no_survivor_bots", 0);
		SetServerInt("survivor_limit", g_maxSurvivors.IntValue);
	}
	g_roundLive = false;
}

void ScheduleMoveToSurvivors(int client)
{
	ScheduleReservationRestore(client, 0, RESERVATION_SURVIVOR);
}

public Action TimerMoveToSurvivors(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int serial = pack.ReadCell();
	int generation = pack.ReadCell();
	int attempt = pack.ReadCell();
	int token = pack.ReadCell();
	int desiredRole = pack.ReadCell();
	if (generation != g_generation || !IsHumanClient(client) || GetClientSerial(client) != serial || token != g_requestToken[client]) return Plugin_Stop;
	if (desiredRole == RESERVATION_SPECTATOR)
	{
		if (GetClientTeam(client) == TEAM_SPECTATORS)
		{
			ClaimReservation(client);
			return Plugin_Stop;
		}
		if (attempt >= 10) return Plugin_Stop;
		ChangeClientTeam(client, TEAM_SPECTATORS);
		ScheduleReservationRestore(client, attempt + 1, desiredRole);
		return Plugin_Stop;
	}
	if (GetClientTeam(client) == TEAM_SURVIVORS)
	{
		ClaimReservation(client);
		return Plugin_Stop;
	}
	if (attempt >= 10) return Plugin_Stop;
	int bot = FindSurvivorBot();
	if (bot > 0)
	{
		char botName[64];
		GetClientName(bot, botName, sizeof(botName));
		FakeClientCommand(client, "jointeam 2 %s", botName);
	}
	else FakeClientCommand(client, "jointeam 2");
	ScheduleReservationRestore(client, attempt + 1, desiredRole);
	return Plugin_Stop;
}

void ScheduleReservationRestore(int client, int attempt, int desiredRole)
{
	DataPack pack;
	CreateDataTimer(attempt == 0 ? 0.7 : 0.25, TimerMoveToSurvivors, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(g_generation);
	pack.WriteCell(attempt);
	pack.WriteCell(g_requestToken[client]);
	pack.WriteCell(desiredRole);
}

void ClaimReservation(int client)
{
	// A completed manual team move also consumes an old reservation for this identity.
	int reservation = FindReservation(client);
	g_pendingReservation[client] = -1;
	if (!ValidReservation(reservation)) return;
	ClearReservation(reservation);
	CancelBotCleanup();
	ReconcileBots();
}

public Action TimerFinishSpectate(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int serial = pack.ReadCell();
	int generation = pack.ReadCell();
	int token = pack.ReadCell();
	if (generation == g_generation && token == g_requestToken[client] && IsHumanClient(client) && GetClientSerial(client) == serial)
	{
		ChangeClientTeam(client, TEAM_SPECTATORS);
		if (GetClientTeam(client) == TEAM_SPECTATORS) ClaimReservation(client);
	}
	return Plugin_Stop;
}

bool SpawnSurvivorBot()
{
	if (g_roundLive) return false;
	int fake = CreateFakeClient("CoopBot");
	if (fake <= 0) return false;
	ChangeClientTeam(fake, TEAM_SURVIVORS);
	if (!DispatchKeyValue(fake, "classname", "survivorbot") || !DispatchSpawn(fake))
	{
		char reason[128];
		FormatEx(reason, sizeof(reason), "%T", "BotSetupFailed", fake);
		KickClient(fake, reason);
		return false;
	}
	DataPack pack;
	CreateDataTimer(0.3, TimerKickFakeClient, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(fake));
	pack.WriteCell(GetClientSerial(fake));
	pack.WriteCell(g_generation);
	return true;
}

public Action TimerKickFakeClient(Handle timer, DataPack pack)
{
	pack.Reset();
	int fake = GetClientOfUserId(pack.ReadCell());
	int serial = pack.ReadCell();
	int generation = pack.ReadCell();
	if (generation != g_generation || fake <= 0 || !IsClientConnected(fake) || GetClientSerial(fake) != serial) return Plugin_Stop;
	char reason[128];
	FormatEx(reason, sizeof(reason), "%T", "BotPlaceholder", fake);
	KickClient(fake, reason);
	return Plugin_Stop;
}

void ScheduleBotCleanup()
{
	if (g_cleanupTimer != null) return;
	SetServerInt("director_no_survivor_bots", 0);
	g_cleanupTimer = CreateTimer(g_slayBotTime.FloatValue, TimerSlayBots, g_generation, TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerSlayBots(Handle timer, int generation)
{
	g_cleanupTimer = null;
	if (generation != g_generation || GetHumanSurvivors() > 0 || CountValidReservations(RESERVATION_SURVIVOR) > 0)
	{
		return Plugin_Stop;
	}
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS)
			ForcePlayerSuicide(client);
	return Plugin_Stop;
}

void CancelBotCleanup()
{
	if (g_cleanupTimer == null) return;
	delete g_cleanupTimer;
	g_cleanupTimer = null;
}

void CaptureReservations()
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsHumanClient(client) && (GetClientTeam(client) == TEAM_SURVIVORS || GetClientTeam(client) == TEAM_SPECTATORS)) RememberRole(client, g_generation + 1);
}

void RememberRole(int client, int targetGeneration = -1)
{
	char steamId[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), true)) return;
	int index;
	if (!g_reservations.GetValue(steamId, index) || index < 1 || index > MAX_RESERVATIONS || !StrEqual(g_reservationSteam[index - 1], steamId))
	{
		index = FindFreeReservation();
		if (index < 0) return;
		if (g_reservationSteam[index][0]) g_reservations.Remove(g_reservationSteam[index]);
		g_reservations.SetValue(steamId, index + 1);
	}
	else index--; // StringMap stores index + 1; FindFreeReservation returns a zero-based index.
	strcopy(g_reservationSteam[index], sizeof(g_reservationSteam[]), steamId);
	g_reservationRole[index] = GetClientTeam(client) == TEAM_SURVIVORS ? RESERVATION_SURVIVOR : RESERVATION_SPECTATOR;
	g_reservationExpires[index] = GetTime() + RoundToNearest(RESERVATION_TTL);
	g_reservationGeneration[index] = targetGeneration < 0 ? g_generation : targetGeneration;
	g_reservationClaimed[index] = false;
}

int FindReservation(int client)
{
	char steamId[32];
	if (!GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), true)) return -1;
	int value;
	if (!g_reservations.GetValue(steamId, value)) return -1;
	int index = value - 1;
	if (index < 0 || index >= MAX_RESERVATIONS || !StrEqual(g_reservationSteam[index], steamId)) return -1;
	if (!ValidReservation(index)) return -1;
	return index;
}

bool ValidReservation(int index, bool includeNextMap = false)
{
	return index >= 0 && index < MAX_RESERVATIONS
		&& g_reservationRole[index] != 0
		&& g_reservationExpires[index] >= GetTime()
		&& (g_reservationGeneration[index] == g_generation
			|| (includeNextMap && g_reservationGeneration[index] == g_generation + 1));
}

int FindFreeReservation()
{
	int oldest = 0;
	for (int i = 0; i < MAX_RESERVATIONS; i++)
	{
		// Preserve next-map records while map_transition is still capturing the roster.
		if (!ValidReservation(i, true)) return i;
		if (g_reservationExpires[i] < g_reservationExpires[oldest]) oldest = i;
	}
	return oldest;
}

int CountValidReservations(int role)
{
	int count;
	for (int i = 0; i < MAX_RESERVATIONS; i++)
		if (ValidReservation(i) && g_reservationRole[i] == role && !g_reservationClaimed[i]) count++;
	return count;
}

void ClearReservation(int index)
{
	if (index < 0 || index >= MAX_RESERVATIONS) return;
	if (g_reservationSteam[index][0]) g_reservations.Remove(g_reservationSteam[index]);
	g_reservationSteam[index][0] = '\0';
	g_reservationRole[index] = 0;
	g_reservationExpires[index] = 0;
	g_reservationGeneration[index] = 0;
	g_reservationClaimed[index] = false;
}

public Action TimerReservationCleanup(Handle timer)
{
	for (int i = 0; i < MAX_RESERVATIONS; i++)
		if (g_reservationRole[i] != 0 && !ValidReservation(i, true)) ClearReservation(i);
	ReconcileBots();
	return Plugin_Continue;
}

void ReconcileBots()
{
	int reserved = CountValidReservations(RESERVATION_SURVIVOR);
	if (g_allowBotSurvivors.BoolValue)
	{
		SetServerInt("director_no_survivor_bots", 0);
		return;
	}
	if (!g_roundLive) return;
	SetServerInt("director_no_survivor_bots", reserved > 0 ? 0 : 1);
	if (reserved > 0)
	{
		SetServerInt("survivor_limit", GetHumanSurvivors() + reserved);
		return;
	}
	SetServerInt("survivor_limit", GetHumanSurvivors());
	KickSurvivorBots();
}

int GetAdmissionCount(int excludeReservation)
{
	int count = GetHumanSurvivors();
	for (int i = 0; i < MAX_RESERVATIONS; i++)
		if (i != excludeReservation && ValidReservation(i) && g_reservationRole[i] == RESERVATION_SURVIVOR && !g_reservationClaimed[i]) count++;
	return count;
}

int FindSurvivorBot()
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS) return client;
	return 0;
}

void KickSurvivorBots()
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS)
			if (GetTotalSurvivors() > GetHumanSurvivors() + CountValidReservations(RESERVATION_SURVIVOR))
			{
				char reason[128];
				FormatEx(reason, sizeof(reason), "%T", "BotCleanup", client);
				KickClient(client, reason);
			}
}

void SetServerInt(const char[] name, int value)
{
	ConVar cvar = FindConVar(name);
	if (cvar != null) cvar.IntValue = value;
}

bool IsHumanClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

bool IsHumanSurvivor(int client)
{
	return IsHumanClient(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}

int GetHumanSurvivors()
{
	int count;
	for (int client = 1; client <= MaxClients; client++) if (IsHumanSurvivor(client)) count++;
	return count;
}

int GetTotalSurvivors()
{
	int count;
	for (int client = 1; client <= MaxClients; client++) if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS) count++;
	return count;
}

int Native_GetHumanSurvivorCount(Handle plugin, int params) { return GetHumanSurvivors(); }
int Native_GetTotalSurvivorCount(Handle plugin, int params) { return GetTotalSurvivors(); }
int Native_IsHumanSurvivor(Handle plugin, int params) { return IsHumanSurvivor(GetNativeCell(1)); }
int Native_IsRoundLive(Handle plugin, int params) { return g_roundLive; }
int Native_ShouldKeepSurvivorBots(Handle plugin, int params) { return g_allowBotSurvivors.BoolValue; }

int Native_IsRosterStable(Handle plugin, int params)
{
	for (int i = 0; i < MAX_RESERVATIONS; i++)
	{
		if (!ValidReservation(i)) continue;
		bool restored;
		int team = g_reservationRole[i] == RESERVATION_SURVIVOR ? TEAM_SURVIVORS : TEAM_SPECTATORS;
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsHumanClient(client) && GetClientTeam(client) == team && FindReservation(client) == i)
			{
				restored = true;
				break;
			}
		}
		if (!restored) return false;
	}
	return true;
}
