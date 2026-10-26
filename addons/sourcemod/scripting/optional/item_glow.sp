#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>
#include <si_unstuck>

#define ENTITY_LIMIT 2048

enum GlowKind
{
    Glow_None,
    Glow_Supply,
    Glow_Hittable,
    Glow_StalledTank,
    Glow_BlackWhiteSurvivor
};

bool g_mapActive;
bool g_roundEnded;

#include "item_glow/outline.inc"
#include "item_glow/supplies.inc"
#include "item_glow/hittables.inc"
#include "item_glow/tank_stall.inc"
#include "item_glow/blackwhite.inc"

public Plugin myinfo =
{
    name = "Coop item glow",
    author = "norths7ar",
    description = "Independent supply, hittable, stalled Tank and black-and-white survivor outlines.",
    version = "1.4.0"
};

public void OnPluginStart()
{
    for (int entity = 0; entity < ENTITY_LIMIT; entity++)
    {
        g_sourceRef[entity] = INVALID_ENT_REFERENCE;
        g_outlineRef[entity] = INVALID_ENT_REFERENCE;
        g_proxySourceRef[entity] = INVALID_ENT_REFERENCE;
        g_cabinetRef[entity] = INVALID_ENT_REFERENCE;
        for (int client = 1; client <= MaxClients; client++)
            g_supplyOutlineRef[entity][client] = INVALID_ENT_REFERENCE;
    }
    InitSupplies();
    InitHittables();
    InitTankStall();
    InitBlackWhite();
    HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
    HookEvent("tank_spawn", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    HookEvent("player_spawn", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    HookEvent("player_death", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    HookEvent("player_team", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    HookEvent("bot_player_replace", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    HookEvent("player_bot_replace", OnPlayerStateChanged, EventHookMode_PostNoCopy);
    CreateTimer(0.2, UpdateGlows, _, TIMER_REPEAT);
}

public void OnMapStart()
{
    g_mapActive = true;
    g_roundEnded = false;
}

public void OnConfigsExecuted()
{
    RebuildSupplies();
    RefreshHittables();
    UpdateTankStall();
    UpdateBlackWhite();
}

void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ClearAllGlows();
    g_roundEnded = false;
    for (int entity = 0; entity < ENTITY_LIMIT; entity++)
        for (int team = 0; team < 4; team++) g_discovered[entity][team] = false;
    RebuildSupplies();
    RequestFrame(RefreshPlayerState);
}

void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_roundEnded = true;
    ClearAllGlows();
}

public void OnMapEnd()
{
    g_mapActive = false;
    ClearAllGlows();
}

public void OnPluginEnd()
{
    ClearAllGlows();
}

void ClearAllGlows()
{
    ClearSupplies();
    ClearHittables();
    ClearTankStall();
    ClearBlackWhite();
}

void OnPlayerStateChanged(Event event, const char[] name, bool dontBroadcast)
{
    // Team changes fire before the new team is installed.
    RequestFrame(RefreshPlayerState);
}

public void OnClientDisconnect(int client)
{
    ReleaseSource(client);
    // Destroy anything this connection saw before its slot can be reused.
    for (int entity = 1; entity < ENTITY_LIMIT; entity++)
    {
        if (g_sourceKind[entity] == Glow_Supply) RemoveSupplyOutline(entity, client);
        if (g_outlineSent[entity][client]) DestroyOutline(entity);
        g_outlineViewers[entity][client] = false;
    }
    RequestFrame(RefreshPlayerState);
}

void RefreshPlayerState(any data)
{
    UpdateGlows(null);
}

Action UpdateGlows(Handle timer)
{
    if (!g_mapActive || g_roundEnded) return Plugin_Continue;
    UpdateSupplies();
    RefreshHittables();
    UpdateHittables();
    UpdateTankStall();
    UpdateBlackWhite();
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || entity >= ENTITY_LIMIT) return;
    g_sourceRef[entity] = INVALID_ENT_REFERENCE;
    g_outlineRef[entity] = INVALID_ENT_REFERENCE;
    g_proxySourceRef[entity] = INVALID_ENT_REFERENCE;
    g_proxyViewerSerial[entity] = 0;
    g_cabinetRef[entity] = INVALID_ENT_REFERENCE;
    for (int client = 1; client <= MaxClients; client++)
        g_supplyOutlineRef[entity][client] = INVALID_ENT_REFERENCE;
    for (int team = 0; team < 4; team++) g_discovered[entity][team] = false;
    if (StrEqual(classname, "weapon_pain_pills") || StrEqual(classname, "weapon_pain_pills_spawn")
        || StrEqual(classname, "weapon_first_aid_kit") || StrEqual(classname, "weapon_first_aid_kit_spawn")
        || StrEqual(classname, "weapon_defibrillator") || StrEqual(classname, "weapon_defibrillator_spawn")
        || StrEqual(classname, "weapon_ammo_spawn") || StrEqual(classname, "weapon_spawn")
        || StrContains(classname, "prop_") == 0)
        SDKHook(entity, SDKHook_SpawnPost, OnWorldEntitySpawned);
}

void OnWorldEntitySpawned(int entity)
{
    // Spawners finish assigning models, weapon IDs and Tank-glow flags later.
    RequestFrame(TrackSpawnedEntity, EntIndexToEntRef(entity));
}

void TrackSpawnedEntity(int reference)
{
    int entity = EntRefToEntIndex(reference);
    if (!g_mapActive || g_roundEnded || entity <= MaxClients) return;
    // Our prop_dynamic_override proxies are never supply/hittable sources.
    if (g_proxySourceRef[entity] != INVALID_ENT_REFERENCE) return;
    AddSupply(entity);
    AddHittable(entity);
}

public void OnEntityDestroyed(int entity)
{
    if (entity < 1 || entity >= ENTITY_LIMIT) return;
    int source = EntRefToEntIndex(g_proxySourceRef[entity]);
    if (source > 0)
    {
        // External proxy deletion does not discard discovery or an episode.
        if (g_sourceKind[source] == Glow_Supply)
        {
            int client = GetClientFromSerial(g_proxyViewerSerial[entity]);
            if (client) g_supplyOutlineRef[source][client] = INVALID_ENT_REFERENCE;
        }
        else
        {
            g_outlineRef[source] = INVALID_ENT_REFERENCE;
            ResetOutlineAudience(source);
        }
    }
    g_proxySourceRef[entity] = INVALID_ENT_REFERENCE;
    g_proxyViewerSerial[entity] = 0;
    ReleaseSource(entity);
    g_cabinetRef[entity] = INVALID_ENT_REFERENCE;
    for (int team = 0; team < 4; team++) g_discovered[entity][team] = false;
}
