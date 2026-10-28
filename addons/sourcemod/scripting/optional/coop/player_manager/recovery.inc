// Round-local reconnect state. Cross-map seat reservations remain in the manager.
#define RECOVERY_RECORDS 128
#define RECOVERY_SLOTS 5

enum struct RecoveryWeapon
{
	char classname[64];
	char melee[64];
	int clip;
	int reserve;
	int upgrades;
	int upgradedAmmo;
	int skin;
	bool dual;
}

enum struct RecoveryState
{
	char steam[32];
	bool captured;
	bool valid;
	bool alive;
	bool incap;
	bool ducked;
	int health;
	float buffer;
	int preHealth;
	int preBuffer;
	int revives;
	int thirdStrike;
	int dying;
	int character;
	char model[PLATFORM_MAX_PATH];
	float origin[3];
	float angles[3];
	float flow;
	int activeSlot;
	int incapClip;
}

ConVar g_recoveryEnabled;
ConVar g_recoveryDistance;
RecoveryState g_recovery[RECOVERY_RECORDS];
RecoveryWeapon g_recoveryWeapons[RECOVERY_RECORDS * RECOVERY_SLOTS];
int g_recoveryBody[MAXPLAYERS + 1];
bool g_recoveryDisconnectHandled[MAXPLAYERS + 1];
bool g_recoverySuppressDrops[MAXPLAYERS + 1];
bool g_recoveryApplying[MAXPLAYERS + 1];
bool g_recoveryNotified[MAXPLAYERS + 1];
bool g_recoveryAutoAttempted[MAXPLAYERS + 1];
bool g_recoveryRoundOpen = true;
int g_secondaryRestoreOffset;

void Recovery_Init()
{
	g_recoveryEnabled = CreateConVar("survivor_reconnect_enabled", "0", "Experimental round-local state and equipment recovery after abnormal disconnects.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_recoveryDistance = CreateConVar("survivor_reconnect_catchup_distance", "1500", "Route distance behind the survivor group before reconnect recovery moves near teammates.", FCVAR_NONE, true, 0.0);
	g_recoveryEnabled.AddChangeHook(Recovery_OnEnabledChanged);
	// Same L4D2 hidden-secondary offset used by l4d_weapon_limits / l4d2_magnum_incap.
	g_secondaryRestoreOffset = FindSendPropInfo("CTerrorPlayer", "m_iVersusTeam") - 20;
	HookEvent("round_end", Recovery_RoundEnd, EventHookMode_PostNoCopy);
	Recovery_Reset();
}

public void Recovery_OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	Recovery_Reset(g_recoveryRoundOpen);
}

public void Recovery_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	Recovery_Reset(false);
}

void Recovery_Reset(bool open = true)
{
	g_recoveryRoundOpen = open;
	for (int i = 0; i < RECOVERY_RECORDS; i++) Recovery_Clear(i);
	for (int i = 1; i <= MaxClients; i++) Recovery_ClientReset(i);
}

void Recovery_ClientReset(int client)
{
	g_recoveryBody[client] = INVALID_ENT_REFERENCE;
	g_recoveryDisconnectHandled[client] = false;
	g_recoverySuppressDrops[client] = false;
	g_recoveryApplying[client] = false;
	g_recoveryNotified[client] = false;
	g_recoveryAutoAttempted[client] = false;
}

bool Recovery_Enabled()
{
	return g_recoveryEnabled.BoolValue && !g_allowBotSurvivors.BoolValue && g_recoveryRoundOpen;
}

void Recovery_Clear(int index)
{
	g_recovery[index].steam[0] = '\0';
	g_recovery[index].captured = false;
	g_recovery[index].valid = false;
}

