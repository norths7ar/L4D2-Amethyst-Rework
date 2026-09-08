#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <player_manager>

#define TEAM_SURVIVORS 2

ConVar g_preserveWeapons;
ConVar g_startPills;
bool g_liveHandled;

public Plugin myinfo =
{
	name = "Coop survivor loadout",
	author = "海洋空氣, norths7ar",
	description = "Preserves AstMod survivor inventory lifecycle for Coop",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_preserveWeapons = CreateConVar("preserve_transition_weapons", "0", "Keep weapons across map transitions.");
	g_startPills = CreateConVar("give_start_pills", "1", "Give starting pain pills when the round goes live.", _, true, 0.0, true, 1.0);
	HookEvent("map_transition", EventMapTransition, EventHookMode_Post);
	HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
}

public void EventRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_liveHandled = false;
}

public void OnMapStart()
{
	g_liveHandled = false;
}

public void OnMapEnd()
{
	g_liveHandled = false;
}

public Action EventMapTransition(Event event, const char[] name, bool dontBroadcast)
{
	ResetInventory(!g_preserveWeapons.BoolValue);
	return Plugin_Continue;
}

/** Called by the shared ready_pause readyup library. */
public void OnRoundIsLive()
{
	if (g_liveHandled) return;
	g_liveHandled = true;
	ReplaceStartingMedkits();
	ResetInventory(false);
	if (g_startPills.BoolValue) GiveStartingPills();
}

void ReplaceStartingMedkits()
{
	// Map pickups belong to the same live transition as carried equipment.
	// Do not touch held kits or medical supplies elsewhere in the campaign.
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity)) continue;
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));
		if (!StrEqual(classname, "weapon_first_aid_kit_spawn") && !StrEqual(classname, "weapon_first_aid_kit")) continue;
		if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") > 0) continue;
		float origin[3], angles[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		if (!L4D_IsPositionInFirstCheckpoint(origin)) continue;
		GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
		int count = HasEntProp(entity, Prop_Data, "m_itemCount") ? GetEntProp(entity, Prop_Data, "m_itemCount") : 1;
		if (count <= 0) continue;
		int pills = CreateEntityByName("weapon_pain_pills_spawn");
		if (pills <= MaxClients) continue;
		DispatchKeyValueInt(pills, "count", count);
		TeleportEntity(pills, origin, angles, NULL_VECTOR);
		if (!DispatchSpawn(pills)) { RemoveEntity(pills); continue; }
		SetEntityMoveType(pills, MOVETYPE_NONE);
		RemoveEntity(entity);
	}
}

void ResetInventory(bool resetWeapons)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS || !IsPlayerAlive(client)) continue;
		if (resetWeapons)
		{
			for (int slot = 0; slot < 5; slot++) DeleteInventoryItem(client, slot);
			ExecuteCheatCommand(client, "give", "pistol");
		}
		else
		{
			for (int slot = 3; slot < 5; slot++) DeleteInventoryItem(client, slot);
		}
		ExecuteCheatCommand(client, "give", "health");
		SetEntityHealth(client, 100);
		L4D_SetTempHealth(client, 0.0);
	}
}

void GiveStartingPills()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS || !IsPlayerAlive(client)) continue;
		if (!Coop_ShouldKeepSurvivorBots() && IsFakeClient(client)) continue;
		int pills = CreateEntityByName("weapon_pain_pills");
		if (pills <= 0) continue;
		float origin[3];
		GetClientAbsOrigin(client, origin);
		TeleportEntity(pills, origin, NULL_VECTOR, NULL_VECTOR);
		if (!DispatchSpawn(pills))
		{
			RemoveEdict(pills);
			continue;
		}
		EquipPlayerWeapon(client, pills);
	}
}

void DeleteInventoryItem(int client, int slot)
{
	int item = GetPlayerWeaponSlot(client, slot);
	if (item > 0)
	{
		RemovePlayerItem(client, item);
		RemoveEdict(item);
	}
}

void ExecuteCheatCommand(int client, const char[] command, const char[] parameter)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, parameter);
	SetCommandFlags(command, flags);
}
