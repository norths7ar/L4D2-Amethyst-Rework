#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define ZC_SMOKER 1
#define ZC_HUNTER 3
#define ZC_JOCKEY 5
#define ZC_CHARGER 6
#define ZC_TANK 8

char g_sSINames[][] =
{
	"Unknown",
	"Smoker",
	"Boomer",
	"Hunter",
	"Spitter",
	"Jockey",
	"Charger",
	"Witch",
	"Tank",
	"Not SI"
};

ConVar g_cvEnable;
ConVar g_cvBaseDamage;
ConVar g_cvRatioEnable;
ConVar g_cvFastGetupEnable;

bool g_bIsUsingAbility[MAXPLAYERS + 1];
float g_fDamagePrint;

public Plugin myinfo =
{
	name = "Coop SI Damage Control",
	author = "海洋空氣, norths7ar",
	description = "Controls Coop special-infected damage, tongue clears, and fast getup.",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("si_damage_enable", "1", "Enable special-infected damage control.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBaseDamage = CreateConVar("si_damage_base", "12.0", "Base special-infected damage.", FCVAR_NOTIFY, true, 1.0, true, 100.0);
	g_cvRatioEnable = CreateConVar("si_damage_ratio_enable", "0", "Use proportional special-infected damage.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFastGetupEnable = CreateConVar("si_damage_fast_getup_enable", "1", "Enable fast getup after special-infected attacks.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("tongue_grab", Event_TongueGrab);
	HookEvent("tongue_release", Event_TongueRelease);
	HookEvent("tongue_broke_bent", Event_TongueRelease);
	HookEvent("tongue_pull_stopped", Event_TonguePullStopped);
	HookEvent("charger_carry_start", Event_ChargerCarryStart, EventHookMode_Post);
	HookEvent("charger_pummel_start", Event_ChargerPummelStart, EventHookMode_Post);
}

public Action Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	if (IsInfected(smoker) && GetZombieClass(smoker) == ZC_SMOKER)
	{
		g_bIsUsingAbility[smoker] = true;
	}
	return Plugin_Continue;
}

public Action Event_TongueRelease(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	if (IsInfected(smoker) && GetZombieClass(smoker) == ZC_SMOKER)
	{
		g_bIsUsingAbility[smoker] = false;
	}
	return Plugin_Continue;
}

// Smoker tongue cutting and self-clears. Called when a dragging tongue is cleared, including cuts.
public Action Event_TonguePullStopped(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));
	int smoker = GetClientOfUserId(event.GetInt("smoker"));
	int reason = event.GetInt("release_type");
	// 1: smoker got shoved; 2: survivor got shoved; 3: smoker got killed; 4: tongue cut.

	if (!IsClientSurvivor(attacker) || !IsInfected(smoker) || attacker != victim)
	{
		return Plugin_Continue;
	}

	if (reason == 4 && g_cvEnable.BoolValue)
	{
		ForcePlayerSuicide(smoker);

		char weapon[32];
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		ReplaceString(weapon, sizeof(weapon), "weapon_", "", false);
		SendDeathMessage(attacker, smoker, weapon, true);
	}

	g_bIsUsingAbility[smoker] = false;
	return Plugin_Continue;
}

void SendDeathMessage(int attacker, int victim, const char[] weapon, bool headshot)
{
	Event event = CreateEvent("player_death");
	if (event == null)
	{
		return;
	}

	event.SetInt("userid", GetClientUserId(victim));
	event.SetInt("attacker", GetClientUserId(attacker));
	event.SetString("weapon", weapon);
	event.SetBool("headshot", headshot);
	event.Fire();
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (attacker == 0 || victim == 0)
	{
		return Plugin_Handled;
	}
	if (!IsInfected(victim))
	{
		return Plugin_Handled;
	}

	g_bIsUsingAbility[victim] = false;
	SDKUnhook(victim, SDKHook_OnTakeDamage, OnTakeDamage);
	return Plugin_Continue;
}

// While a Charger is carrying a Survivor, undo any friendly fire done to them
// since they are effectively pinned and pinned survivors are normally immune to FF.
public Action Event_ChargerCarryStart(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	g_bIsUsingAbility[charger] = true;
	return Plugin_Continue;
}

