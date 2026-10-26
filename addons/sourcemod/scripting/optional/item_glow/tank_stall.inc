ConVar g_tankStallEnable, g_tankStallDuration;
int g_displayEpisode[MAXPLAYERS + 1];
float g_displayStarted[MAXPLAYERS + 1], g_displayUntil[MAXPLAYERS + 1];

void InitTankStall()
{
    g_tankStallEnable = CreateConVar("tank_stuck_glow_enable", "0", "Show a red Tank outline once at the start of each si_unstuck stall episode.", _, true, 0.0, true, 1.0);
    g_tankStallDuration = CreateConVar("tank_stuck_glow_duration", "3.0", "Seconds from the first stall notification, captured once per episode; retries never restart it.", _, true, 0.0);
    g_tankStallEnable.AddChangeHook(OnTankStallSettingsChanged);
    g_tankStallDuration.AddChangeHook(OnTankStallSettingsChanged);
}

void OnTankStallSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateTankStall();
}

void ClearTankStall()
{
    for (int client = 1; client <= MaxClients; client++)
        if (g_sourceKind[client] == Glow_StalledTank) ReleaseSource(client);
}

void UpdateTankStall()
{
    if (!g_mapActive || g_roundEnded || !g_tankStallEnable.BoolValue
        || GetFeatureStatus(FeatureType_Native, "SIUnstuck_GetTankStall") != FeatureStatus_Available)
    {
        ClearTankStall();
        return;
    }
    bool viewers[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++) viewers[client] = IsLivingGlowViewer(client);
    for (int tank = 1; tank <= MaxClients; tank++)
    {
        int episode;
        float startedAt;
        // Use the provider's original timestamp, not our load/enable time.
        // No local timer or diagnostic stream can restart a retry episode.
        if (!IsLivingTank(tank) || !SIUnstuck_GetTankStall(tank, episode, startedAt))
        {
            if (g_sourceKind[tank] == Glow_StalledTank) ReleaseSource(tank);
            g_displayEpisode[tank] = 0;
            continue;
        }
        if (g_displayEpisode[tank] != episode || g_displayStarted[tank] != startedAt)
        {
            g_displayEpisode[tank] = episode;
            g_displayStarted[tank] = startedAt;
            g_displayUntil[tank] = startedAt + g_tankStallDuration.FloatValue;
        }
        if (GetGameTime() >= g_displayUntil[tank])
        {
            if (g_sourceKind[tank] == Glow_StalledTank) ReleaseSource(tank);
            continue;
        }
        TrackSource(tank, Glow_StalledTank);
        UpdateOutline(tank, 255, viewers);
    }
}

public void SIUnstuck_OnTankStallChanged(int client, bool stalled, int episode, float startedAt)
{
    if (!stalled)
    {
        if (client > 0 && client <= MaxClients && g_sourceKind[client] == Glow_StalledTank)
            ReleaseSource(client);
        return;
    }
    UpdateTankStall();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "si_unstuck")) UpdateTankStall();
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "si_unstuck")) ClearTankStall();
}
