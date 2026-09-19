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
char g_reservationName[MAX_RESERVATIONS][MAX_NAME_LENGTH];
int g_reservationCharacter[MAX_RESERVATIONS];
int g_reservationSet[MAX_RESERVATIONS];
char g_reservationModel[MAX_RESERVATIONS][PLATFORM_MAX_PATH];
bool g_wantsSpectator[MAXPLAYERS + 1];
char g_loadedSteamId[MAXPLAYERS + 1][32];
StringMap g_reservations;

public Plugin myinfo =
{
	name = "Coop player manager",
	author = "海洋空氣, norths7ar",
	description = "Coop join, spectator, bot-slot and player-team lifecycle",
	version = "1.2.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
	CreateNative("Coop_GetHumanSurvivorCount", Native_GetHumanSurvivorCount);
	CreateNative("Coop_GetTotalSurvivorCount", Native_GetTotalSurvivorCount);
	CreateNative("Coop_IsHumanSurvivor", Native_IsHumanSurvivor);
	CreateNative("Coop_IsRoundLive", Native_IsRoundLive);
	CreateNative("Coop_ShouldKeepSurvivorBots", Native_ShouldKeepSurvivorBots);
	CreateNative("Coop_IsRosterStable", Native_IsRosterStable);
	CreateNative("Coop_GetWaitingSurvivor", Native_GetWaitingSurvivor);
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
	AddCommandListener(OnJoinTeamCommand, "jointeam");

	HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
	HookEvent("map_transition", EventMapTransition, EventHookMode_Post);
	HookEvent("player_team", EventPlayerTeam, EventHookMode_Post);
	HookEvent("player_disconnect", EventPlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_spawn", EventCharacterSpawn);
	HookEvent("bot_player_replace", EventCharacterTransfer);
	HookEvent("player_bot_replace", EventCharacterTransfer);
	for (int client = 1; client <= MaxClients; client++)
		if (IsHumanClient(client)) CreateTimer(0.2, TimerCheckHumanTeam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void EventPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!event.GetBool("disconnect"))
	{
		// A restored identity remains protected from late loaders, but team
		// events must never turn it back into an outstanding loading wait.
		CreateTimer(0.2, TimerCheckHumanTeam, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnJoinTeamCommand(int client, const char[] command, int argc)
{
	if (!IsHumanClient(client) || argc < 1) return Plugin_Continue;
	char team[16];
	GetCmdArg(1, team, sizeof(team));
	if (StringToInt(team) == TEAM_SPECTATORS || StrEqual(team, "spectator", false))
	{
		g_wantsSpectator[client] = true;
		g_requestToken[client]++;
		int reservation = FindReservation(client);
		if (ValidReservation(reservation)) ClearReservation(reservation);
	}
	else if (StringToInt(team) == TEAM_SURVIVORS || StrEqual(team, "survivor", false))
	{
		g_wantsSpectator[client] = false;
		int reservation = FindReservation(client);
		if (ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SPECTATOR)
		{
			g_requestToken[client]++;
			ClearReservation(reservation);
		}
	}
	return Plugin_Continue;
}

public Action TimerCheckHumanTeam(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsHumanClient(client) || g_transitionCaptured) return Plugin_Stop;
	int reservation = FindReservation(client);
	if (g_wantsSpectator[client] || (ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SPECTATOR))
	{
		g_wantsSpectator[client] = true;
		if (GetClientTeam(client) != TEAM_SPECTATORS) ChangeClientTeam(client, TEAM_SPECTATORS);
		ClaimReservation(client);
	}
	else if (GetClientTeam(client) == TEAM_INFECTED)
	{
		// Anne join.sp also checks the actual team event: command-only checks miss
		// the automatic Versus assignment while a human is connecting.
		ChangeClientTeam(client, TEAM_SPECTATORS);
		CommandJoin(client, 0);
	}
	else if (GetClientTeam(client) == TEAM_SURVIVORS)
	{
		if (ValidReservation(reservation))
		{
			MakeRoomForReturningSurvivor(client);
			ClaimReservation(client);
		}
		else if (GetAdmissionCount(-1) > g_maxSurvivors.IntValue)
		{
			ChangeClientTeam(client, TEAM_SPECTATORS);
			PrintToChat(client, "%t", "SeatsReserved");
		}
	}
	else if (ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SURVIVOR)
		ScheduleMoveToSurvivors(client);
	return Plugin_Stop;
}

public Action L4D_OnEnterGhostStatePre(int client)
{
	if (!IsHumanClient(client)) return Plugin_Continue;
	CreateTimer(0.1, TimerCheckHumanTeam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public void OnMapStart()
{
	g_generation++;
	g_roundLive = false;
	CancelBotCleanup();
	g_transitionCaptured = false;
	// Loading the destination map must not consume the player's return window.
	for (int i = 0; i < MAX_RESERVATIONS; i++)
		if (g_reservationRole[i] != 0 && g_reservationGeneration[i] == g_generation)
			g_reservationExpires[i] = GetTime() + RoundToNearest(RESERVATION_TTL);
	for (int client = 1; client <= MaxClients; client++)
	{
		g_pendingReservation[client] = -1;
		if (IsHumanClient(client)) CreateTimer(0.2, TimerCheckHumanTeam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
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
	g_loadedSteamId[client][0] = '\0';
	if (!IsFakeClient(client)) CancelBotCleanup();
	g_pendingReservation[client] = -1;
	g_requestToken[client]++;
	g_wantsSpectator[client] = false;
	if (!IsFakeClient(client)) CreateTimer(0.2, TimerCheckHumanTeam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client)
{
	// This callback runs after both entering the game and Steam authentication.
	if (!IsHumanClient(client)) return;
	GetClientAuthId(client, AuthId_SteamID64, g_loadedSteamId[client], sizeof(g_loadedSteamId[]), true);
	g_pendingReservation[client] = FindReservation(client);
	if (ValidReservation(g_pendingReservation[client])) ScheduleReservationRestore(client, 0, g_reservationRole[g_pendingReservation[client]]);
	CreateTimer(0.2, TimerCheckHumanTeam, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void EventPlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || IsFakeClient(client)) return;
	char reason[128];
	event.GetString("reason", reason, sizeof(reason));
	if (!StrEqual(reason, "Disconnect by user.", false)) return;
	// Explicit quit releases even a not-yet-restored next-map reservation.
	char steamId[32];
	int value;
	if (g_loadedSteamId[client][0]) strcopy(steamId, sizeof(steamId), g_loadedSteamId[client]);
	else GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), false);
	if (steamId[0] && g_reservations.GetValue(steamId, value)) ClearReservation(value - 1);
}

public void OnClientDisconnect(int client)
{
	// Reservations are created only by map_transition. Once loaded into the
	// destination, any disconnect releases that seat, including Steam errors.
	int value;
	if (!g_transitionCaptured && g_loadedSteamId[client][0]
		&& g_reservations.GetValue(g_loadedSteamId[client], value)) ClearReservation(value - 1);
	if (IsHumanClient(client))
	{
		if (g_roundLive && GetHumanSurvivors() == 1)
			ScheduleBotCleanup();
	}
	g_pendingReservation[client] = -1;
	g_loadedSteamId[client][0] = '\0';
}

public Action CommandJoin(int client, int args)
{
	if (!IsHumanClient(client)) return Plugin_Handled;
	int reservation = FindReservation(client);
	// An explicit join overrides a saved spectator role, just as !spec gives up
	// a survivor reservation. Engine team changes alone do neither.
	g_wantsSpectator[client] = false;
	g_requestToken[client]++;
	if (ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SPECTATOR) ClearReservation(reservation);
	if (GetClientTeam(client) == TEAM_SURVIVORS) { ClaimReservation(client); return Plugin_Handled; }
	bool returningSurvivor = ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SURVIVOR;
	if (!returningSurvivor && GetAdmissionCount(-1) >= g_maxSurvivors.IntValue)
	{
		PrintToChat(client, "%t", "SeatsReserved");
		return Plugin_Handled;
	}
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
	g_wantsSpectator[client] = true;
	int reservation = FindReservation(client);
	if (ValidReservation(reservation)) ClearReservation(reservation);
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
	SetServerInt("director_no_survivor_bots", 0);
	SetServerInt("survivor_limit", g_maxSurvivors.IntValue);
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
	// With ready_pause loaded, its Live forward owns the round boundary.
	if (!LibraryExists("readyup") && !g_roundLive) OnRoundIsLive();
}

public void OnRoundIsLive()
{
	g_roundLive = true;
	bool waiting = CountValidReservations(RESERVATION_SURVIVOR) > 0;
	for (int i = 0; i < MAX_RESERVATIONS; i++) ClearReservation(i);
	for (int client = 1; client <= MaxClients; client++) g_requestToken[client]++;
	if (waiting) PrintToChatAll("%t", "SeatProtectionEnded");
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
	if (g_wantsSpectator[client] && desiredRole == RESERVATION_SURVIVOR) return Plugin_Stop;
	if (desiredRole == RESERVATION_SPECTATOR)
	{
		g_wantsSpectator[client] = true;
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
	int reservation = FindReservation(client);
	if (ValidReservation(reservation)) MakeRoomForReturningSurvivor(client);
	else if (GetClientTeam(client) != TEAM_SURVIVORS && GetAdmissionCount(-1) >= g_maxSurvivors.IntValue) return Plugin_Stop;
	if (GetClientTeam(client) == TEAM_SURVIVORS)
	{
		ClaimReservation(client);
		return Plugin_Stop;
	}
	if (attempt >= 10) return Plugin_Stop;
	if (!g_roundLive && GetTotalSurvivors() < g_maxSurvivors.IntValue) SpawnSurvivorBot();
	int bot = FindSurvivorBot(reservation);
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
	if (g_reservationRole[reservation] == RESERVATION_SURVIVOR)
	{
		RestoreReservedCharacter(client, reservation);
		if (!g_reservationClaimed[reservation]) PrintToChat(client, "%t", "SeatRestored");
		// Retain the identity until live/expiry so a later slow loader cannot
		// displace somebody whose original seat was already restored.
		g_reservationClaimed[reservation] = true;
	}
	else ClearReservation(reservation);
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

void RememberRole(int client, int targetGeneration)
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
	GetClientName(client, g_reservationName[index], sizeof(g_reservationName[]));
	g_reservationRole[index] = GetClientTeam(client) == TEAM_SURVIVORS ? RESERVATION_SURVIVOR : RESERVATION_SPECTATOR;
	g_reservationExpires[index] = GetTime() + RoundToNearest(RESERVATION_TTL);
	g_reservationGeneration[index] = targetGeneration;
	g_reservationClaimed[index] = false;
	g_reservationModel[index][0] = '\0';
	if (GetClientTeam(client) == TEAM_SURVIVORS)
	{
		g_reservationCharacter[index] = GetEntProp(client, Prop_Send, "m_survivorCharacter");
		g_reservationSet[index] = L4D2_GetSurvivorSetMod();
		GetClientModel(client, g_reservationModel[index], sizeof(g_reservationModel[]));
	}
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
		if (ValidReservation(i) && g_reservationRole[i] == role && !g_reservationClaimed[i] && !ReservationIsOccupied(i)) count++;
	return count;
}

void ClearReservation(int index)
{
	if (index < 0 || index >= MAX_RESERVATIONS) return;
	if (g_reservationSteam[index][0]) g_reservations.Remove(g_reservationSteam[index]);
	g_reservationSteam[index][0] = '\0';
	g_reservationRole[index] = 0;
	g_reservationModel[index][0] = '\0';
	g_reservationExpires[index] = 0;
	g_reservationGeneration[index] = 0;
	g_reservationClaimed[index] = false;
}

public Action TimerReservationCleanup(Handle timer)
{
	for (int i = 0; i < MAX_RESERVATIONS; i++)
		if (g_reservationRole[i] != 0 && !ValidReservation(i, true))
		{
			if (g_reservationGeneration[i] == g_generation && g_reservationRole[i] == RESERVATION_SURVIVOR && !g_reservationClaimed[i])
				PrintToChatAll("%t", "SeatExpired", g_reservationName[i]);
			ClearReservation(i);
		}
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
		if (i != excludeReservation && ValidReservation(i) && g_reservationRole[i] == RESERVATION_SURVIVOR && !g_reservationClaimed[i] && !ReservationIsOccupied(i)) count++;
	return count;
}

bool ReservationIsOccupied(int reservation)
{
	int team = g_reservationRole[reservation] == RESERVATION_SURVIVOR ? TEAM_SURVIVORS : TEAM_SPECTATORS;
	for (int client = 1; client <= MaxClients; client++)
		if (IsHumanClient(client) && GetClientTeam(client) == team && FindReservation(client) == reservation) return true;
	return false;
}

void MakeRoomForReturningSurvivor(int returning)
{
	// Rework fix_team_shuffle restores ownership by first moving newcomers out
	// of reserved seats. Use Steam identities here, not its PvP winner indices.
	for (int client = MaxClients; client >= 1 && GetAdmissionCount(-1) > g_maxSurvivors.IntValue; client--)
	{
		if (client == returning || !IsHumanSurvivor(client) || ValidReservation(FindReservation(client))) continue;
		ChangeClientTeam(client, TEAM_SPECTATORS);
		PrintToChat(client, "%t", "SeatsReserved");
	}
}

int FindSurvivorBot(int reservation = -1)
{
	int fallback;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsAvailableSurvivorBot(client)) continue;
		if (!fallback) fallback = client;
		if (CharacterReservationApplies(reservation)
			&& GetEntProp(client, Prop_Send, "m_survivorCharacter") == g_reservationCharacter[reservation]) return client;
	}
	return fallback;
}

bool IsAvailableSurvivorBot(int client)
{
	return IsClientInGame(client) && IsFakeClient(client) && !IsClientInKickQueue(client)
		&& GetClientTeam(client) == TEAM_SURVIVORS && L4D_GetIdlePlayerOfBot(client) <= 0;
}

bool CharacterReservationApplies(int reservation)
{
	// A map changing survivor sets owns that change; do not force old voices/models into it.
	return ValidReservation(reservation) && g_reservationRole[reservation] == RESERVATION_SURVIVOR
		&& g_reservationModel[reservation][0] && g_reservationSet[reservation] == L4D2_GetSurvivorSetMod();
}

void RestoreReservedCharacter(int client, int reservation)
{
	if (!IsHumanSurvivor(client) || !CharacterReservationApplies(reservation) || g_transitionCaptured) return;
	// Validate the complete ownership chain before writing. Returning humans may
	// have been auto-assigned each other's characters; restore their own records
	// together rather than treating that permutation as a permanent conflict.
	int clients[MAXPLAYERS + 1], records[MAXPLAYERS + 1], count;
	bool visited[MAXPLAYERS + 1];
	int current = client;
	int matchingBot;
	while (current > 0 && !visited[current])
	{
		int record = FindReservation(current);
		if (!IsHumanSurvivor(current) || !CharacterReservationApplies(record)) return;
		int character = g_reservationCharacter[record];
		for (int i = 0; i < count; i++)
			if (g_reservationCharacter[records[i]] == character) return;
		visited[current] = true;
		clients[count] = current;
		records[count++] = record;
		int occupant;
		for (int other = 1; other <= MaxClients; other++)
		{
			if (other == current || !IsClientInGame(other)) continue;
			int team = GetClientTeam(other);
			if (team != TEAM_SURVIVORS && team != 4) continue;
			if (GetEntProp(other, Prop_Send, "m_survivorCharacter") != character) continue;
			// Never move scripted NPCs, idle-owned bots, or unreserved humans.
			if (team == 4 || occupant) return;
			if (!IsAvailableSurvivorBot(other) && !IsHumanSurvivor(other)) return;
			occupant = other;
		}
		if (occupant && IsAvailableSurvivorBot(occupant)) { matchingBot = occupant; current = 0; break; }
		current = occupant;
	}
	if (current > 0 && visited[current] && current != client) return;
	if (matchingBot)
	{
		char oldModel[PLATFORM_MAX_PATH];
		GetClientModel(client, oldModel, sizeof(oldModel));
		SetEntProp(matchingBot, Prop_Send, "m_survivorCharacter", GetEntProp(client, Prop_Send, "m_survivorCharacter"));
		SetEntityModel(matchingBot, oldModel);
	}
	for (int i = 0; i < count; i++)
	{
		int record = records[i];
		PrecacheModel(g_reservationModel[record], true);
		SetEntProp(clients[i], Prop_Send, "m_survivorCharacter", g_reservationCharacter[record]);
		SetEntityModel(clients[i], g_reservationModel[record]);
	}
}

public void EventCharacterSpawn(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.2, TimerRestoreCharacter, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action TimerRestoreCharacter(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (IsHumanSurvivor(client)) RestoreReservedCharacter(client, FindReservation(client));
	return Plugin_Stop;
}

public void EventCharacterTransfer(Event event, const char[] name, bool dontBroadcast)
{
	int player = GetClientOfUserId(event.GetInt("player"));
	int bot = GetClientOfUserId(event.GetInt("bot"));
	if (player <= 0 || bot <= 0 || !IsClientInGame(player) || !IsClientInGame(bot)) return;
	bool toPlayer = StrEqual(name, "bot_player_replace");
	int source = toPlayer ? bot : player;
	int destination = toPlayer ? player : bot;
	if (GetClientTeam(destination) != TEAM_SURVIVORS) return;
	// Anne character_manager preserves both fields across engine ownership transfers.
	char model[PLATFORM_MAX_PATH];
	GetClientModel(source, model, sizeof(model));
	SetEntProp(destination, Prop_Send, "m_survivorCharacter", GetEntProp(source, Prop_Send, "m_survivorCharacter"));
	SetEntityModel(destination, model);
	if (toPlayer) CreateTimer(0.2, TimerRestoreCharacter, GetClientUserId(player), TIMER_FLAG_NO_MAPCHANGE);
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
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && !IsClientInKickQueue(client);
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
	for (int client = 1; client <= MaxClients; client++) if (IsClientInGame(client) && !IsClientInKickQueue(client) && GetClientTeam(client) == TEAM_SURVIVORS) count++;
	return count;
}

int Native_GetHumanSurvivorCount(Handle plugin, int params) { return GetHumanSurvivors(); }
int Native_GetTotalSurvivorCount(Handle plugin, int params) { return GetTotalSurvivors(); }
int Native_IsHumanSurvivor(Handle plugin, int params) { return IsHumanSurvivor(GetNativeCell(1)); }
int Native_IsRoundLive(Handle plugin, int params) { return g_roundLive; }
int Native_ShouldKeepSurvivorBots(Handle plugin, int params) { return g_allowBotSurvivors.BoolValue; }

int Native_IsRosterStable(Handle plugin, int params)
{
	return CountValidReservations(RESERVATION_SURVIVOR) == 0;
}

int Native_GetWaitingSurvivor(Handle plugin, int params)
{
	int ordinal = GetNativeCell(1);
	for (int i = 0; i < MAX_RESERVATIONS; i++)
	{
		if (!ValidReservation(i) || g_reservationRole[i] != RESERVATION_SURVIVOR || g_reservationClaimed[i] || ReservationIsOccupied(i)) continue;
		if (ordinal-- > 0) continue;
		SetNativeString(2, g_reservationName[i], GetNativeCell(3), true);
		SetNativeCellRef(4, g_reservationExpires[i] - GetTime());
		return true;
	}
	return false;
}
