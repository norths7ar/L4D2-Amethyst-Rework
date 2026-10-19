#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <actions>
#include <ai_diagnostics>

native bool IsInPause();

ConVar g_enable, g_charger, g_smoker, g_duration;
bool g_roundEnded;
BehaviorAction g_retreat[MAXPLAYERS + 1];
bool g_pending[MAXPLAYERS + 1], g_owned[MAXPLAYERS + 1], g_release[MAXPLAYERS + 1];
int g_victim[MAXPLAYERS + 1], g_commandVictim[MAXPLAYERS + 1];
float g_deadline[MAXPLAYERS + 1], g_nextCommand[MAXPLAYERS + 1];
float g_destination[MAXPLAYERS + 1][3], g_nextDiagnostic[MAXPLAYERS + 1];
char g_lastDiagnostic[MAXPLAYERS + 1][64];

public Plugin myinfo =
{
    name = "SI native anti-retreat",
    author = "OpenAI",
    description = "Bounded pursuit during confirmed Charger and Smoker retreat actions",
    version = "1.0.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    MarkNativeAsOptional("IsInPause");
    RegPluginLibrary("si_anti_retreat");
    CreateNative("SI_AntiRetreat_YieldMovement", Native_YieldMovement);
    return APLRes_Success;
}

// The watchdog can supersede this plugin's MOVE without racing its deferred
// release callback or having retreat immediately reissue MOVE during recovery.
// Returns whether releasing our owned command already issued the caller's RESET.
public any Native_YieldMovement(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if (!IsNormalBot(client)) return false;
    bool owned = g_owned[client];
    ReleaseCommand(client, "release_to_unstuck");
    g_nextCommand[client] = GetGameTime() + view_as<float>(GetNativeCell(2));
    return owned;
}

public void OnPluginStart()
{
    g_enable = CreateConVar("si_anti_retreat_enable", "1", "Intercept confirmed native SI retreat actions", _, true, 0.0, true, 1.0);
    g_charger = CreateConVar("si_anti_retreat_charger", "1", "Intercept ChargerEvade only", _, true, 0.0, true, 1.0);
    g_smoker = CreateConVar("si_anti_retreat_smoker", "1", "Intercept unpinned SmokerRetreatToCover while tongue is cooling down", _, true, 0.0, true, 1.0);
    g_duration = CreateConVar("si_anti_retreat_command_time", "1.0", "Maximum lifetime of one pursuit command before yielding to native AI", _, true, 0.1, true, 3.0);
    g_enable.AddChangeHook(OnPolicyChanged);
    g_charger.AddChangeHook(OnPolicyChanged);
    g_smoker.AddChangeHook(OnPolicyChanged);
    HookEvent("player_spawn", OnSpawn);
    HookEvent("player_death", OnDeath);
    HookEvent("round_end", OnRoundEnd);
    HookEvent("round_start", OnRoundStart);
    // A command-generated BehaviorMoveTo is not always reported by Actions.
    // Maintain our own bounded ownership, not hooks on every BehaviorMoveTo.
    CreateTimer(0.1, MonitorCommands, _, TIMER_REPEAT);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsNormalBot(client)) ActionsManager.Iterator(client, HookExistingAction);
    }
}

public void HookExistingAction(BehaviorAction action)
{
    char name[ACTION_NAME_LENGTH];
    action.GetName(name, sizeof(name));
    OnActionCreated(action, action.Actor, name);
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
    if (action == INVALID_ACTION || !IsNormalBot(actor)) return;
    int zombieClass = GetEntProp(actor, Prop_Send, "m_zombieClass");
    // Evidence: Anne ai_charger3 and ai_smoker3. Do not infer generic Retreat,
    // OnInjured, backward input or obstacle avoidance as equivalent actions.
    if ((zombieClass == 6 && StrEqual(name, "ChargerEvade"))
        || (zombieClass == 1 && StrEqual(name, "SmokerRetreatToCover")))
    {
        action.OnUpdate = OnRetreatUpdate;
        action.OnEnd = OnRetreatEnd;
    }
}

public Action OnRetreatUpdate(BehaviorAction action, int actor, float interval, ActionResult result)
{
    if (!IsNormalBot(actor)) return Plugin_Continue;
    if (g_owned[actor] || g_pending[actor] || g_release[actor]) return Plugin_Continue;
    char reason[64];
    if (!CanIntercept(actor, reason, sizeof(reason)))
    {
        Diagnostic(actor, reason);
        return Plugin_Continue;
    }
    if (GetGameTime() < g_nextCommand[actor]) return Plugin_Continue;
    int target = GetClientOfUserId(g_victim[actor]);
    if (!IsSurvivor(target))
    {
        Diagnostic(actor, "skip_no_native_victim");
        return Plugin_Continue;
    }
    g_retreat[actor] = action;
    g_pending[actor] = true;
    // CommandABot synchronously changes the action tree. Never call it inside
    // an Actions propagation stack (including OnEnd and the destructor).
    RequestFrame(IssuePursuit, GetClientUserId(actor));
    return Plugin_Continue;
}

