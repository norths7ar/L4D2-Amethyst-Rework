#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define GRACE_TIME 5.0
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "AstRedux AutoWipe Adapter",
    author = "Breezy, 海洋空氣, norths7ar",
    description = "Keeps AutoWipe loaded while allowing AstRedux profiles to enable it declaratively.",
    version = "1.3-redux"
};

ConVar g_cvEnabled;
ConVar g_cvWipeDamage;
ConVar g_cvMaxIncaps;
ConVar g_cvReviveHealth;

bool g_bCanStart;
bool g_bWipePending;
bool g_bRoundLive;
int g_iSurvivorHealth[MAXPLAYERS + 1];
float g_fSurvivorTempHealth[MAXPLAYERS + 1];

public void OnPluginStart()
{
    HookEvent("tongue_grab", Event_SurvivorDominated);
    HookEvent("jockey_ride", Event_SurvivorDominated);
    HookEvent("lunge_pounce", Event_SurvivorDominated);
    HookEvent("charger_carry_start", Event_SurvivorDominated);
    HookEvent("player_left_start_area", Event_EnableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_DisableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("mission_lost", Event_DisableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_DisableAutoWipe, EventHookMode_PostNoCopy);

    g_cvWipeDamage = CreateConVar("aw_wipedamage", "40", "Survivor health cost when AstRedux AutoWipe revives the team.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
    g_cvMaxIncaps = FindConVar("survivor_max_incapacitated_count");
    g_cvReviveHealth = FindConVar("survivor_revive_health");
}

public void OnMapStart()
{
    g_bCanStart = false;
    g_bWipePending = false;
    g_bRoundLive = false;
}

public Action Event_DisableAutoWipe(Event event, const char[] name, bool dontBroadcast)
{
    g_bCanStart = false;
    g_bWipePending = false;
    g_bRoundLive = false;
    return Plugin_Continue;
}

public Action Event_EnableAutoWipe(Event event, const char[] name, bool dontBroadcast)
{
    g_bRoundLive = true;
    g_bCanStart = IsEnabled();
    return Plugin_Continue;
}

public Action Event_SurvivorDominated(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (!IsSurvivor(victim))
    {
        return Plugin_Continue;
    }

    g_iSurvivorHealth[victim] = GetClientHealth(victim);
    g_fSurvivorTempHealth[victim] = L4D_GetTempHealth(victim);
    return Plugin_Continue;
}

public void OnGameFrame()
{
    if (!IsEnabled())
    {
        g_bCanStart = false;
        g_bWipePending = false;
        return;
    }

    if (g_bRoundLive && !g_bWipePending)
    {
        g_bCanStart = true;
    }

    if (g_bWipePending || IsTeamDead() || !g_bCanStart || g_cvMaxIncaps == null || g_cvMaxIncaps.IntValue == 0)
    {
        return;
    }

    if (IsTeamPinned())
    {
        CreateTimer(1.0, Timer_AutoWipe, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bWipePending = true;
    }
    else if (IsTeamImmobilised())
    {
        CreateTimer(GRACE_TIME, Timer_AutoWipe, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bCanStart = false;
        g_bWipePending = true;
    }
}

public Action Timer_AutoWipe(Handle timer)
{
    if (IsEnabled() && IsTeamImmobilised() && !IsTeamIncapacitated())
    {
        WipeSurvivors();
    }

    g_bCanStart = IsEnabled();
    g_bWipePending = false;
    return Plugin_Stop;
}

void WipeSurvivors()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            int remainingHealth = g_iSurvivorHealth[client] - g_cvWipeDamage.IntValue;
            float remainingTotal = g_fSurvivorTempHealth[client] + float(remainingHealth);

            if (IsIncapacitated(client))
            {
                SetEntProp(client, Prop_Send, "m_isIncapacitated", false);
            }

            if (remainingHealth >= 1)
            {
                SetEntityHealth(client, remainingHealth);
                L4D_SetTempHealth(client, g_fSurvivorTempHealth[client]);
            }
            else if (remainingTotal >= 1.0)
            {
                SetEntityHealth(client, 1);
                L4D_SetTempHealth(client, remainingTotal);
            }
            else
            {
                int reviveCount = GetEntProp(client, Prop_Send, "m_currentReviveCount") + 1;
                SetEntProp(client, Prop_Send, "m_currentReviveCount", reviveCount);
                SetEntityHealth(client, 1);

                if (reviveCount == g_cvMaxIncaps.IntValue)
                {
                    SetEntProp(client, Prop_Send, "m_isGoingToDie", 1);
                    SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 1);
                }
                else if (reviveCount > g_cvMaxIncaps.IntValue)
                {
                    ForcePlayerSuicide(client);
                    continue;
                }

                if (g_cvReviveHealth != null)
                {
                    L4D_SetTempHealth(client, g_cvReviveHealth.FloatValue);
                }
            }
        }
        else if (IsInfected(client) && GetEntProp(client, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
        {
            ForcePlayerSuicide(client);
        }
    }
}

bool IsEnabled()
{
    if (g_cvEnabled == null)
    {
        g_cvEnabled = FindConVar("astredux_autowipe_enable");
    }
    return g_cvEnabled != null && g_cvEnabled.BoolValue;
}

bool IsTeamImmobilised()
{
    bool foundAliveSurvivor;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            foundAliveSurvivor = true;
            if (!IsPinned(client) && !IsIncapacitated(client))
            {
                return false;
            }
        }
    }
    return foundAliveSurvivor;
}

bool IsTeamPinned()
{
    bool foundAliveSurvivor;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            foundAliveSurvivor = true;
            if (!IsPinned(client))
            {
                return false;
            }
        }
    }
    return foundAliveSurvivor;
}

bool IsTeamIncapacitated()
{
    bool foundAliveSurvivor;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            foundAliveSurvivor = true;
            if (!IsIncapacitated(client))
            {
                return false;
            }
        }
    }
    return foundAliveSurvivor;
}

bool IsTeamDead()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            return false;
        }
    }
    return true;
}

bool IsPinned(int client)
{
    return GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0;
}

bool IsIncapacitated(int client)
{
    return IsSurvivor(client) && (GetEntProp(client, Prop_Send, "m_isIncapacitated") > 0 || !IsPlayerAlive(client));
}

bool IsSurvivor(int client)
{
    return IsValidClient(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsInfected(int client)
{
    return IsValidClient(client) && GetClientTeam(client) == TEAM_INFECTED;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}
