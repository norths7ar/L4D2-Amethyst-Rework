#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "Tank Melee Damage",
    author = "norths7ar",
    description = "Sets fixed damage dealt to Tanks by weapon_melee attacks.",
    version = "1.0.0"
};

ConVar g_cvDamage;

public void OnPluginStart()
{
    g_cvDamage = CreateConVar("tank_melee_damage", "300.0", "Fixed damage dealt to Tanks by weapon_melee attacks.", FCVAR_NOTIFY, true, 1.0);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
}

public Action Hook_TankMeleeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (damage <= 0.0 || victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED || GetEntProp(victim, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
    {
        return Plugin_Continue;
    }
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
    {
        return Plugin_Continue;
    }

    int weaponEntity = weapon;
    if (weaponEntity <= MaxClients || !IsValidEntity(weaponEntity))
    {
        weaponEntity = inflictor;
    }
    if (weaponEntity <= MaxClients || !IsValidEntity(weaponEntity))
    {
        return Plugin_Continue;
    }

    char classname[64];
    GetEntityClassname(weaponEntity, classname, sizeof(classname));
    if (!StrEqual(classname, "weapon_melee"))
    {
        return Plugin_Continue;
    }

    damage = g_cvDamage.FloatValue;
    return Plugin_Changed;
}
