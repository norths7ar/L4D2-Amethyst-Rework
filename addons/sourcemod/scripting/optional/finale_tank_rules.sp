#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <map_rules>
#include <left4dhooks> //#include <l4d2_direct>

#define MAP_NAME_MAX_LENGTH 64

#if !defined _l4dh_included
// from https://developer.valvesoftware.com/wiki/L4D2_Director_Scripts
enum
{
	FINALE_GAUNTLET_1 = 0,
	FINALE_HORDE_ATTACK_1 = 1,
	FINALE_HALFTIME_BOSS = 2,
	FINALE_GAUNTLET_2 = 3,
	FINALE_HORDE_ATTACK_2 = 4,
	FINALE_FINAL_BOSS = 5,
	FINALE_HORDE_ESCAPE = 6,
	FINALE_CUSTOM_PANIC = 7,
	FINALE_CUSTOM_TANK = 8,
	FINALE_CUSTOM_SCRIPTED = 9,
	FINALE_CUSTOM_DELAY = 10,
	FINALE_CUSTOM_CLEAROUT = 11,
	FINALE_GAUNTLET_START = 12,
	FINALE_GAUNTLET_HORDE = 13,
	FINALE_GAUNTLET_HORDE_BONUSTIME	= 14,
	FINALE_GAUNTLET_BOSS_INCOMING = 15,
	FINALE_GAUNTLET_BOSS = 16,
	FINALE_GAUNTLET_ESCAPE = 17
};
#endif

enum TankSpawningScheme
{
	Skip,
	FlowAndSecondOnEvent,
	FirstOnEvent
};

ConVar
	hVersusTankChanceFinale = null;

StringMap
	hFirstTankSpawningScheme = null,
	hSecondTankSpawningScheme = null;

TankSpawningScheme
	spawnScheme = Skip;

int
	tankCount = 0;

enum FinaleMode
{
	FinaleAuto,
	FinaleRounds,
	FinaleLegacy
};

FinaleMode g_finaleMode;
bool g_activeRounds[3] = {true, true, true};
static const char g_roundKeys[][] = {"tank_round_1", "tank_round_2", "tank_round_later"};
bool g_observedCustom;
bool g_confirmedGauntlet;
bool g_lateLoad;
bool g_waitForRound;
bool g_rulesLoaded;
int g_activeStage = -1;
int g_customCount;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	g_lateLoad = late;
	CreateNative("FinaleRules_CanEdit", Native_CanEdit);
	CreateNative("FinaleRules_GetRound", Native_GetRound);
	CreateNative("FinaleRules_SetRound", Native_SetRound);
	RegPluginLibrary("finale_tank_rules");
	return APLRes_Success;
}

public void OnMapStart()
{
	g_observedCustom = false;
	g_confirmedGauntlet = false;
	g_activeStage = -1;
	g_customCount = 0;
	tankCount = 0;
	g_rulesLoaded = false;
}

public void OnConfigsExecuted()
{
	if (g_lateLoad)
	{
		// The helper did not see any saferoom exit before this plugin loaded.
		g_waitForRound = MapRules_IsLive() || L4D_HasAnySurvivorLeftSafeArea();
		if (g_waitForRound) MapRules_Lock();
		g_lateLoad = false;
	}
	if (MapRules_Enabled() && (!g_rulesLoaded || !MapRules_IsLive())) LoadFinaleRules();
}

public void OnRoundIsLive()
{
	MapRules_Lock();
}

void LoadFinaleRules()
{
	KeyValues rules = MapRules_Load();
	char map[MAP_NAME_MAX_LENGTH], mode[16];
	MapRules_CurrentMap(map, sizeof(map));
	strcopy(mode, sizeof(mode), "auto");
	for (int slot = 0; slot < 3; slot++)
		g_activeRounds[slot] = rules == null || MapRules_ReadInt(rules, map, g_roundKeys[slot], 1) != 0;
	if (rules != null)
		MapRules_ReadString(rules, map, "finale_mode", mode, sizeof(mode), "auto");
	delete rules;
	g_finaleMode = FinaleAuto;
	if (StrEqual(mode, "rounds")) g_finaleMode = FinaleRounds;
	else if (StrEqual(mode, "legacy")) g_finaleMode = FinaleLegacy;
	g_rulesLoaded = true;
}

bool CanEditFinale()
{
	if (!MapRules_Enabled() || g_waitForRound || g_lateLoad || !g_rulesLoaded) return false;
	// Unsupported legacy finales retain file policy, not new menu editing.
	if (g_finaleMode == FinaleLegacy) return false;
	return !g_confirmedGauntlet && (g_finaleMode == FinaleRounds || g_observedCustom);
}

int RoundSlot(int ordinal)
{
	return ordinal > 2 ? 2 : ordinal - 1;
}

public any Native_CanEdit(Handle plugin, int numParams)
{
	return CanEditFinale();
}

public any Native_GetRound(Handle plugin, int numParams)
{
	int slot = GetNativeCell(1);
	if (slot < 0 || slot >= 3) return false;
	if (numParams < 2 || !GetNativeCell(2)) return g_activeRounds[slot];
	KeyValues rules = MapRules_Load();
	char map[MAP_NAME_MAX_LENGTH];
	MapRules_CurrentMap(map, sizeof(map));
	bool allowed = rules == null || MapRules_ReadInt(rules, map, g_roundKeys[slot], 1) != 0;
	delete rules;
	return allowed;
}

public any Native_SetRound(Handle plugin, int numParams)
{
	int slot = GetNativeCell(1);
	if (slot < 0 || slot >= 3 || !CanEditFinale()) return false;
	bool allowed = GetNativeCell(2) != 0;
	if (!MapRules_SaveInt(g_roundKeys[slot], allowed)) return false;
	if (!MapRules_IsLive()) g_activeRounds[slot] = allowed;
	return true;
}

