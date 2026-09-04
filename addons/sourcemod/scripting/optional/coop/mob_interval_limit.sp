#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

ConVar hMobLimitEnabled;
ConVar hMobInterval;
ConVar hDebug;
ConVar hMegaMobSize;
ConVar hMobSpawnMinSize;
ConVar hMobSpawnMaxSize;
Handle g_hMobIntervalTimer;
int iMegaMobSize;
int iMobSpawnMinSize;
int iMobSpawnMaxSize;
bool bAllowSpawnMobs = true;
bool bAllowMobsChange = true;

public void OnPluginStart()
{
	hMobLimitEnabled = CreateConVar("mob_spawn_limit_enabled", "0");
	hMobInterval = CreateConVar("mob_spawn_block_interval", "8.0");
	hDebug = CreateConVar("mob_spawn_debug", "0");

	RegServerCmd("sm_mob_lock", LockMobs);
	RegServerCmd("sm_mob_unlock", UnlockMobs);

	hMegaMobSize = FindConVar("z_mega_mob_size");
	hMobSpawnMinSize = FindConVar("z_mob_spawn_min_size");
	hMobSpawnMaxSize = FindConVar("z_mob_spawn_max_size");

	if (hMegaMobSize != null) HookConVarChange(hMegaMobSize, OnMobChanged);
	if (hMobSpawnMinSize != null) HookConVarChange(hMobSpawnMinSize, OnMobChanged);
	if (hMobSpawnMaxSize != null) HookConVarChange(hMobSpawnMaxSize, OnMobChanged);
	HookConVarChange(hMobLimitEnabled, OnMobLimitEnabledChanged);
}

public void OnMapEnd()
{
	CancelMobIntervalTimer();
	bAllowSpawnMobs = true;
	bAllowMobsChange = true;
}

public Action L4D_OnSpawnMob(int &amount)
{
	if (!hMobLimitEnabled.BoolValue) return Plugin_Continue;

	int mobSize = hMegaMobSize != null ? hMegaMobSize.IntValue : amount;
	float mobInterval = hMobInterval.FloatValue;
	bool iDebug = hDebug.BoolValue;
	if (iDebug) PrintToChatAll("mob original amount: %d", amount);
	if (bAllowSpawnMobs) {
		if (amount > mobSize) amount = mobSize;
		bAllowSpawnMobs = false;
		if (iDebug) PrintToChatAll("mob altered amount: %d", amount);
		CancelMobIntervalTimer();
		g_hMobIntervalTimer = CreateTimer(mobInterval, MobsIntervalTimer);
		return Plugin_Changed;
	}
	return Plugin_Handled;
}

public Action MobsIntervalTimer(Handle timer)
{
	if (g_hMobIntervalTimer == timer) g_hMobIntervalTimer = null;
	if (hMobLimitEnabled.BoolValue) bAllowSpawnMobs = true;
	return Plugin_Stop;
}

public Action LockMobs(int args)
{
	if (!hMobLimitEnabled.BoolValue) return Plugin_Handled;
	bAllowMobsChange = false;
	if (hMegaMobSize != null) iMegaMobSize = hMegaMobSize.IntValue;
	if (hMobSpawnMinSize != null) iMobSpawnMinSize = hMobSpawnMinSize.IntValue;
	if (hMobSpawnMaxSize != null) iMobSpawnMaxSize = hMobSpawnMaxSize.IntValue;
	return Plugin_Handled;
}

public Action UnlockMobs(int args)
{
	bAllowMobsChange = true;
	return Plugin_Handled;
}

public void OnMobLimitEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!convar.BoolValue) {
		CancelMobIntervalTimer();
		bAllowSpawnMobs = true;
		bAllowMobsChange = true;
	}
}

void CancelMobIntervalTimer()
{
	if (g_hMobIntervalTimer != null) {
		delete g_hMobIntervalTimer;
		g_hMobIntervalTimer = null;
	}
}

public void OnMobChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!hMobLimitEnabled.BoolValue) return;
	if (!bAllowMobsChange) {
		if (hMegaMobSize != null) hMegaMobSize.IntValue = iMegaMobSize;
		if (hMobSpawnMinSize != null) hMobSpawnMinSize.IntValue = iMobSpawnMinSize;
		if (hMobSpawnMaxSize != null) hMobSpawnMaxSize.IntValue = iMobSpawnMaxSize;
	}
}
