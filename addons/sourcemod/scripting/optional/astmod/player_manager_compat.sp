#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

ConVar g_infectedLimit;
ConVar g_allowHumanTank;
ConVar g_legacyInfectedLimit;
ConVar g_legacyAllowHumanTank;
bool g_syncing;

public Plugin myinfo =
{
	name = "AstMod player manager compatibility",
	author = "norths7ar",
	description = "Bridges paused AstFlex Challenge CVars to the Coop player manager",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_infectedLimit = FindConVar("coop_player_infected_limit");
	g_allowHumanTank = FindConVar("coop_player_allow_human_tank");
	if (g_infectedLimit == null || g_allowHumanTank == null)
	{
		SetFailState("player_manager.smx must load before player_manager_compat.smx");
		return;
	}

	g_legacyInfectedLimit = CreateConVar("ast_maxinfected", "0", "AstFlex compatibility alias for coop_player_infected_limit.");
	g_legacyAllowHumanTank = CreateConVar("ast_allowhumantank", "0", "AstFlex compatibility alias for coop_player_allow_human_tank.");

	g_infectedLimit.AddChangeHook(OnCanonicalChanged);
	g_allowHumanTank.AddChangeHook(OnCanonicalChanged);
	g_legacyInfectedLimit.AddChangeHook(OnLegacyChanged);
	g_legacyAllowHumanTank.AddChangeHook(OnLegacyChanged);

	SyncLegacyFromCanonical();
}

public void OnCanonicalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_syncing) return;
	g_syncing = true;
	if (convar == g_infectedLimit) g_legacyInfectedLimit.SetString(newValue);
	else g_legacyAllowHumanTank.SetString(newValue);
	g_syncing = false;
}

public void OnLegacyChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_syncing) return;
	g_syncing = true;
	if (convar == g_legacyInfectedLimit) g_infectedLimit.SetString(newValue);
	else g_allowHumanTank.SetString(newValue);
	g_syncing = false;
}

void SyncLegacyFromCanonical()
{
	char value[32];
	g_syncing = true;
	g_infectedLimit.GetString(value, sizeof(value));
	g_legacyInfectedLimit.SetString(value);
	g_allowHumanTank.GetString(value, sizeof(value));
	g_legacyAllowHumanTank.SetString(value);
	g_syncing = false;
}
