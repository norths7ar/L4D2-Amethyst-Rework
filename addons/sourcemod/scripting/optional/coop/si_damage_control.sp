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

const float SMOKER_TONGUE_WINDOW_DURATION = 2.0;
float g_fSmokerTongueWindowExpires[MAXPLAYERS + 1];
int g_iSmokerTongueWindowUserId[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Coop SI Damage Control",
	author = "海洋空氣, norths7ar",
	description = "Controls Coop special-infected damage, tongue clears, and fast getup.",
	version = "1.1.0"
};

public void OnPluginStart()
{
    LoadTranslations("si_damage_control.phrases");
	g_cvEnable = CreateConVar("si_damage_enable", "1", "Enable special-infected damage control.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBaseDamage = CreateConVar("si_damage_base", "12.0", "Base special-infected damage.", FCVAR_NOTIFY, true, 1.0, true, 100.0);
	g_cvRatioEnable = CreateConVar("si_damage_ratio_enable", "0", "Use proportional special-infected damage.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFastGetupEnable = CreateConVar("si_damage_fast_getup_enable", "1", "Enable fast getup after special-infected attacks.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	HookConVarChange(g_cvEnable, OnDamageControlEnabledChanged);

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("ability_use", Event_AbilityUse);
	HookEvent("tongue_release", Event_TongueRelease);
	HookEvent("tongue_broke_bent", Event_TongueRelease);
	HookEvent("tongue_pull_stopped", Event_TonguePullStopped);
	HookEvent("charger_carry_start", Event_ChargerCarryStart, EventHookMode_Post);
	HookEvent("charger_pummel_start", Event_ChargerPummelStart, EventHookMode_Post);
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client)) SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public Action Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	int smoker = GetClientOfUserId(event.GetInt("userid"));
	char ability[32];
	event.GetString("ability", ability, sizeof(ability));
	if (StrEqual(ability, "ability_tongue") && IsInfected(smoker) && GetZombieClass(smoker) == ZC_SMOKER)
	{
		// Start on the skill, not tongue_grab; grabbing never extends this window.
		g_iSmokerTongueWindowUserId[smoker] = GetClientUserId(smoker);
		g_fSmokerTongueWindowExpires[smoker] = GetGameTime() + SMOKER_TONGUE_WINDOW_DURATION;
	}
	return Plugin_Continue;
}

public Action Event_TongueRelease(Event event, const char[] name, bool dontBroadcast)
{
	ClearSmokerTongueWindow(GetClientOfUserId(event.GetInt("userid")));
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
	ClearSmokerTongueWindow(smoker);

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
	ClearSmokerTongueWindow(victim);

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

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	ClearSmokerTongueWindow(client);
	if (IsClientAndInGame(client))
	{
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
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

// End immunity about one second after the carry ends.
// There is some time between carryend and pummelbegin, but pummelbegin does not
// always get called if the Charger died first, so it is unreliable.
// 轨迹注：拆分时保留原有 charger_pummel_start 事件，不在架构迁移中改变触发时机。
public Action Event_ChargerPummelStart(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	g_bIsUsingAbility[charger] = false;
	return Plugin_Continue;
}

// 插件重读的时候也重新 Hook。
public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		ClearSmokerTongueWindow(client);
		if (IsClientInGame(client))
		{
			SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		}
	}
}

public void OnClientPutInServer(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		ClearSmokerTongueWindow(client);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public void OnClientDisconnect(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		ClearSmokerTongueWindow(client);
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

	if (IsInfected(victim) && GetZombieClass(victim) == ZC_SMOKER && IsSmokerTongueWindowActive(victim))
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
		CPrintToChatAll("[{olive}Ast{default}] {red}%s{default} %t", g_sSINames[zombieClass], "DamageSummary", remainingHealth, g_fDamagePrint);
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

void OnDamageControlEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!convar.BoolValue)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			ClearSmokerTongueWindow(client);
		}
	}
}

void ClearSmokerTongueWindow(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_fSmokerTongueWindowExpires[client] = 0.0;
	g_iSmokerTongueWindowUserId[client] = 0;
}

bool IsSmokerTongueWindowActive(int smoker)
{
	if (!g_cvEnable.BoolValue || g_iSmokerTongueWindowUserId[smoker] != GetClientUserId(smoker))
	{
		ClearSmokerTongueWindow(smoker);
		return false;
	}

	if (GetGameTime() >= g_fSmokerTongueWindowExpires[smoker])
	{
		ClearSmokerTongueWindow(smoker);
		return false;
	}

	return true;
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
