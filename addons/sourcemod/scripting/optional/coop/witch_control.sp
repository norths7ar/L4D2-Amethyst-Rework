#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <admin_spawn>
#include <profile_controller>
#include <readyup>

enum WitchData
{
    WitchRef,
    WitchAdmin,
    WitchSpawned,
    WitchGlowStopped,
    WitchGlowing,
    WitchDataSize
};

public Plugin myinfo =
{
    name = "Witch Control",
    author = "norths7ar, CanadaRox",
    description = "Owns Witch eligibility and native proximity glow.",
    version = "1.1.0"
};

ConVar g_cvBlock;
ConVar g_cvGlow;
ConVar g_cvRange;
ArrayList g_witches;
bool g_configsReady;
bool g_roundLive;
bool g_livePolicyPending;
float g_minRangeSquared;

public void OnPluginStart()
{
    g_witches = new ArrayList(view_as<int>(WitchDataSize));
    g_cvBlock = CreateConVar("witch_block", "1", "Block future Witch spawns for the active profile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvGlow = CreateConVar("witch_glow_enable", "1", "Enable native Witch proximity glow.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvRange = CreateConVar("wg_min_range", "500", "Glows will not show if a survivor is this close to the witch", FCVAR_NONE, true, 0.0);
    g_minRangeSquared = g_cvRange.FloatValue * g_cvRange.FloatValue;
    g_cvBlock.AddChangeHook(OnPolicyChanged);
    g_cvGlow.AddChangeHook(OnPolicyChanged);
    g_cvRange.AddChangeHook(OnRangeChanged);
    HookEvent("round_start", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("witch_harasser_set", Event_WitchHarassed);
}

public void OnMapEnd()
{
    g_configsReady = false;
    g_roundLive = false;
    g_livePolicyPending = false;
    g_witches.Clear();
}

// Do not reset on OnMapStart: map entities and round_start can precede it.
// Only entities observed at creation are owned; there is no late-load scan.
public void OnConfigsExecuted()
{
    g_configsReady = true;
    RequestFrame(Frame_UpdateGlows);
}

public void Event_RoundBoundary(Event event, const char[] name, bool dontBroadcast)
{
    g_roundLive = false;
    g_livePolicyPending = false;
}

public void OnReadyUpInitiatePre()
{
    g_roundLive = false;
    g_livePolicyPending = false;
}

public void OnRoundIsLive()
{
    // Profile Controller refreshes in OnRoundIsLivePre. The entire Pre forward
    // has finished here, independent of plugin load/forward listener order.
    g_roundLive = true;
    g_livePolicyPending = true;
    UpdateWitches(true);
}

bool PolicyKnown()
{
    return g_configsReady
        && GetFeatureStatus(FeatureType_Native, "ProfileController_GetCurrentProfile") == FeatureStatus_Available
        && ProfileController_GetCurrentProfile() > 0
        && (g_roundLive || (GetFeatureStatus(FeatureType_Native, "IsInReady") == FeatureStatus_Available && IsInReady()));
}

public void ProfileController_OnProfileApplied(int profile)
{
    RequestFrame(Frame_UpdateGlows);
}

public void OnPolicyChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // Clear promptly on a blocked profile; no runtime purge of existing witches.
    UpdateWitches(false);
}

public void OnRangeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_minRangeSquared = convar.FloatValue * convar.FloatValue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "witch") && !StrEqual(classname, "witch_bride")) return;

    int data[WitchData];
    data[WitchRef] = EntIndexToEntRef(entity);
    // The admin native is synchronous. Retain the exemption for this entity's
    // lifetime, not the entity slot or the later Spawn/frame callback.
    data[WitchAdmin] = GetFeatureStatus(FeatureType_Native, "AdminSpawn_IsActive") == FeatureStatus_Available && AdminSpawn_IsActive();
    g_witches.PushArray(data);
    SDKHook(entity, SDKHook_SpawnPost, OnWitchSpawned);
}

