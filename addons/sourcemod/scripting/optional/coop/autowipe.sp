#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

// Original AutoWipe 1.2 rationale:
// This plugin was created because of a Hard12 bug where one or more survivors were not taking damage while pinned
// by special infected. Only a currently fully pinned team receives automatic rescue.
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "AutoWipe",
    author = "Breezy, 海洋空氣, norths7ar",
    description = "Automatically rescues survivors when every living teammate is pinned.",
    version = "1.5.0"
};

ConVar g_cvEnabled;
ConVar g_cvWipeDamage;
ConVar g_cvMaxIncaps;
ConVar g_cvReviveHealth;

bool g_bCanStart;      // Prevent AutoWipe before survivors have left the start area.
bool g_bWipePending;   // Prevent multiple wipe timers from being scheduled together.
Handle g_hWipeTimer;
bool g_bRoundLive;

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar("autowipe_enable", "0", "Enable AutoWipe.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    // Enable only after the round starts; disable again at every round boundary.
    HookEvent("player_left_start_area", Event_EnableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_DisableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("mission_lost", Event_DisableAutoWipe, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_DisableAutoWipe, EventHookMode_PostNoCopy);

    g_cvWipeDamage = CreateConVar("autowipe_wipe_damage", "40", "Survivor health cost when AutoWipe revives the team.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
    g_cvMaxIncaps = FindConVar("survivor_max_incapacitated_count");
    g_cvReviveHealth = FindConVar("survivor_revive_health");
}

public void OnMapStart()
{
    g_bCanStart = false;
    g_bWipePending = false;
    g_bRoundLive = false;
}

public void OnMapEnd()
{
    g_hWipeTimer = null; // TIMER_FLAG_NO_MAPCHANGE owns its destruction.
}


public Action Event_DisableAutoWipe(Event event, const char[] name, bool dontBroadcast)
{
    g_bCanStart = false;
    g_bWipePending = false;
    g_bRoundLive = false;
    delete g_hWipeTimer;
    return Plugin_Continue;
}

public Action Event_EnableAutoWipe(Event event, const char[] name, bool dontBroadcast)
{
    g_bRoundLive = true;
    g_bCanStart = IsEnabled();
    return Plugin_Continue;
}

public void OnGameFrame()
{
    if (!IsEnabled())
    {
        g_bCanStart = false;
        g_bWipePending = false;
        delete g_hWipeTimer;
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

    // A fully pinned team cannot recover by itself, so release it quickly.
    if (IsTeamPinned())
    {
        g_hWipeTimer = CreateTimer(1.0, Timer_AutoWipe, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bWipePending = true;
    }
}

public Action Timer_AutoWipe(Handle timer)
{
    g_hWipeTimer = null;
    if (g_bRoundLive && IsEnabled() && IsTeamPinned())
    {
        WipeSurvivors();
    }

    g_bCanStart = IsEnabled();
    g_bWipePending = false;
    return Plugin_Stop;
}

void WipeSurvivors()
{
    // Capture settlement before releasing attackers: release callbacks can change health/state.
    bool wasIncapped[MAXPLAYERS + 1];
    int health[MAXPLAYERS + 1], reviveCounts[MAXPLAYERS + 1];
    int dying[MAXPLAYERS + 1], thirdStrikes[MAXPLAYERS + 1];
    float tempHealth[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsSurvivor(client) || !IsPlayerAlive(client)) continue;
        wasIncapped[client] = IsIncapacitated(client);
        health[client] = GetClientHealth(client);
        tempHealth[client] = L4D_GetTempHealth(client);
        reviveCounts[client] = GetEntProp(client, Prop_Send, "m_currentReviveCount");
        dying[client] = GetEntProp(client, Prop_Send, "m_isGoingToDie");
        thirdStrikes[client] = GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike");
    }
    // Release attackers before restoring survivors, regardless of client slot order.
    // Their normal death handling ends pins/carries; an active Tank is preserved.
    for (int attacker = 1; attacker <= MaxClients; attacker++)
    {
        if (IsInfected(attacker) && IsPlayerAlive(attacker)
            && GetEntProp(attacker, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
        {
            ForcePlayerSuicide(attacker);
        }
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsSurvivor(client) && IsPlayerAlive(client))
        {
            // Standing survivors pay from their current health, never a pre-pin snapshot.
            int standingHealth = health[client];
            float standingTempHealth = tempHealth[client];
            int remainingHealth = standingHealth - g_cvWipeDamage.IntValue;
            float remainingTotal = standingTempHealth + float(remainingHealth);

            // OnRevived restores the hidden secondary weapon. This incap was already
            // charged by the game: preserve its count/black-and-white state and do not
            // charge the standing rescue fee a second time.
            int reviveCount = reviveCounts[client];
            if (wasIncapped[client])
            {
                L4D_ReviveSurvivor(client);
                SetEntProp(client, Prop_Send, "m_currentReviveCount", reviveCount);
                SetEntProp(client, Prop_Send, "m_isGoingToDie", dying[client]);
                SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", thirdStrikes[client]);
                SetEntityHealth(client, 1);
                L4D_SetTempHealth(client, g_cvReviveHealth.FloatValue);
                continue;
            }

            if (remainingHealth >= 1)
            {
                SetEntityHealth(client, remainingHealth);
                L4D_SetTempHealth(client, standingTempHealth);
            }
            else if (remainingTotal >= 1.0)
            {
                SetEntityHealth(client, 1);
                L4D_SetTempHealth(client, remainingTotal - 1.0);
            }
            else
            {
                // Not enough total health remains: consume one incap and apply revive health.
                reviveCount++;
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
    }
}

bool IsEnabled()
{
    return g_cvEnabled.BoolValue;
}

bool IsTeamPinned()
{
    // True only when every living survivor is held by a special infected.
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
    // Smoker, Hunter, Charger and Jockey ownership properties.
    return GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0;
}

bool IsIncapacitated(int client)
{
    return IsSurvivor(client) && (GetEntProp(client, Prop_Send, "m_isIncapacitated") > 0
        || GetEntProp(client, Prop_Send, "m_isHangingFromLedge") > 0 || !IsPlayerAlive(client));
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