int Recovery_Find(int client, bool create = false)
{
	if (!Recovery_Enabled() || client <= 0 || client > MaxClients) return -1;
	char steam[32];
	strcopy(steam, sizeof(steam), g_loadedSteamId[client]);
	if (!steam[0] && IsClientConnected(client)) GetClientAuthId(client, AuthId_SteamID64, steam, sizeof(steam), false);
	if (!steam[0]) return -1;
	int free = -1;
	for (int i = 0; i < RECOVERY_RECORDS; i++)
	{
		if (StrEqual(g_recovery[i].steam, steam)) return i;
		if (!g_recovery[i].steam[0] && free < 0) free = i;
	}
	if (!create || free < 0) return -1;
	Recovery_Clear(free);
	strcopy(g_recovery[free].steam, sizeof(g_recovery[].steam), steam);
	return free;
}

bool Recovery_HasSave(int client)
{
	int index = Recovery_Find(client);
	return index >= 0 && g_recovery[index].valid;
}

int Recovery_Body(int client)
{
	if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS) return client;
	int bot = EntRefToEntIndex(g_recoveryBody[client]);
	return bot > 0 && bot <= MaxClients && IsClientInGame(bot) && IsFakeClient(bot) && GetClientTeam(bot) == TEAM_SURVIVORS ? bot : 0;
}

int Recovery_HiddenSecondary(int client)
{
	if (g_secondaryRestoreOffset <= 0 || !GetEntProp(client, Prop_Send, "m_isIncapacitated")) return -1;
	int weapon = GetEntDataEnt2(client, g_secondaryRestoreOffset);
	return weapon > MaxClients && IsValidEntity(weapon) ? weapon : -1;
}

void Recovery_Capture(int index, int body)
{
	g_recovery[index].captured = true;
	g_recovery[index].alive = IsPlayerAlive(body);
	bool hanging = GetEntProp(body, Prop_Send, "m_isHangingFromLedge") != 0;
	g_recovery[index].incap = GetEntProp(body, Prop_Send, "m_isIncapacitated") != 0 && !hanging;
	g_recovery[index].ducked = GetEntProp(body, Prop_Send, "m_bDucked") != 0;
	g_recovery[index].preHealth = L4D2Direct_GetPreIncapHealth(body);
	g_recovery[index].preBuffer = L4D2Direct_GetPreIncapHealthBuffer(body);
	g_recovery[index].health = hanging ? g_recovery[index].preHealth : GetClientHealth(body);
	g_recovery[index].buffer = hanging ? float(g_recovery[index].preBuffer) : L4D_GetTempHealth(body);
	g_recovery[index].revives = GetEntProp(body, Prop_Send, "m_currentReviveCount");
	g_recovery[index].thirdStrike = GetEntProp(body, Prop_Send, "m_bIsOnThirdStrike");
	g_recovery[index].dying = GetEntProp(body, Prop_Send, "m_isGoingToDie");
	g_recovery[index].character = GetEntProp(body, Prop_Send, "m_survivorCharacter");
	GetClientModel(body, g_recovery[index].model, sizeof(g_recovery[].model));
	GetClientAbsOrigin(body, g_recovery[index].origin);
	GetClientEyeAngles(body, g_recovery[index].angles);
	g_recovery[index].flow = Recovery_Flow(body);
	g_recovery[index].activeSlot = 0;
	int secondary = GetPlayerWeaponSlot(body, 1);
	g_recovery[index].incapClip = secondary > MaxClients && HasEntProp(secondary, Prop_Send, "m_iClip1") ? GetEntProp(secondary, Prop_Send, "m_iClip1") : -1;
	int active = GetEntPropEnt(body, Prop_Send, "m_hActiveWeapon");
	for (int slot = 0; slot < RECOVERY_SLOTS; slot++)
	{
		int w = index * RECOVERY_SLOTS + slot;
		g_recoveryWeapons[w].classname[0] = '\0';
		g_recoveryWeapons[w].melee[0] = '\0';
		if (!g_recovery[index].alive) continue;
		int weapon = GetPlayerWeaponSlot(body, slot);
		if (weapon == active) g_recovery[index].activeSlot = slot;
		int hidden = slot == 1 ? Recovery_HiddenSecondary(body) : -1;
		if (hidden > MaxClients) weapon = hidden;
		if (weapon <= MaxClients || !IsValidEntity(weapon)) continue;
		GetEntityClassname(weapon, g_recoveryWeapons[w].classname, sizeof(g_recoveryWeapons[].classname));
		g_recoveryWeapons[w].clip = HasEntProp(weapon, Prop_Send, "m_iClip1") ? GetEntProp(weapon, Prop_Send, "m_iClip1") : -1;
		g_recoveryWeapons[w].reserve = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") > 0 ? L4D_GetReserveAmmo(body, weapon) : 0;
		g_recoveryWeapons[w].skin = GetEntProp(weapon, Prop_Send, "m_nSkin");
		g_recoveryWeapons[w].dual = HasEntProp(weapon, Prop_Send, "m_isDualWielding") && GetEntProp(weapon, Prop_Send, "m_isDualWielding") != 0;
		g_recoveryWeapons[w].upgrades = HasEntProp(weapon, Prop_Send, "m_upgradeBitVec") ? GetEntProp(weapon, Prop_Send, "m_upgradeBitVec") : 0;
		g_recoveryWeapons[w].upgradedAmmo = HasEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded") ? GetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded") : 0;
		if (StrEqual(g_recoveryWeapons[w].classname, "weapon_melee"))
		{
			GetEntPropString(weapon, Prop_Data, "m_strMapSetScriptName", g_recoveryWeapons[w].melee, sizeof(g_recoveryWeapons[].melee));
			if (!g_recoveryWeapons[w].melee[0])
			{
				char model[PLATFORM_MAX_PATH];
				GetEntPropString(weapon, Prop_Data, "m_ModelName", model, sizeof(model));
				if (StrContains(model, "tonfa", false) != -1) strcopy(g_recoveryWeapons[w].melee, sizeof(g_recoveryWeapons[].melee), "tonfa");
			}
		}
	}
}

