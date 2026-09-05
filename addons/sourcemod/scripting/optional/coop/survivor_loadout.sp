#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <coop_player_manager>

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
	LoadTranslations("coop_flow.phrases");
	g_preserveWeapons = CreateConVar("coop_loadout_preserve_weapons", "0", "Keep weapons across map transitions.");
	g_startPills = CreateConVar("coop_loadout_start_pills", "1", "Give starting pain pills when the round goes live.", _, true, 0.0, true, 1.0);
	HookEvent("map_transition", EventMapTransition, EventHookMode_Post);
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
	ResetInventory(false);
	if (g_startPills.BoolValue) GiveStartingPills();
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
