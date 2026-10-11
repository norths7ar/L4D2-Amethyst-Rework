#if defined _map_rules_included
 #endinput
#endif
#define _map_rules_included

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN

// Shared source helpers, not a plugin. Each feature owns its commands, active
// round state and fields. Writers read the latest file before changing one key.
static ConVar g_mapRulesEnabled;
static bool g_mapRulesLive;

stock void MapRules_Init()
{
	g_mapRulesEnabled = CreateConVar("map_rules_enabled", "0", "Use configs/map_rules.cfg for map rules in this mode.", FCVAR_NONE, true, 0.0, true, 1.0);
	HookEvent("round_start", MapRules_RoundStart, EventHookMode_Pre);
	HookEvent("player_left_start_area", MapRules_LeftStart, EventHookMode_PostNoCopy);
}

public void MapRules_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_mapRulesLive = false;
}

public void MapRules_LeftStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!MapRules_HasReadyGate()) g_mapRulesLive = true;
}

// Call from the owning plugin's OnRoundIsLive forward.
stock void MapRules_Lock() { g_mapRulesLive = true; }

stock bool MapRules_HasReadyGate()
{
	if (GetFeatureStatus(FeatureType_Native, "IsInReady") != FeatureStatus_Available) return false;
	// Coop's IsInReady is false while its loading gate is disabled, even before
	// anyone leaves the saferoom. In that case the Live forward/exit owns timing.
	ConVar enabled = FindConVar("ready_enabled");
	return enabled == null || enabled.BoolValue;
}

stock bool MapRules_IsLive()
{
	if (MapRules_HasReadyGate())
		return g_mapRulesLive || !IsInReady();
	return g_mapRulesLive;
}

stock bool MapRules_Enabled() { return g_mapRulesEnabled != null && g_mapRulesEnabled.BoolValue; }

stock void MapRules_CurrentMap(char[] map, int length)
{
	GetCurrentMap(map, length);
	for (int i = 0; map[i]; i++) map[i] = CharToLower(map[i]);
}

stock KeyValues MapRules_Load()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/map_rules.cfg");
	KeyValues rules = new KeyValues("MapRules");
	if (!rules.ImportFromFile(path))
	{
		LogError("Cannot read map rules: %s", path);
		delete rules;
		return null;
	}
	return rules;
}

stock int MapRules_ReadInt(KeyValues rules, const char[] map, const char[] key, int fallback = 0)
{
	rules.Rewind();
	int value = fallback;
	if (rules.JumpToKey("defaults")) value = rules.GetNum(key, fallback);
	rules.Rewind();
	if (rules.JumpToKey("maps") && rules.JumpToKey(map)) value = rules.GetNum(key, value);
	rules.Rewind();
	return value;
}

stock void MapRules_ReadString(KeyValues rules, const char[] map, const char[] key, char[] value, int length, const char[] fallback = "")
{
	rules.Rewind();
	strcopy(value, length, fallback);
	if (rules.JumpToKey("defaults")) rules.GetString(key, value, length, fallback);
	rules.Rewind();
	if (rules.JumpToKey("maps") && rules.JumpToKey(map))
	{
		char inherited[64];
		strcopy(inherited, sizeof(inherited), value);
		rules.GetString(key, value, length, inherited);
	}
	rules.Rewind();
}

stock bool MapRules_SaveInt(const char[] key, int value)
{
	KeyValues rules = MapRules_Load();
	if (rules == null) return false;
	char map[64], path[PLATFORM_MAX_PATH], temporary[PLATFORM_MAX_PATH];
	MapRules_CurrentMap(map, sizeof(map));
	rules.JumpToKey("maps", true);
	rules.JumpToKey(map, true);
	rules.SetNum(key, value);
	rules.Rewind();
	BuildPath(Path_SM, path, sizeof(path), "configs/map_rules.cfg");
	FormatEx(temporary, sizeof(temporary), "%s.tmp", path);
	bool saved = rules.ExportToFile(temporary) && RenameFile(path, temporary);
	if (!saved) LogError("Cannot save map rules: %s", path);
	delete rules;
	return saved;
}
