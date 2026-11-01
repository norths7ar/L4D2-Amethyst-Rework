#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <map_rules>

bool g_configsReady;
bool g_roundRulesReady;
bool g_rulesActive;
bool g_fuelBarrelsAllowed;

public Plugin myinfo =
{
	name = "Map Entity Rules",
	author = "norths7ar",
	description = "Per-map rules for map-authored gameplay entities",
	version = "1.0.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	RegPluginLibrary("map_entity_rules");
	CreateNative("EntityRules_GetFuelBarrels", Native_GetFuelBarrels);
	CreateNative("EntityRules_SetFuelBarrels", Native_SetFuelBarrels);
	return APLRes_Success;
}

public void OnPluginStart()
{
	MapRules_Init();
	HookEvent("round_start_pre_entity", RoundReset, EventHookMode_Pre);
}

public void OnMapEnd()
{
	g_configsReady = false;
	g_roundRulesReady = false;
	g_rulesActive = false;
}

public void OnConfigsExecuted()
{
	g_configsReady = true;
	if (!g_roundRulesReady) LoadRoundRules();
}

public void RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	// Latch before CleanUpMap recreates entities. A saved permission must be
	// active before their spawn hooks run, not after round_start.
	g_roundRulesReady = false;
	g_rulesActive = false;
	if (g_configsReady) LoadRoundRules();
}

bool ReadFuelBarrels()
{
	KeyValues rules = MapRules_Load();
	if (rules == null) return false;
	char map[64];
	MapRules_CurrentMap(map, sizeof(map));
	bool allowed = MapRules_ReadInt(rules, map, "fuel_barrels", 0) != 0;
	delete rules;
	return allowed;
}

void LoadRoundRules()
{
	g_rulesActive = MapRules_Enabled();
	g_fuelBarrelsAllowed = !g_rulesActive || ReadFuelBarrels();
	g_roundRulesReady = true;
	RequestFrame(ScanMapEntities);
}

public void ScanMapEntities(any unused)
{
	if (!g_rulesActive || g_fuelBarrelsAllowed) return;
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_fuel_barrel")) != -1)
		RemoveEntity(entity);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "prop_fuel_barrel"))
		SDKHook(entity, SDKHook_SpawnPost, FuelBarrelSpawned);
}

public void FuelBarrelSpawned(int entity)
{
	// Delete only the live entity, never its map definition. The engine restores
	// the original barrel and its links on the next ordinary round reset.
	if (g_rulesActive && !g_fuelBarrelsAllowed) RemoveEntity(entity);
}

public any Native_GetFuelBarrels(Handle plugin, int numParams)
{
	return GetNativeCell(1) ? ReadFuelBarrels() : g_fuelBarrelsAllowed;
}

public any Native_SetFuelBarrels(Handle plugin, int numParams)
{
	if (!MapRules_Enabled()) return false;
	// Both directions apply next round, even during ready-up. Enabling cannot
	// resurrect an entity already removed this round.
	return MapRules_SaveInt("fuel_barrels", GetNativeCell(1) ? 1 : 0);
}
