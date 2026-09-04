#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "Tank Health",
    author = "norths7ar",
    description = "Controls newly spawned Tank health and engine scaling.",
    version = "1.0.0"
};

ConVar g_cvSpawnHealth;
ConVar g_cvEngineScale;

public void OnPluginStart()
{
    g_cvSpawnHealth = CreateConVar("tank_spawn_health", "1200", "Final health assigned to newly spawned Tanks.", FCVAR_NOTIFY, true, 1.0);
    g_cvEngineScale = CreateConVar("tank_health_engine_scale", "1.5", "Current mutation's engine Tank health multiplier.", FCVAR_DONTRECORD, true, 0.1);
    HookConVarChange(g_cvSpawnHealth, ConVarChanged_Health);
    HookConVarChange(g_cvEngineScale, ConVarChanged_Health);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);
}

public void OnConfigsExecuted()
{
    SyncEngineTankHealth();
}

void ConVarChanged_Health(ConVar convar, const char[] oldValue, const char[] newValue)
{
    SyncEngineTankHealth();
}

void SyncEngineTankHealth()
{
    ConVar engineHealth = FindConVar("z_tank_health");
    if (engineHealth == null)
    {
        LogError("[Tank Health] Required cvar does not exist: z_tank_health.");
        return;
    }
    engineHealth.IntValue = RoundToNearest(float(g_cvSpawnHealth.IntValue) / g_cvEngineScale.FloatValue);
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

    int tankHealth = g_cvSpawnHealth.IntValue;
    SetEntProp(tank, Prop_Data, "m_iMaxHealth", tankHealth);
    SetEntityHealth(tank, tankHealth);
}