void Recovery_Strip(int body)
{
	int hidden = Recovery_HiddenSecondary(body);
	if (hidden > MaxClients)
	{
		SetEntDataEnt2(body, g_secondaryRestoreOffset, -1);
		RemoveEntity(hidden);
	}
	for (int slot = 0; slot < RECOVERY_SLOTS; slot++)
	{
		int weapon = GetPlayerWeaponSlot(body, slot);
		if (weapon <= MaxClients || !IsValidEntity(weapon)) continue;
		RemovePlayerItem(body, weapon);
		RemoveEntity(weapon);
	}
}

void Recovery_OnTransfer(int player, int bot, bool toPlayer)
{
	if (!Recovery_Enabled() || player <= 0 || bot <= 0 || !IsClientInGame(player) || !IsClientInGame(bot) || IsFakeClient(player)) return;
	if (toPlayer)
	{
		if (!g_recoveryDisconnectHandled[player]) g_recoverySuppressDrops[player] = false;
		// The old idle owner must not later recover a body somebody else took over.
		for (int owner = 1; owner <= MaxClients; owner++)
		{
			if (EntRefToEntIndex(g_recoveryBody[owner]) != bot) continue;
			g_recoveryBody[owner] = INVALID_ENT_REFERENCE;
			int old = Recovery_Find(owner);
			if (old >= 0 && !g_recovery[old].valid) Recovery_Clear(old);
		}
		g_recoveryBody[player] = INVALID_ENT_REFERENCE;
		int record = Recovery_Find(player);
		if (record >= 0 && !g_recovery[record].valid) Recovery_Clear(record);
		return;
	}
	g_recoveryBody[player] = EntIndexToEntRef(bot);
	if (g_recoverySuppressDrops[player] || g_recoveryApplying[player])
	{
		Recovery_Strip(bot);
		return;
	}
	// Explicit spectating leaves the original equipment for native BOT cleanup.
	if (g_wantsSpectator[player] || g_recoveryDisconnectHandled[player]) return;
	int index = Recovery_Find(player, true);
	if (index >= 0 && !g_recovery[index].valid) Recovery_Capture(index, bot);
}

