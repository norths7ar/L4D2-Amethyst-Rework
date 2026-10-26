// Shared ownership only: each module decides whether and to whom a source glows.
int g_sourceRef[ENTITY_LIMIT];
GlowKind g_sourceKind[ENTITY_LIMIT];
int g_outlineRef[ENTITY_LIMIT];
int g_supplyOutlineRef[ENTITY_LIMIT][MAXPLAYERS + 1];
int g_proxySourceRef[ENTITY_LIMIT];
int g_proxyViewerSerial[ENTITY_LIMIT];
bool g_outlineViewers[ENTITY_LIMIT][MAXPLAYERS + 1];
bool g_outlineSent[ENTITY_LIMIT][MAXPLAYERS + 1];
bool g_outlineRecreate[ENTITY_LIMIT];

void TrackSource(int entity, GlowKind kind)
{
    // A player slot can switch between survivor and Tank. Rebuild its display
    // rather than reusing the previous role's model and audience.
    if (g_sourceKind[entity] != Glow_None && g_sourceKind[entity] != kind)
        ReleaseSource(entity);
    g_sourceRef[entity] = EntIndexToEntRef(entity);
    g_sourceKind[entity] = kind;
}

void ResetOutlineAudience(int source)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        g_outlineViewers[source][client] = false;
        g_outlineSent[source][client] = false;
    }
}

void DestroyOutline(int source)
{
    int glow = EntRefToEntIndex(g_outlineRef[source]);
    g_outlineRef[source] = INVALID_ENT_REFERENCE;
    g_outlineRecreate[source] = false;
    ResetOutlineAudience(source);
    // Merely returning Handled from SetTransmit leaves an already-lit outline
    // on the client. Destroy/recreate, as in l4d2_tank_props_glow 3.0.
    if (glow > MaxClients)
    {
        g_proxySourceRef[glow] = INVALID_ENT_REFERENCE;
        g_proxyViewerSerial[glow] = 0;
        RemoveEntity(glow);
    }
}

void RemoveSupplyOutline(int source, int client)
{
    int glow = EntRefToEntIndex(g_supplyOutlineRef[source][client]);
    g_supplyOutlineRef[source][client] = INVALID_ENT_REFERENCE;
    // A supply proxy belongs to exactly one connection. Removing it must not
    // recreate another player's still-in-range outline.
    if (glow > MaxClients)
    {
        g_proxySourceRef[glow] = INVALID_ENT_REFERENCE;
        g_proxyViewerSerial[glow] = 0;
        RemoveEntity(glow);
    }
}

void ReleaseSource(int source)
{
    if (g_sourceKind[source] == Glow_Supply)
        for (int client = 1; client <= MaxClients; client++) RemoveSupplyOutline(source, client);
    DestroyOutline(source);
    g_sourceRef[source] = INVALID_ENT_REFERENCE;
    g_sourceKind[source] = Glow_None;
}

void UpdateOutline(int source, int color, const bool viewers[MAXPLAYERS + 1])
{
    bool anyViewer;
    bool recreate;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (viewers[client]) anyViewer = true;
        else if (g_outlineSent[source][client]) recreate = true;
    }
    if (!anyViewer)
    {
        DestroyOutline(source);
        return;
    }
    if (recreate) DestroyOutline(source);
    for (int client = 1; client <= MaxClients; client++)
        g_outlineViewers[source][client] = viewers[client];
    int glow = EntRefToEntIndex(g_outlineRef[source]);
    if (glow <= MaxClients) CreateOutline(source, color);
    else
    {
        SetEntProp(glow, Prop_Send, "m_glowColorOverride", color);
        SyncOutlineAppearance(source, glow);
    }
}

void SyncOutlineAppearance(int source, int glow)
{
    // Bodygroups affect the silhouette (e.g. broken car parts), not just color.
    // Copy onto the display only, also following later source appearance changes.
    if (HasEntProp(source, Prop_Send, "m_nSkin"))
        SetEntProp(glow, Prop_Send, "m_nSkin", GetEntProp(source, Prop_Send, "m_nSkin"));
    if (HasEntProp(source, Prop_Send, "m_nBody"))
        SetEntProp(glow, Prop_Send, "m_nBody", GetEntProp(source, Prop_Send, "m_nBody"));
}