public void IssuePursuit(any userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0 || !g_pending[client]) return;
    g_pending[client] = false;
    char reason[64];
    if (!IsNormalBot(client) || g_release[client] || g_retreat[client] == INVALID_ACTION
        || !CanIntercept(client, reason, sizeof(reason))) return;
    int target = GetClientOfUserId(g_victim[client]);
    if (!IsSurvivor(target)) return;
    float position[3];
    GetClientAbsOrigin(target, position);
    Address area = L4D_GetNearestNavArea(position, 200.0, false, true, true, 2);
    if (area == Address_Null)
    {
        Diagnostic(client, "skip_target_nav_unavailable");
        g_nextCommand[client] = GetGameTime() + 1.0;
        return;
    }
    L4D_GetNavAreaCenter(area, g_destination[client]);
    // Anne documents a false return even when MOVE has created BehaviorMoveTo.
    // Track the issued command so every exit still attempts RESET.
    g_owned[client] = true;
    g_commandVictim[client] = GetClientUserId(target);
    g_deadline[client] = GetGameTime() + g_duration.FloatValue;
    bool accepted = L4D2_CommandABot(client, target, BOT_CMD_MOVE, g_destination[client]);
    Diagnostic(client, accepted ? "pursuit_issued" : "pursuit_issued_result_false");
}

public void OnRetreatEnd(BehaviorAction action, int actor, BehaviorAction nextAction, ActionResult result)
{
    QueueRelease(action, actor);
}

public void OnActionDestroyed(BehaviorAction action, int actor, const char[] name)
{
    QueueRelease(action, actor);
}

void QueueRelease(BehaviorAction action, int client)
{
    if (client < 1 || client > MaxClients || g_retreat[client] != action) return;
    g_retreat[client] = INVALID_ACTION;
    g_pending[client] = false;
    if (g_owned[client] && !g_release[client])
    {
        g_release[client] = true;
        RequestFrame(ReleaseNextFrame, GetClientUserId(client));
    }
}

public void ReleaseNextFrame(any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && g_release[client]) ReleaseCommand(client, "release_action_ended");
}

public Action MonitorCommands(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_owned[client]) continue;
        char reason[64];
        if (!IsNormalBot(client)) ReleaseCommand(client, "release_ineligible");
        else if (!CanIntercept(client, reason, sizeof(reason))) ReleaseCommand(client, reason);
        else if (g_release[client]) ReleaseCommand(client, "release_action_ended");
        else if (g_commandVictim[client] != g_victim[client]
            || !IsSurvivor(GetClientOfUserId(g_commandVictim[client]))) ReleaseCommand(client, "release_victim_changed");
        else if (GetGameTime() >= g_deadline[client]) ReleaseCommand(client, "release_timeout");
        else
        {
            float position[3];
            GetClientAbsOrigin(client, position);
            if (GetVectorDistance(position, g_destination[client]) < 80.0) ReleaseCommand(client, "release_destination_reached");
        }
    }
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (g_owned[client])
    {
        char reason[64];
        // Recheck native motion at command frequency, not just the timer.
        if (!IsNormalBot(client) || !CanIntercept(client, reason, sizeof(reason))) ReleaseCommand(client, "release_native_motion_or_policy");
        else if (buttons & (IN_ATTACK | IN_ATTACK2)) ReleaseCommand(client, "release_attack_input");
    }
    return Plugin_Continue;
}

void ReleaseCommand(int client, const char[] reason)
{
    bool owned = g_owned[client];
    g_owned[client] = false;
    g_pending[client] = false;
    g_release[client] = false;
    g_commandVictim[client] = 0;
    // Give native attack/route decisions a real window before another MOVE.
    g_nextCommand[client] = GetGameTime() + 0.5;
    if (owned && IsClientInGame(client) && IsFakeClient(client)
        && IsPlayerAlive(client) && GetClientTeam(client) == 3)
    {
        L4D2_CommandABot(client, 0, BOT_CMD_RESET);
        Diagnostic(client, reason);
    }
}