bool Recovery_IsExplicitReason(const char[] reason)
{
	return StrEqual(reason, "Disconnect by user.", false) || StrEqual(reason, "Disconnect by user", false)
		|| StrContains(reason, "Kicked", false) == 0 || StrContains(reason, "Banned", false) == 0
		|| StrContains(reason, "#L4D_vote_kick", false) == 0;
}

void Recovery_OnDisconnect(int client, const char[] reason)
{
	if (!Recovery_Enabled() || client <= 0 || !IsClientConnected(client) || IsFakeClient(client)) return;
	// player_disconnect carries the reason before native body teardown.
	// OnClientDisconnect is only a fallback when that event was not observed.
	if (g_recoveryDisconnectHandled[client]) return;
	g_recoveryDisconnectHandled[client] = true;
	if (Recovery_IsExplicitReason(reason) || IsClientInKickQueue(client) || g_wantsSpectator[client])
	{
		int old = Recovery_Find(client);
		if (old >= 0) Recovery_Clear(old);
		return;
	}
	int index = Recovery_Find(client, true);
	if (index < 0) return;
	int body = Recovery_Body(client);
	// A reconnect that fails while still spectating must not replace its old save.
	if (body > 0)
	{
		if (!g_recovery[index].valid) Recovery_Capture(index, body);
		Recovery_Strip(body);
	}
	if (g_recovery[index].captured)
	{
		g_recovery[index].valid = true;
		g_recoverySuppressDrops[client] = true;
	}
	else Recovery_Clear(index);
}

void Recovery_ExplicitLeave(int client)
{
	if (!Recovery_Enabled() || g_recoveryApplying[client]) return;
	int index = Recovery_Find(client);
	if (index >= 0) Recovery_Clear(index);
}