public Plugin myinfo =
{
	name = "Finale Tank Rules",
	author = "Visor, Electr0",
	description = "Either two event tanks or one flow and one (second) event tank",
	version = "2.6.0",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

public void OnPluginStart()
{
	MapRules_Init();
	hFirstTankSpawningScheme = new StringMap();
	hSecondTankSpawningScheme = new StringMap();

	hVersusTankChanceFinale = FindConVar("versus_tank_chance_finale");

	RegServerCmd("tank_map_flow_and_second_event", SetMapFirstTankSpawningScheme);
	RegServerCmd("tank_map_only_first_event", SetMapSecondTankSpawningScheme);

	HookEvent("round_start", RoundStartEvent, EventHookMode_PostNoCopy);
}

Action SetMapFirstTankSpawningScheme(int args)
{
	if (args != 1) {
		PrintToServer("Usage: tank_map_flow_and_second_event <mapname>");
		LogError("Usage: tank_map_flow_and_second_event <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[MAP_NAME_MAX_LENGTH];
	GetCmdArg(1, mapname, sizeof(mapname));
	hFirstTankSpawningScheme.SetValue(mapname, true);

	return Plugin_Handled;
}

Action SetMapSecondTankSpawningScheme(int args)
{
	if (args != 1) {
		PrintToServer("Usage: tank_map_only_first_event <mapname>");
		LogError("Usage: tank_map_only_first_event <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[MAP_NAME_MAX_LENGTH];
	GetCmdArg(1, mapname, sizeof(mapname));
	hSecondTankSpawningScheme.SetValue(mapname, true);

	return Plugin_Handled;
}

void RoundStartEvent(Event hEvent, const char[] name, bool dontBroadcast)
{
	tankCount = 0;
	g_customCount = 0;
	g_activeStage = -1;
	g_waitForRound = false;
	g_lateLoad = false;
	if (MapRules_Enabled()) LoadFinaleRules();
	CreateTimer(8.0, ProcessTankSpawn, _, TIMER_FLAG_NO_MAPCHANGE);
}

Action ProcessTankSpawn(Handle hTimer)
{
	// Managed finale rules never own flow eligibility.
	if (MapRules_Enabled()) return Plugin_Stop;
	spawnScheme = Skip;
	
	char mapname[MAP_NAME_MAX_LENGTH];
	GetCurrentMap(mapname, sizeof(mapname));
	
	int iValue;
	if (hFirstTankSpawningScheme.GetValue(mapname, iValue)) {
		spawnScheme = FlowAndSecondOnEvent;
	}
	
	if (hSecondTankSpawningScheme.GetValue(mapname, iValue)) {
		spawnScheme = FirstOnEvent;
	}
	
	if (IsTankAllowed() && spawnScheme != Skip) {
		bool bIsSpawn = (spawnScheme == FlowAndSecondOnEvent);
		L4D2Direct_SetVSTankToSpawnThisRound(InSecondHalfOfRound(), bIsSpawn);
	}

	return Plugin_Stop;
}

public Action L4D2_OnChangeFinaleStage(int &finaleType, const char[] arg)
{
	if (MapRules_Enabled())
	{
		if (g_waitForRound || g_lateLoad || !g_rulesLoaded) return Plugin_Continue;
		if (g_finaleMode == FinaleLegacy
			&& (finaleType == FINALE_CUSTOM_TANK
			|| finaleType == FINALE_GAUNTLET_BOSS
			|| finaleType == FINALE_GAUNTLET_ESCAPE))
		{
			// Preserve legacy interception and count even blocked attempts.
			tankCount++;
			if (!g_activeRounds[RoundSlot(tankCount)]) return Plugin_Handled;
		}
		// Ordinary custom stages must enter so the engine owns advancement.
		return Plugin_Continue;
	}
	if (spawnScheme != Skip
		&& (finaleType == FINALE_CUSTOM_TANK
		|| finaleType == FINALE_GAUNTLET_BOSS
		|| finaleType == FINALE_GAUNTLET_ESCAPE)
	) {
		//PrintToChatAll("Finale type %i has commenced", finaleType);
		
		tankCount++;
		
		if ((spawnScheme == FlowAndSecondOnEvent && tankCount != 2)
			|| (spawnScheme == FirstOnEvent && tankCount != 1)
		) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void L4D2_OnChangeFinaleStage_Post(int finaleType, const char[] arg)
{
	g_activeStage = finaleType;
	if (finaleType >= FINALE_GAUNTLET_START && finaleType <= FINALE_GAUNTLET_ESCAPE)
		g_confirmedGauntlet = true;
	if (finaleType == FINALE_CUSTOM_TANK)
	{
		// Map capability survives wipes, but ordinals do not.
		g_observedCustom = true;
		if (!g_waitForRound && !g_lateLoad) g_customCount++;
	}
}

public Action L4D_OnSpawnTank(const float vecPos[3], const float vecAng[3])
{
	if (!CanEditFinale() || g_finaleMode == FinaleLegacy
		|| g_activeStage != FINALE_CUSTOM_TANK || g_customCount == 0)
		return Plugin_Continue;

	// A null custom tank consumes the pending spawn; the engine advances when
	// no live tanks remain. Gauntlets retry null spawns and must never use this.
	if (!g_activeRounds[RoundSlot(g_customCount)]) return Plugin_Handled;
	return Plugin_Continue;
}

int InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

bool IsTankAllowed()
{
	return (hVersusTankChanceFinale.FloatValue > 0.0);
}
