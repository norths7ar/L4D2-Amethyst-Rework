#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "AstRedux Rules",
    author = "norths7ar",
    description = "Owns profile-driven Tank, Witch, and weapon rules for AstRedux.",
    version = "1.0.0"
};

ConVar g_cvTankHealth;
ConVar g_cvTankMeleeDamage;
ConVar g_cvTankEngineScale;
ConVar g_cvNoWitch;
ConVar g_cvSmgReloadDuration;
ConVar g_cvSilencedSmgReloadDuration;

public void OnPluginStart()
{
    g_cvTankHealth = CreateConVar("astredux_tank_spawn_health", "1200", "Final health assigned to newly spawned Tanks.", FCVAR_NOTIFY, true, 1.0);
    g_cvTankMeleeDamage = CreateConVar("astredux_tank_melee_damage", "300.0", "Fixed damage dealt to Tanks by weapon_melee attacks.", FCVAR_NOTIFY, true, 1.0);
    g_cvTankEngineScale = CreateConVar("astredux_tank_engine_scale", "1.5", "Current mutation's engine Tank health multiplier.", FCVAR_DONTRECORD, true, 0.1);
    g_cvNoWitch = CreateConVar("astredux_no_witch", "1", "Block future Witch spawns for the active profile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvSmgReloadDuration = CreateConVar("astredux_smg_reload_duration", "1.4", "SMG reload duration for the active profile.", FCVAR_DONTRECORD, true, 0.1);
    g_cvSilencedSmgReloadDuration = CreateConVar("astredux_smg_silenced_reload_duration", "1.5", "Silenced SMG reload duration for the active profile.", FCVAR_DONTRECORD, true, 0.1);

    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
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

public void OnEntityCreated(int entity, const char[] classname)
{
    if (g_cvNoWitch.BoolValue && (StrEqual(classname, "witch") || StrEqual(classname, "witch_bride")))
    {
        RequestFrame(Frame_RemoveWitch, EntIndexToEntRef(entity));
    }
}

public void Frame_RemoveWitch(any entityReference)
{
    int entity = EntRefToEntIndex(entityReference);
    if (g_cvNoWitch.BoolValue && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Kill");
    }
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (tank > 0)
    {
        RequestFrame(Frame_ApplyTankHealth, GetClientUserId(tank));
    }
}

public void Frame_ApplyTankHealth(any userId)
{
    int tank = GetClientOfUserId(userId);
    if (tank <= 0 || !IsClientInGame(tank) || GetClientTeam(tank) != TEAM_INFECTED || GetEntProp(tank, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
    {
        return;
    }

    int tankHealth = g_cvTankHealth.IntValue;
    SetEntProp(tank, Prop_Data, "m_iMaxHealth", tankHealth);
    SetEntityHealth(tank, tankHealth);
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

    damage = g_cvTankMeleeDamage.FloatValue;
    return Plugin_Changed;
}

public void AstRedux_OnProfileApplied(int profile)
{
    ConVar tankHealth = FindConVar("z_tank_health");
    if (tankHealth != null)
    {
        tankHealth.IntValue = RoundToNearest(float(g_cvTankHealth.IntValue) / g_cvTankEngineScale.FloatValue);
    }
    else
    {
        LogError("[AstRedux] Required cvar does not exist: z_tank_health.");
    }

    if (GetCommandFlags("sm_weapon") == INVALID_FCVAR_FLAGS)
    {
        LogError("[AstRedux] Required server command does not exist: sm_weapon.");
        return;
    }

    ServerCommand("sm_weapon smg reloadduration %.6f", g_cvSmgReloadDuration.FloatValue);
    ServerCommand("sm_weapon smg_silenced reloadduration %.6f", g_cvSilencedSmgReloadDuration.FloatValue);
}