void Recovery_ApplyWeapon(int weapon, int w, int client)
{
	if (HasEntProp(weapon, Prop_Send, "m_iClip1")) SetEntProp(weapon, Prop_Send, "m_iClip1", g_recoveryWeapons[w].clip);
	SetEntProp(weapon, Prop_Send, "m_nSkin", g_recoveryWeapons[w].skin);
	if (HasEntProp(weapon, Prop_Send, "m_upgradeBitVec")) SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", g_recoveryWeapons[w].upgrades);
	if (HasEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded")) SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", g_recoveryWeapons[w].upgradedAmmo);
	if (GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") > 0) L4D_SetReserveAmmo(client, weapon, g_recoveryWeapons[w].reserve);
}

int Recovery_CreateWeapon(int w)
{
	if (StrEqual(g_recoveryWeapons[w].classname, "weapon_melee") && !g_recoveryWeapons[w].melee[0]) return -1;
	int weapon = CreateEntityByName(g_recoveryWeapons[w].classname);
	if (weapon <= MaxClients) return -1;
	if (g_recoveryWeapons[w].melee[0]) DispatchKeyValue(weapon, "melee_script_name", g_recoveryWeapons[w].melee);
	if (!DispatchSpawn(weapon)) { RemoveEntity(weapon); return -1; }
	return weapon;
}

bool Recovery_TraceFilter(int entity, int mask)
{
	return entity == 0 || entity > MaxClients;
}

bool Recovery_GroundPoint(const float source[3], bool ducked, float result[3])
{
	float top[3], bottom[3], mins[3] = {-16.0, -16.0, 2.0}, maxs[3] = {16.0, 16.0, 72.0};
	top = source;
	top[2] += 18.0;
	bottom = source;
	bottom[2] -= 80.0;
	if (ducked) maxs[2] = 36.0;
	Handle trace = TR_TraceHullFilterEx(top, bottom, mins, maxs, MASK_PLAYERSOLID, Recovery_TraceFilter);
	bool valid = !TR_StartSolid(trace) && !TR_AllSolid(trace) && TR_DidHit(trace);
	float normal[3];
	if (valid)
	{
		TR_GetEndPosition(result, trace);
		TR_GetPlaneNormal(trace, normal);
		valid = normal[2] >= 0.7;
	}
	delete trace;
	if (!valid) return false;
	result[2] += 2.0;
	trace = TR_TraceHullFilterEx(result, result, mins, maxs, MASK_PLAYERSOLID, Recovery_TraceFilter);
	valid = !TR_StartSolid(trace) && !TR_AllSolid(trace);
	delete trace;
	float head[3];
	head = result;
	head[2] += ducked ? 30.0 : 60.0;
	return valid && !(TR_GetPointContents(head) & CONTENTS_WATER);
}

float Recovery_Flow(int client)
{
	// Flow zero is valid at a map start; absence of a NAV area is not.
	return L4D_GetLastKnownArea(client) == 0 ? -1.0 : L4D2Direct_GetFlowDistance(client);
}

int Recovery_GroupAnchor(int client)
{
	int clients[MAXPLAYERS + 1], count;
	float flows[MAXPLAYERS + 1];
	for (int pass = 0; pass < 2 && !count; pass++)
	{
		for (int other = 1; other <= MaxClients; other++)
		{
			if (other == client || !IsHumanSurvivor(other) || !IsPlayerAlive(other) || GetEntProp(other, Prop_Send, "m_isHangingFromLedge")) continue;
			if (!pass && GetEntProp(other, Prop_Send, "m_isIncapacitated")) continue;
			clients[count] = other;
			flows[count++] = Recovery_Flow(other);
		}
	}
	bool spatialFallback;
	for (int i = 0; i < count; i++)
		if (flows[i] < 0.0) spatialFallback = true;
	if (spatialFallback)
	{
		// With incomplete NAV evidence, choose the survivor nearest the group,
		// not an arbitrary client slot or an isolated leader.
		int best;
		float bestDistance = -1.0;
		for (int i = 0; i < count; i++)
		{
			float origin[3], total;
			GetClientAbsOrigin(clients[i], origin);
			for (int j = 0; j < count; j++)
			{
				float other[3];
				GetClientAbsOrigin(clients[j], other);
				total += GetVectorDistance(origin, other);
			}
			if (bestDistance < 0.0 || total < bestDistance)
			{
				best = clients[i];
				bestDistance = total;
			}
		}
		return best;
	}
	// Median progress avoids following an isolated front runner.
	for (int i = 0; i < count; i++)
		for (int j = i + 1; j < count; j++)
			if (flows[j] < flows[i])
			{
				float flow = flows[i]; flows[i] = flows[j]; flows[j] = flow;
				int value = clients[i]; clients[i] = clients[j]; clients[j] = value;
			}
	return count ? clients[(count - 1) / 2] : 0;
}

bool Recovery_Position(int client, int index, float result[3])
{
	int anchor = Recovery_GroupAnchor(client);
	if (!anchor) return false;
	float teammate[3];
	GetClientAbsOrigin(anchor, teammate);
	float flow = Recovery_Flow(anchor);
	bool behind = flow >= 0.0 && g_recovery[index].flow >= 0.0
		? flow - g_recovery[index].flow > g_recoveryDistance.FloatValue
		: GetVectorDistance(teammate, g_recovery[index].origin) > g_recoveryDistance.FloatValue;
	if (!behind && Recovery_GroundPoint(g_recovery[index].origin, false, result)) return true;
	for (int attempt = 0; attempt < 9; attempt++)
	{
		float candidate[3];
		candidate = teammate;
		if (attempt < 8)
		{
			float angle = float(attempt) * FLOAT_PI / 4.0;
			candidate[0] += Cosine(angle) * 40.0;
			candidate[1] += Sine(angle) * 40.0;
		}
		if (Recovery_GroundPoint(candidate, false, result)) return true;
	}
	return false;
}

void Recovery_TryRestore(int client)
{
	int index = Recovery_Find(client);
	if (index < 0 || !g_recovery[index].valid || g_recoveryApplying[client] || !IsHumanClient(client)) return;
	g_recoveryAutoAttempted[client] = true;
	g_initialAdmissionPending[client] = false;
	if (!g_recovery[index].alive)
	{
		// A dead participant remains an observer; do not manufacture a respawn/death.
		g_recoveryApplying[client] = true;
		if (GetClientTeam(client) != TEAM_SPECTATORS) ChangeClientTeam(client, TEAM_SPECTATORS);
		g_recoveryApplying[client] = false;
		g_initialAdmissionPending[client] = false;
		g_wantsSpectator[client] = true;
		g_requestToken[client]++;
		Recovery_Clear(index);
		PrintToChat(client, "%t", "RecoveryDead");
		return;
	}
	if (GetAdmissionCount(-1) - (GetClientTeam(client) == TEAM_SURVIVORS ? 1 : 0) >= g_maxSurvivors.IntValue)
	{
		Recovery_NotifyRetry(client);
		return;
	}
	float pos[3];
	if (g_recovery[index].alive && !Recovery_Position(client, index, pos))
	{
		Recovery_NotifyRetry(client);
		return;
	}
	g_recoveryApplying[client] = true;
	g_recoverySuppressDrops[client] = false;
	g_requestToken[client]++;
	g_initialAdmissionPending[client] = false;
	// This is the sole live-round creation exception: an authenticated saved identity.
	if (GetClientTeam(client) != TEAM_SURVIVORS) ChangeClientTeam(client, TEAM_SURVIVORS);
	if (GetClientTeam(client) != TEAM_SURVIVORS)
	{
		g_recoveryApplying[client] = false;
		Recovery_NotifyRetry(client);
		return;
	}
	if (g_recovery[index].alive)
	{
		if (!IsPlayerAlive(client)) L4D_RespawnPlayer(client, false);
		if (!IsPlayerAlive(client))
		{
			g_recoveryApplying[client] = false;
			Recovery_NotifyRetry(client);
			return;
		}
		Recovery_Strip(client);
		if (GetEntProp(client, Prop_Send, "m_isIncapacitated")) L4D_ReviveSurvivor(client);
		TeleportEntity(client, pos, g_recovery[index].angles, NULL_VECTOR);
		PrecacheModel(g_recovery[index].model, true);
		SetEntProp(client, Prop_Send, "m_survivorCharacter", g_recovery[index].character);
		SetEntityModel(client, g_recovery[index].model);
		bool restored = Recovery_RestoreItems(client, index) && Recovery_RestoreHealth(client, index);
		if (!restored)
		{
			Recovery_Strip(client);
			ChangeClientTeam(client, TEAM_SPECTATORS);
			g_recoveryApplying[client] = false;
			Recovery_NotifyRetry(client);
			return;
		}
	}
	g_recoveryApplying[client] = false;
	Recovery_Clear(index);
	g_recoveryNotified[client] = false;
	CancelBotCleanup();
	ReconcileBots();
	PrintToChat(client, "%t", "RecoveryRestored");
}

bool Recovery_RestoreItems(int client, int index)
{
	for (int slot = 0; slot < RECOVERY_SLOTS; slot++)
	{
		int w = index * RECOVERY_SLOTS + slot;
		if (!g_recoveryWeapons[w].classname[0]) continue;
		int weapon = Recovery_CreateWeapon(w);
		if (weapon <= MaxClients) return false;
		EquipPlayerWeapon(client, weapon);
		if (GetPlayerWeaponSlot(client, slot) != weapon || GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity") != client)
		{
			if (IsValidEntity(weapon)) RemoveEntity(weapon);
			return false;
		}
		if (g_recoveryWeapons[w].dual)
		{
			int second = GivePlayerItem(client, "weapon_pistol");
			if (second <= MaxClients) return false;
			weapon = GetPlayerWeaponSlot(client, slot);
			if (weapon <= MaxClients || !GetEntProp(weapon, Prop_Send, "m_isDualWielding"))
			{
				if (IsValidEntity(second) && second != weapon) RemoveEntity(second);
				return false;
			}
		}
		if (weapon <= MaxClients) return false;
		Recovery_ApplyWeapon(weapon, w, client);
	}
	int active = GetPlayerWeaponSlot(client, g_recovery[index].activeSlot);
	if (active > MaxClients) SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", active);
	return true;
}

bool Recovery_RestoreHealth(int client, int index)
{
	if (g_recovery[index].incap)
	{
		// Use the engine incap transition (including its hidden secondary), not just a bool.
		SetEntProp(client, Prop_Send, "m_currentReviveCount", 0);
		SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 0);
		SetEntProp(client, Prop_Send, "m_isGoingToDie", 0);
		SetEntityHealth(client, 1);
		L4D_SetTempHealth(client, 0.0);
		int damageMode = GetEntProp(client, Prop_Data, "m_takedamage");
		int flags = GetEntityFlags(client);
		SetEntProp(client, Prop_Data, "m_takedamage", 2);
		SetEntityFlags(client, flags & ~FL_GODMODE);
		CountdownTimer protection = L4D2Direct_GetInvulnerabilityTimer(client);
		float protectionDuration, protectionTimestamp;
		if (protection != CTimer_Null)
		{
			protectionDuration = CTimer_GetDuration(protection);
			protectionTimestamp = CTimer_GetTimestamp(protection);
			CTimer_Invalidate(protection);
		}
		SDKHooks_TakeDamage(client, 0, 0, 100.0, DMG_GENERIC);
		if (protection != CTimer_Null)
		{
			CTimer_SetDuration(protection, protectionDuration);
			CTimer_SetTimestamp(protection, protectionTimestamp);
		}
		SetEntProp(client, Prop_Data, "m_takedamage", damageMode);
		SetEntityFlags(client, GetEntityFlags(client) | (flags & FL_GODMODE));
		if (!IsPlayerAlive(client) || !GetEntProp(client, Prop_Send, "m_isIncapacitated")) return false;
		int secondary = GetPlayerWeaponSlot(client, 1);
		if (secondary > MaxClients && g_recovery[index].incapClip >= 0)
			SetEntProp(secondary, Prop_Send, "m_iClip1", g_recovery[index].incapClip);
	}
	SetEntityHealth(client, g_recovery[index].health);
	L4D_SetTempHealth(client, g_recovery[index].buffer);
	SetEntProp(client, Prop_Send, "m_currentReviveCount", g_recovery[index].revives);
	SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", g_recovery[index].thirdStrike);
	SetEntProp(client, Prop_Send, "m_isGoingToDie", g_recovery[index].dying);
	L4D2Direct_SetPreIncapHealth(client, g_recovery[index].preHealth);
	L4D2Direct_SetPreIncapHealthBuffer(client, g_recovery[index].preBuffer);
	return true;
}

void Recovery_NotifyRetry(int client)
{
	// Engine auto-assignment must not leave an un-restored body playable on failure.
	if (GetClientTeam(client) == TEAM_SURVIVORS)
	{
		g_recoveryApplying[client] = true;
		Recovery_Strip(client);
		ChangeClientTeam(client, TEAM_SPECTATORS);
		g_recoveryApplying[client] = false;
	}
	if (!g_recoveryNotified[client]) PrintToChat(client, "%t", "RecoveryRetry");
	g_recoveryNotified[client] = true;
}
