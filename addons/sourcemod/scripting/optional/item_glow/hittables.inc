ConVar g_hittableEnable;
ConVar g_hittableRange, g_hittableIntroDuration;
float g_hittableIntroUntil;
int g_hittableTraceClient;
ArrayList g_hittables;
bool g_hittablesActive;

void InitHittables()
{
    g_hittables = new ArrayList();
    g_hittableEnable = CreateConVar("hittable_glow_enable", "0", "Show orange hittable outlines to living survivors while any Tank is alive.", _, true, 0.0, true, 1.0);
    g_hittableEnable.AddChangeHook(OnHittableSettingsChanged);
    g_hittableRange = CreateConVar("hittable_glow_range", "600", "Nearby hittable outline distance after the Tank introduction (Source units).", _, true, 1.0);
    g_hittableIntroDuration = CreateConVar("hittable_glow_intro_duration", "8", "Seconds to highlight visible hittables without a distance cap when Tank combat begins.", _, true, 0.0);
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
    g_hittableIntroUntil = GetGameTime() + g_hittableIntroDuration.FloatValue;
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
    bool introduction = GetGameTime() < g_hittableIntroUntil;
    for (int i = g_hittables.Length - 1; i >= 0; i--)
    {
        int prop = EntRefToEntIndex(g_hittables.Get(i));
        if (prop <= MaxClients) { g_hittables.Erase(i); continue; }
        bool viewers[MAXPLAYERS + 1];
        float center[3], mins[3], maxs[3];
        GetEntPropVector(prop, Prop_Data, "m_vecAbsOrigin", center);
        GetEntPropVector(prop, Prop_Send, "m_vecMins", mins);
        GetEntPropVector(prop, Prop_Send, "m_vecMaxs", maxs);
        center[2] += (mins[2] + maxs[2]) * 0.5;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (!IsLivingGlowViewer(client)) continue;
            float eye[3];
            GetClientEyePosition(client, eye);
            if (!introduction && GetVectorDistance(eye, center) > g_hittableRange.FloatValue) continue;
            viewers[client] = CanSeeHittable(client, prop, eye, center);
        }
        UpdateOutline(prop, 255 | (128 << 8), viewers);
    }
}

bool CanSeeHittable(int client, int prop, const float eye[3], const float center[3])
{
    float angles[3], facing[3], direction[3];
    GetClientEyeAngles(client, angles);
    GetAngleVectors(angles, facing, NULL_VECTOR, NULL_VECTOR);
    MakeVectorFromPoints(eye, center, direction);
    NormalizeVector(direction, direction);
    int fov = GetEntProp(client, Prop_Send, "m_iFOV");
    if (!fov) fov = GetEntProp(client, Prop_Send, "m_iDefaultFOV");
    if (GetVectorDotProduct(facing, direction) < Cosine(DegToRad(float(fov) * 0.5))) return false;
    g_hittableTraceClient = client;
    Handle trace = TR_TraceRayFilterEx(eye, center, MASK_VISIBLE, RayType_EndPoint, TraceHittableVisibility);
    bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == prop;
    delete trace;
    return visible;
}

bool TraceHittableVisibility(int entity, int contentsMask)
{
    if (entity == g_hittableTraceClient) return false;
    return entity <= MaxClients || entity >= ENTITY_LIMIT || g_proxySourceRef[entity] == INVALID_ENT_REFERENCE;
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
