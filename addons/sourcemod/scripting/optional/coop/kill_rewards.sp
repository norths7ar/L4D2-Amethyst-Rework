#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <coop_skill_detect>

// Balance policy is centralized here; only feature switches are exposed to !ast.
#define SI_BASE_HEALTH 2
#define LOW_HEALTH_THRESHOLD 40
#define CRITICAL_HEALTH_THRESHOLD 20
#define LOW_HEALTH_BONUS 2
#define CRITICAL_HEALTH_BONUS 3
#define SI_HEALTH_PER_STAR 1
#define WITCH_BASE_HEALTH 5
#define WITCH_CROWN_HEALTH 8
#define WITCH_DRAW_HEALTH 15
#define SMG_AMMO_REWARD 20
#define SHOTGUN_AMMO_REWARD 4
#define SNIPER_AMMO_REWARD 3
ConVar g_HealthEnabled, g_WitchHealthEnabled, g_AmmoEnabled, g_Decay;
public Plugin myinfo =
{
    name = "Coop Kill Rewards",
    author = "海洋空氣, norths7ar",
    description = "Settles health and capped reserve ammo from unified skill events.",
    version = "2.1.0"
};
public void OnPluginStart()
{
    g_HealthEnabled = CreateConVar("kill_rewards_health_enable", "0", "Enable kill healing rewards.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_WitchHealthEnabled = CreateConVar("kill_rewards_witch_health_enable", "1", "Enable Witch healing independently of special infected healing.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_AmmoEnabled = CreateConVar("kill_rewards_ammo_enable", "0", "Enable kill ammo rewards.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_Decay = FindConVar("pain_pills_decay_rate");
}
public void OnSkillKillResolved(int survivor, int victim, CoopSkill skill, int stars,
    int zombieClass, const char[] weapon, int healthBefore)
{
    if (!CanReceive(survivor) || zombieClass < 1 || zombieClass > 7) return;
    if (zombieClass == 7 ? g_WitchHealthEnabled.BoolValue : g_HealthEnabled.BoolValue)
    {
        int amount;
        if (zombieClass == 7)
        {
            amount = skill == Skill_WitchDraw ? WITCH_DRAW_HEALTH
                : (skill == Skill_WitchCrown ? WITCH_CROWN_HEALTH : WITCH_BASE_HEALTH);
        }
        else
        {
            amount = SI_BASE_HEALTH + stars * SI_HEALTH_PER_STAR;
            if (healthBefore < CRITICAL_HEALTH_THRESHOLD) amount += CRITICAL_HEALTH_BONUS;
            else if (healthBefore < LOW_HEALTH_THRESHOLD) amount += LOW_HEALTH_BONUS;
        }
        GiveHealth(survivor, amount);
    }
    if (g_AmmoEnabled.BoolValue && zombieClass <= 6) GiveAmmo(survivor, weapon);
}
bool CanReceive(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && GetClientTeam(client) == 2 && IsPlayerAlive(client)
        && !GetEntProp(client, Prop_Send, "m_isIncapacitated")
        && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}
void GiveHealth(int client, int amount)
{
    int health = GetClientHealth(client);
    if (health >= 100) return;
    int target = health + amount;
    if (target > 100) target = 100;
    float buffer = GetEntPropFloat(client, Prop_Send, "m_healthBuffer")
        - (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * g_Decay.FloatValue;
    if (buffer < 0.0) buffer = 0.0;
    if (buffer > float(100 - target)) buffer = float(100 - target);
    SetEntityHealth(client, target);
    SetEntPropFloat(client, Prop_Send, "m_healthBuffer", buffer);
    SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}
void GiveAmmo(int client, const char[] killingWeapon)
{
    // Only the primary that actually made the kill receives reserve ammo.
    int primary = GetPlayerWeaponSlot(client, 0);
    if (primary <= MaxClients || !IsValidEntity(primary)) return;
    char classname[64], expected[72], limitName[40];
    GetEntityClassname(primary, classname, sizeof(classname));
    FormatEx(expected, sizeof(expected), "weapon_%s", killingWeapon);
    if (!StrEqual(classname, expected)) return;
    int amount;
    if (StrContains(killingWeapon, "smg") == 0)
    {
        amount = SMG_AMMO_REWARD;
        strcopy(limitName, sizeof(limitName), "ammo_smg_max");
    }
    else if (StrEqual(killingWeapon, "pumpshotgun") || StrEqual(killingWeapon, "shotgun_chrome"))
    {
        amount = SHOTGUN_AMMO_REWARD;
        strcopy(limitName, sizeof(limitName), "ammo_shotgun_max");
    }
    else if (StrEqual(killingWeapon, "autoshotgun") || StrEqual(killingWeapon, "shotgun_spas"))
    {
        amount = SHOTGUN_AMMO_REWARD;
        strcopy(limitName, sizeof(limitName), "ammo_autoshotgun_max");
    }
    else if (StrContains(killingWeapon, "sniper_") == 0 || StrEqual(killingWeapon, "hunting_rifle"))
    {
        amount = SNIPER_AMMO_REWARD;
        strcopy(limitName, sizeof(limitName), StrEqual(killingWeapon, "hunting_rifle") ? "ammo_huntingrifle_max" : "ammo_sniperrifle_max");
    }
    else return;
    ConVar limit = FindConVar(limitName);
    if (limit == null) return;
    int ammoType = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
    if (ammoType < 0) return;
    int current = GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
    int maximum = limit.IntValue;
    if (current >= maximum) return;
    int target = current + amount;
    if (target > maximum) target = maximum;
    SetEntProp(client, Prop_Send, "m_iAmmo", target, _, ammoType);
}
