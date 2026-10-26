ConVar g_hittableEnable;
ArrayList g_hittables;
bool g_hittablesActive;

void InitHittables()
{
    g_hittables = new ArrayList();
    g_hittableEnable = CreateConVar("hittable_glow_enable", "0", "Show orange hittable outlines to living survivors while any Tank is alive.", _, true, 0.0, true, 1.0);
    g_hittableEnable.AddChangeHook(OnHittableSettingsChanged);
}

void OnHittableSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshHittables();
    UpdateHittables();
}

bool IsLivingTank(int client)
{
    return IsClientInGame(client) && GetClientTeam(client) == 3 && IsPlayerAlive(client)
        && GetEntProp(client, Prop_Send, "m_zombieClass") == 8
        && !GetEntProp(client, Prop_Send, "m_isGhost");
}

void RefreshHittables()
{
    bool active;
    if (g_mapActive && !g_roundEnded && g_hittableEnable.BoolValue)
    {
        for (int client = 1; client <= MaxClients; client++)
            if (IsLivingTank(client)) { active = true; break; }
    }
    if (active == g_hittablesActive) return;
    ClearHittables();
    g_hittablesActive = active;
    if (!active) return;
    // Once at the first Tank (also late load/enable). New props use SpawnPost.
    for (int entity = MaxClients + 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
        if (IsValidEntity(entity)) AddHittable(entity);
}

void AddHittable(int entity)
{
    if (!g_hittablesActive || g_sourceRef[entity] == EntIndexToEntRef(entity)
        || !HasEntProp(entity, Prop_Send, "m_hasTankGlow")
        || !GetEntProp(entity, Prop_Send, "m_hasTankGlow", 1)) return;
    TrackSource(entity, Glow_Hittable);
    g_hittables.Push(g_sourceRef[entity]);
}

void UpdateHittables()
{
    if (!g_hittablesActive) return;
    bool viewers[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++) viewers[client] = IsLivingGlowViewer(client);
    for (int i = g_hittables.Length - 1; i >= 0; i--)
    {
        int prop = EntRefToEntIndex(g_hittables.Get(i));
        if (prop <= MaxClients) { g_hittables.Erase(i); continue; }
        UpdateOutline(prop, 255 | (128 << 8), viewers);
    }
}

void ClearHittables()
{
    g_hittablesActive = false;
    for (int i = 0; i < g_hittables.Length; i++)
    {
        int prop = EntRefToEntIndex(g_hittables.Get(i));
        if (prop > MaxClients) ReleaseSource(prop);
    }
    g_hittables.Clear();
}