void CreateOutline(int source, int color, int viewer = 0)
{
    char model[PLATFORM_MAX_PATH];
    GetEntPropString(source, Prop_Data, "m_ModelName", model, sizeof(model));
    if (!model[0]) return;
    int glow = CreateEntityByName("prop_dynamic_override");
    if (glow == -1) return;
    if (glow >= ENTITY_LIMIT) { RemoveEntity(glow); return; }
    SetEntityModel(glow, model);
    DispatchSpawn(glow);
    SyncOutlineAppearance(source, glow);
    SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
    SetEntProp(glow, Prop_Send, "m_nGlowRange", 0);
    SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
    SetEntProp(glow, Prop_Send, "m_glowColorOverride", color);
    SetEntityRenderMode(glow, RENDER_NONE);
    SetEntityRenderColor(glow, 0, 0, 0, 0);
    float origin[3], angles[3];
    GetEntPropVector(source, Prop_Data, "m_vecAbsOrigin", origin);
    GetEntPropVector(source, Prop_Data, "m_angAbsRotation", angles);
    TeleportEntity(glow, origin, angles, NULL_VECTOR);
    SetVariantString("!activator");
    AcceptEntityInput(glow, "SetParent", source);
    if (source <= MaxClients)
    {
        // The player's skeleton drives its same-model outline. Reference:
        // attachments_api SetAttached; omit FASTCULL for the visible attachment.
        // BONEMERGE | NOSHADOW | PARENT_ANIMATES, only on our display entity.
        SetEntityMoveType(glow, MOVETYPE_NONE);
        SetEntProp(glow, Prop_Send, "m_fEffects", 1 | 16 | 512);
        float zero[3];
        TeleportEntity(glow, zero, zero, NULL_VECTOR);
    }
    AcceptEntityInput(glow, "StartGlowing");
    if (viewer)
    {
        g_supplyOutlineRef[source][viewer] = EntIndexToEntRef(glow);
        g_proxyViewerSerial[glow] = GetClientSerial(viewer);
    }
    else g_outlineRef[source] = EntIndexToEntRef(glow);
    g_proxySourceRef[glow] = g_sourceRef[source];
    SDKHook(glow, SDKHook_SetTransmit, OnOutlineTransmit);
}

bool IsLivingGlowViewer(int client)
{
    return IsClientInGame(client) && !IsFakeClient(client)
        && GetClientTeam(client) == 2 && IsPlayerAlive(client);
}

Action OnOutlineTransmit(int glow, int client)
{
    int source = EntRefToEntIndex(g_proxySourceRef[glow]);
    if (source <= 0) return Plugin_Handled;
    // Preserve item_glow 1.2.1's personal proxy policy, including slot reuse.
    // Supply updates/events destroy only this connection's proxy on loss of
    // eligibility/range; shared recreation below is for hittables/Tanks only.
    if (g_sourceKind[source] == Glow_Supply)
        return GetClientFromSerial(g_proxyViewerSerial[glow]) == client ? Plugin_Continue : Plugin_Handled;
    bool allowed = g_outlineViewers[source][client];
    allowed = allowed && IsLivingGlowViewer(client);
    if (allowed)
    {
        g_outlineSent[source][client] = true;
        return Plugin_Continue;
    }
    if (g_outlineSent[source][client] && !g_outlineRecreate[source])
    {
        g_outlineRecreate[source] = true;
        RequestFrame(RecreateOutline, g_sourceRef[source]);
    }
    return Plugin_Handled;
}

void RecreateOutline(int reference)
{
    int source = EntRefToEntIndex(reference);
    if (source <= 0 || g_sourceRef[source] != reference || !g_outlineRecreate[source]) return;
    DestroyOutline(source);
    // Re-evaluate the module policy rather than replaying an obsolete audience.
    UpdateGlows(null);
}