// End immunity when the pummel starts. The original behavior intentionally uses this event.
public Action Event_ChargerPummelStart(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	g_bIsUsingAbility[charger] = false;
	return Plugin_Continue;
}

// 插件重读的时候也重新 Hook。
public void OnMapStart()
{
	for (int client = 1; client < MaxClients; client++)
	{
		if (!IsValidEntity(client))
		{
			return;
		}
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public void OnClientPutInServer(int client)
{
	if (client > 0 && client < MaxClients)
	{
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public void OnClientDisconnect(int client)
{
	if (client > 0 && client < MaxClients)
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!IsClientAndInGame(victim) || !IsClientAndInGame(attacker))
	{
		return Plugin_Continue;
	}

	if (IsInfected(victim) && GetZombieClass(victim) == ZC_SMOKER && g_bIsUsingAbility[victim])
	{
		damage = FindConVar("z_gas_health").FloatValue;
		return Plugin_Changed;
	}
	if (!IsInfected(attacker))
	{
		return Plugin_Continue;
	}

	int zombieClass = GetZombieClass(attacker);
	if (zombieClass != ZC_SMOKER && zombieClass != ZC_HUNTER && zombieClass != ZC_JOCKEY && zombieClass != ZC_CHARGER)
	{
		return Plugin_Continue;
	}

	float adjustedDamage = g_cvBaseDamage.FloatValue;
	if (g_cvRatioEnable.BoolValue)
	{
		float currentHealth = float(GetEntProp(attacker, Prop_Data, "m_iHealth"));
		float maxHealth = float(GetEntProp(attacker, Prop_Data, "m_iMaxHealth"));
		adjustedDamage = g_cvBaseDamage.FloatValue * (currentHealth / maxHealth);
		if (adjustedDamage < 1.0)
		{
			adjustedDamage = 1.0;
		}
	}

	g_fDamagePrint = adjustedDamage;
	damage = adjustedDamage;

	// 在梯子上被扑不造成伤害，防止生还卡在梯子上无法起身。
	if (zombieClass == ZC_HUNTER && GetEntityMoveType(victim) & MOVETYPE_LADDER)
	{
		damage = 0.0;
	}

	// 牛撞停不造成伤害，防止过早处死导致 pummel end 事件不触发。
	if (zombieClass == ZC_CHARGER && g_bIsUsingAbility[attacker])
	{
		damage = 0.0;
	}
	return Plugin_Changed;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Handled;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientAndInGame(attacker) || !IsClientAndInGame(victim))
	{
		return Plugin_Handled;
	}

	int damage = event.GetInt("dmg_health");
	int zombieClass = GetZombieClass(attacker);
	if (IsInfected(attacker) && IsSurvivor(victim) && zombieClass != ZC_TANK && damage > 0)
	{
		int remainingHealth = GetClientHealth(attacker);
		ForcePlayerSuicide(attacker);
		CPrintToChatAll("[{olive}Ast{default}] {red}%N{default}({green}%s{default}) 还剩下 {olive}%d{default} 血! 造成了 {olive}%2.1f{default} 点伤害!", attacker, g_sSINames[zombieClass], remainingHealth, g_fDamagePrint);
		if (g_cvFastGetupEnable.BoolValue && (zombieClass == ZC_HUNTER || zombieClass == ZC_CHARGER))
		{
			CancelGetupLater(victim);
		}
	}
	return Plugin_Continue;
}

void CancelGetupLater(int client)
{
	CreateTimer(0.4, Timer_CancelGetup, client);
}

public Action Timer_CancelGetup(Handle timer, int client)
{
	SetEntPropFloat(client, Prop_Send, "m_flCycle", 1000.0);
	return Plugin_Continue;
}

int GetZombieClass(int client)
{
	return GetEntProp(client, Prop_Send, "m_zombieClass");
}

bool IsClientAndInGame(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsClientSurvivor(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}

bool IsInfected(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_INFECTED;
}

bool IsSurvivor(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}