public void OnWitchSpawned(int entity)
{
    int reference = EntIndexToEntRef(entity);
    int index = g_witches.FindValue(reference, WitchRef);
    if (index == -1) return;
    g_witches.Set(index, true, WitchSpawned);
    // One deferred owner performs eligibility BEFORE glow, never a separate
    // next-frame removal racing another plugin's witch_spawn glow callback.
    RequestFrame(Frame_WitchSpawned, reference);
}

public void Frame_WitchSpawned(any reference)
{
    int index = g_witches.FindValue(reference, WitchRef);
    if (index != -1) UpdateWitch(index, g_roundLive);
}

public void Frame_UpdateGlows(any unused)
{
    UpdateWitches(false);
}

void UpdateWitches(bool removeBlocked)
{
    if (g_livePolicyPending && PolicyKnown())
    {
        removeBlocked = true;
        g_livePolicyPending = false;
    }
    for (int index = g_witches.Length - 1; index >= 0; index--)
        UpdateWitch(index, removeBlocked);
}

void UpdateWitch(int index, bool removeBlocked)
{
    int entity = EntRefToEntIndex(g_witches.Get(index, WitchRef));
    if (entity == INVALID_ENT_REFERENCE)
    {
        g_witches.Erase(index);
        return;
    }
    if (!g_witches.Get(index, WitchSpawned)) return;

    bool known = PolicyKnown();
    bool allowed = known && (g_witches.Get(index, WitchAdmin) || !g_cvBlock.BoolValue);
    if (known && !allowed && removeBlocked)
    {
        SetGlow(index, entity, false);
        // Preserve native entities/outputs throughout preparation. No snapshots
        // or reconstruction: only the live policy may remove a blocked Witch.
        AcceptEntityInput(entity, "Kill");
        return;
    }
    SetGlow(index, entity, allowed && g_cvGlow.BoolValue && !g_witches.Get(index, WitchGlowStopped));
}

void SetGlow(int index, int entity, bool enabled)
{
    if (view_as<bool>(g_witches.Get(index, WitchGlowing)) == enabled) return;
    SetEntProp(entity, Prop_Send, "m_iGlowType", enabled ? 3 : 0);
    if (enabled) SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0xFFFFFF);
    g_witches.Set(index, enabled, WitchGlowing);
}

void StopGlow(int index, int entity)
{
    g_witches.Set(index, true, WitchGlowStopped);
    SetGlow(index, entity, false);
}

public void Event_WitchHarassed(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("witchid");
    if (entity <= MaxClients || !IsValidEntity(entity)) return;
    int index = g_witches.FindValue(EntIndexToEntRef(entity), WitchRef);
    if (index != -1) StopGlow(index, entity);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsPlayerAlive(client) || GetClientTeam(client) != 2) return Plugin_Continue;
    float clientOrigin[3], witchOrigin[3];
    GetClientAbsOrigin(client, clientOrigin);
    for (int index = g_witches.Length - 1; index >= 0; index--)
    {
        int entity = EntRefToEntIndex(g_witches.Get(index, WitchRef));
        if (entity == INVALID_ENT_REFERENCE)
        {
            g_witches.Erase(index);
            continue;
        }
        if (!g_witches.Get(index, WitchSpawned) || g_witches.Get(index, WitchGlowStopped)) continue;
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", witchOrigin);
        if (GetVectorDistance(clientOrigin, witchOrigin, true) < g_minRangeSquared)
            StopGlow(index, entity);
    }
    return Plugin_Continue;
}

public void OnPluginEnd()
{
    for (int index = 0; index < g_witches.Length; index++)
    {
        int entity = EntRefToEntIndex(g_witches.Get(index, WitchRef));
        if (entity != INVALID_ENT_REFERENCE && g_witches.Get(index, WitchSpawned))
            SetGlow(index, entity, false);
    }
}
