#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

// Original AutoWipe 1.2 rationale:
// This plugin was created because of a Hard12 bug where one or more survivors were not taking damage while pinned
// by special infected. If the whole team is immobilised, they get a grace period before they are AutoWiped.
// This component keeps that behavior behind a declarative profile switch.
#define GRACE_TIME 2.0
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

public Plugin myinfo =
{
    name = "AutoWipe",
    author = "Breezy, 海洋空氣, norths7ar",
    description = "Automatically revives survivors when the whole team is immobilised.",
    version = "1.4.1"
};

ConVar g_cvEnabled;
ConVar g_cvWipeDamage;
ConVar g_cvMaxIncaps;
ConVar g_cvReviveHealth;

bool g_bCanStart;      // Prevent AutoWipe before survivors have left the start area.
bool g_bWipePending;   // Prevent multiple wipe timers from being scheduled together.
Handle g_hWipeTimer;
bool g_bRoundLive;
// Health is captured while a survivor is standing. The last standing snapshot
// remains valid while that survivor is pinned or incapacitated.
bool g_bHasHealthSnapshot[MAXPLAYERS + 1];
int g_iSurvivorHealth[MAXPLAYERS + 1];
float g_fSurvivorTempHealth[MAXPLAYERS + 1];

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
    for (int client = 1; client <= MaxClients; client++)
    {
        g_bHasHealthSnapshot[client] = false;
    }
}

public void OnMapEnd()
{
    g_hWipeTimer = null; // TIMER_FLAG_NO_MAPCHANGE owns its destruction.
}

public void OnClientDisconnect(int client)
{
    g_bHasHealthSnapshot[client] = false;
}

public Action Event_DisableAutoWipe(Event event, const char[] name, bool dontBroadcast)
{
    g_bCanStart = false;
    g_bWipePending = false;
    g_bRoundLive = false;
    delete g_hWipeTimer;
    ClearHealthSnapshots();
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
        ClearHealthSnapshots();
        return;
    }

    RefreshHealthSnapshots();

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
    // Allow a short self-rescue window when pins and incapacitations are mixed.
    else if (IsTeamImmobilised())
    {
        g_hWipeTimer = CreateTimer(GRACE_TIME, Timer_AutoWipe, _, TIMER_FLAG_NO_MAPCHANGE);
        g_bCanStart = false;
        g_bWipePending = true;
    }
}

public Action Timer_AutoWipe(Handle timer)
{
    g_hWipeTimer = null;
    if (g_bRoundLive && IsEnabled() && IsTeamImmobilised() && !IsTeamIncapacitated())
    {
        WipeSurvivors();
    }

    g_bCanStart = IsEnabled();
    g_bWipePending = false;
    return Plugin_Stop;
}

void WipeSurvivors()
{
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
            // Pay the wipe cost from the last standing snapshot. If no
            // standing state was observed, use a conservative 1 permanent /
            // 0 temporary fallback rather than an incapacitation health pool.
            int standingHealth = g_bHasHealthSnapshot[client] ? g_iSurvivorHealth[client] : 1;
            float standingTempHealth = g_bHasHealthSnapshot[client] ? g_fSurvivorTempHealth[client] : 0.0;
            int remainingHealth = standingHealth - g_cvWipeDamage.IntValue;
            float remainingTotal = standingTempHealth + float(remainingHealth);

            // OnRevived restores the hidden secondary weapon and completes ledge rescue.
            // Preserve our existing incap accounting: the native must not add another
            // incap or replace black-and-white state before the wipe cost is applied.
            int reviveCount = GetEntProp(client, Prop_Send, "m_currentReviveCount");
            int goingToDie = GetEntProp(client, Prop_Send, "m_isGoingToDie");
            int thirdStrike = GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike");
            if (IsIncapacitated(client))
            {
                L4D_ReviveSurvivor(client);
                SetEntProp(client, Prop_Send, "m_currentReviveCount", reviveCount);
                SetEntProp(client, Prop_Send, "m_isGoingToDie", goingToDie);
                SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", thirdStrike);
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
            g_bHasHealthSnapshot[client] = false;
        }
    }
}

bool IsEnabled()
{
    return g_cvEnabled.BoolValue;
}

void RefreshHealthSnapshots()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsSurvivor(client))
        {
            g_bHasHealthSnapshot[client] = false;
        }
        else if (IsPlayerAlive(client) && !IsPinned(client) && !IsIncapacitated(client))
        {
            g_iSurvivorHealth[client] = GetClientHealth(client);
            g_fSurvivorTempHealth[client] = L4D_GetTempHealth(client);
            g_bHasHealthSnapshot[client] = true;
        }
    }
}

void ClearHealthSnapshots()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_bHasHealthSnapshot[client] = false;
    }
}

bool IsTeamImmobilised()
{
    // True when every living survivor is pinned or incapacitated.
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

bool IsTeamIncapacitated()
{
    // A team that is already fully incapacitated should follow the normal wipe flow.
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