bool CanIntercept(int client, char[] reason, int length)
{
    if (!g_enable.BoolValue) strcopy(reason, length, "skip_disabled");
    else if (g_roundEnded) strcopy(reason, length, "skip_round_ended");
    else if (GetFeatureStatus(FeatureType_Native, "IsInPause") == FeatureStatus_Available && IsInPause()) strcopy(reason, length, "skip_pause");
    else if (NativeMotion(client)) strcopy(reason, length, "skip_native_motion");
    else
    {
        int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if (zombieClass == 6 && g_charger.BoolValue) return true;
        if (zombieClass == 1 && g_smoker.BoolValue)
        {
            int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
            // Keep native attack positioning as soon as the tongue is ready.
            if (ability > MaxClients && IsValidEntity(ability)
                && HasEntProp(ability, Prop_Send, "m_timestamp")
                && GetEntPropFloat(ability, Prop_Send, "m_timestamp") > GetGameTime()) return true;
            strcopy(reason, length, "skip_tongue_ready_or_unknown");
        }
        else strcopy(reason, length, "skip_class_disabled");
    }
    return false;
}

bool NativeMotion(int client)
{
    if (GetEntityMoveType(client) == MOVETYPE_LADDER || (GetEntityFlags(client) & FL_FROZEN)
        || L4D_IsPlayerStaggering(client)) return true;
    if (GetEntProp(client, Prop_Send, "m_zombieClass") == 6
        && L4D2_GetQueuedPummelVictim(client) > 0) return true;
    static const char victims[][] = {"m_tongueVictim", "m_pounceVictim", "m_carryVictim", "m_pummelVictim", "m_jockeyVictim"};
    for (int i = 0; i < sizeof(victims); i++)
        if (HasEntProp(client, Prop_Send, victims[i]) && GetEntPropEnt(client, Prop_Send, victims[i]) > 0) return true;
    int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
    if (ability > MaxClients && IsValidEntity(ability))
    {
        static const char active[][] = {"m_isCharging", "m_isLunging", "m_isLeaping", "m_isSpraying"};
        for (int i = 0; i < sizeof(active); i++)
            if (HasEntProp(ability, Prop_Send, active[i]) && GetEntProp(ability, Prop_Send, active[i])) return true;
    }
    return false;
}

public Action L4D2_OnChooseVictim(int client, int &target)
{
    if (IsNormalBot(client)) g_victim[client] = IsSurvivor(target) ? GetClientUserId(target) : 0;
    return Plugin_Continue;
}

bool IsNormalBot(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsFakeClient(client)
        || !IsPlayerAlive(client) || GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_isGhost")
        || GetEntityMoveType(client) == MOVETYPE_NOCLIP) return false;
    int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    return zombieClass >= 1 && zombieClass <= 6;
}

bool IsSurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2;
}

void Diagnostic(int client, const char[] reason)
{
    if (StrEqual(g_lastDiagnostic[client], reason) || GetGameTime() < g_nextDiagnostic[client]) return;
    strcopy(g_lastDiagnostic[client], sizeof(g_lastDiagnostic[]), reason);
    g_nextDiagnostic[client] = GetGameTime() + 1.0;
    char detail[160];
    FormatEx(detail, sizeof(detail), "class=%d target=%d owned=%d reason=%s",
        GetEntProp(client, Prop_Send, "m_zombieClass"), GetClientOfUserId(g_victim[client]), g_owned[client], reason);
    AIDiag_TryEvent(client, "si_retreat", detail);
}

public void OnPolicyChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for (int client = 1; client <= MaxClients; client++) ReleaseCommand(client, "release_policy_changed");
}

public void OnSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) ClearClient(client);
}

public void OnDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) ClearClient(client);
}

public void OnClientDisconnect(int client) { ClearClient(client); }
public void OnMapStart()
{
    g_roundEnded = false;
    for (int client = 1; client <= MaxClients; client++) ClearClient(client);
}
public void OnRoundStart(Event event, const char[] name, bool dontBroadcast) { g_roundEnded = false; }
public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast) { g_roundEnded = true; StopAll(); }
public void OnMapEnd() { g_roundEnded = true; StopAll(); }
public void OnPluginEnd() { StopAll(); }
public void OnPause() { StopAll(); }
public void OnPluginPauseChange(bool pause) { if (pause) StopAll(); }

void StopAll()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ReleaseCommand(client, "release_lifecycle");
        ClearClient(client);
    }
}

void ClearClient(int client)
{
    g_retreat[client] = INVALID_ACTION;
    g_owned[client] = false;
    g_pending[client] = false;
    g_release[client] = false;
    g_victim[client] = 0;
    g_commandVictim[client] = 0;
    g_deadline[client] = 0.0;
    g_nextCommand[client] = 0.0;
    g_nextDiagnostic[client] = 0.0;
    g_lastDiagnostic[client][0] = '\0';
}
