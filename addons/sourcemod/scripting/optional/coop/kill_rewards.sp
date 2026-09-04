#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define ZC_WITCH 7
#define ZC_TANK 8

#define WEAPON_SMG "weapon_smg,weapon_smg_silenced"
#define WEAPON_SG "weapon_pumpshotgun,weapon_shotgun_chrome"
#define WEAPON_SNIPER "weapon_sniper_scout,weapon_sniper_awp"

ConVar g_cvHealthEnable;
ConVar g_cvAmmoEnable;
ConVar g_cvSIThreshold;
ConVar g_cvCIThreshold;
ConVar g_cvShotgunAmmo;
ConVar g_cvSmgAmmo;
ConVar g_cvSniperAmmo;

int g_iSIKills[MAXPLAYERS + 1];
int g_iCIKills[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Coop Kill Rewards",
	author = "海洋空氣, norths7ar",
	description = "Provides configurable health and reserve-ammo rewards for Coop kills.",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_cvHealthEnable = CreateConVar("kill_rewards_health_enable", "0", "Enable kill healing rewards.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAmmoEnable = CreateConVar("kill_rewards_ammo_enable", "0", "Enable kill ammo rewards.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSIThreshold = CreateConVar("kill_rewards_si_threshold", "10", "Special infected kills per ammo reward.", FCVAR_NOTIFY, true, 1.0);
	g_cvCIThreshold = CreateConVar("kill_rewards_ci_threshold", "25", "Common infected kills per ammo reward.", FCVAR_NOTIFY, true, 1.0);
	g_cvShotgunAmmo = CreateConVar("kill_rewards_shotgun_ammo", "8", "Shotgun ammo reward.", FCVAR_NOTIFY, true, 1.0);
	g_cvSmgAmmo = CreateConVar("kill_rewards_smg_ammo", "100", "SMG ammo reward.", FCVAR_NOTIFY, true, 1.0);
	g_cvSniperAmmo = CreateConVar("kill_rewards_sniper_ammo", "15", "Sniper ammo reward.", FCVAR_NOTIFY, true, 1.0);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int client = 0; client <= MaxClients; client++)
	{
		g_iSIKills[client] = 0;
		g_iCIKills[client] = 0;
	}
	return Plugin_Handled;
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

	int zombieClass = GetZombieClass(victim);

	// 击杀回血
	if (g_cvHealthEnable.BoolValue && IsSurvivor(attacker) && GetEntProp(attacker, Prop_Send, "m_isIncapacitated") == 0)
	{
		bool headshot = event.GetBool("headshot");
		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));
		int health = GetEntProp(attacker, Prop_Data, "m_iHealth");
		int totalHealth = GetClientHealth(attacker);
		int addHealth = 0;

		switch (zombieClass)
		{
			case 1: // Smoker
			{
				addHealth++;
			}
			case 2: {} // Boomer
			case 3: // Hunter
			{
				if (StrEqual(weapon, "pistol_magnum", false)
					|| StrEqual(weapon, "pistol", false)
					|| StrEqual(weapon, "smg", false)
					|| StrEqual(weapon, "smg_silenced", false))
				{
					addHealth += 2;
				}
				else if (StrEqual(weapon, "pumpshotgun", false)
					|| StrEqual(weapon, "shotgun_chrome", false)
					|| StrEqual(weapon, "sniper_scout", false))
				{
					addHealth++;
				}
				if (!IsGrounded(victim))
				{
					addHealth++;
				}
			}
			case 4: {} // Spitter
			case 5: // Jockey
			{
				addHealth++;
				if (!IsGrounded(victim))
				{
					addHealth++;
				}
			}
			case 6: // Charger
			{
				addHealth++;
			}
			case 7: {} // Witch
			case 8: {} // Tank
		}

		// 额外加血，降低难度
		if (zombieClass > 0 && headshot)
		{
			addHealth++;
		}
		if (health > 40 && health < 70)
		{
			addHealth += 2;
		}
		else if (health > 20)
		{
			addHealth += 3;
		}
		else if (health <= 10 && totalHealth < 40)
		{
			addHealth += 7;
		}

		SetEntProp(attacker, Prop_Data, "m_iHealth", health + addHealth);
		if (health + addHealth > 100)
		{
			SetEntProp(attacker, Prop_Data, "m_iHealth", 100);
		}
	}

	// 击杀回复备弹，打开开关才开始计数
	if (g_cvAmmoEnable.BoolValue && IsSurvivor(attacker))
	{
		int primaryWeapon = GetPlayerWeaponSlot(attacker, 0);
		if (primaryWeapon == -1)
		{
			return Plugin_Handled;
		}

		char primaryClass[32];
		GetEdictClassname(primaryWeapon, primaryClass, sizeof(primaryClass));
		int ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");

		if (zombieClass < ZC_WITCH)
		{
			g_iSIKills[attacker]++;
		}
		if (zombieClass == ZC_WITCH || g_iSIKills[attacker] % g_cvSIThreshold.IntValue == 0)
		{
			GiveAmmo(attacker, primaryClass, ammoOffset);
		}
		if (zombieClass == ZC_TANK)
		{
			for (int client = 1; client <= MaxClients; client++)
			{
				if (!IsClientInGame(client) || IsFakeClient(client) || !IsSurvivor(client))
				{
					continue;
				}
				GiveAmmo(client, primaryClass, ammoOffset);
			}
		}
	}

	return Plugin_Continue;
}

public Action Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsSurvivor(attacker))
	{
		return Plugin_Handled;
	}

	if (g_cvAmmoEnable.BoolValue)
	{
		g_iCIKills[attacker]++;
		int primaryWeapon = GetPlayerWeaponSlot(attacker, 0);
		if (primaryWeapon == -1)
		{
			return Plugin_Handled;
		}

		char primaryClass[32];
		GetEdictClassname(primaryWeapon, primaryClass, sizeof(primaryClass));
		int ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
		if (g_iCIKills[attacker] % g_cvCIThreshold.IntValue == 0)
		{
			GiveAmmo(attacker, primaryClass, ammoOffset);
		}
	}
	return Plugin_Continue;
}

void GiveAmmo(int client, const char[] primaryClass, int ammoOffset)
{
	int addAmmo;
	int finalOffset;

	if (StrContains(WEAPON_SMG, primaryClass) >= 0)
	{
		finalOffset = ammoOffset + (5 * 4);
		addAmmo = g_cvSmgAmmo.IntValue;
	}
	else if (StrContains(WEAPON_SG, primaryClass) >= 0)
	{
		finalOffset = ammoOffset + (7 * 4);
		addAmmo = g_cvShotgunAmmo.IntValue;
	}
	else if (StrContains(WEAPON_SNIPER, primaryClass) >= 0)
	{
		finalOffset = ammoOffset + (10 * 4);
		addAmmo = g_cvSniperAmmo.IntValue;
	}
	else
	{
		return;
	}

	int currentAmmo = GetEntData(client, finalOffset);
	SetEntData(client, finalOffset, currentAmmo + addAmmo);
}

bool IsGrounded(int client)
{
	return (GetEntProp(client, Prop_Data, "m_fFlags") & FL_ONGROUND) > 0;
}

int GetZombieClass(int client)
{
	return GetEntProp(client, Prop_Send, "m_zombieClass");
}

bool IsClientAndInGame(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

bool IsInfected(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_INFECTED;
}

bool IsSurvivor(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}
