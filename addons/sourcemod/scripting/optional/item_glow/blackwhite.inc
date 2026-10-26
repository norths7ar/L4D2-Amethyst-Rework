ConVar g_blackWhiteEnable;

void InitBlackWhite()
{
    g_blackWhiteEnable = CreateConVar("survivor_blackwhite_glow_enable", "0",
        "Show white outlines of black-and-white survivors to living teammates.", _, true, 0.0, true, 1.0);
    g_blackWhiteEnable.AddChangeHook(OnBlackWhiteSettingsChanged);
}

void OnBlackWhiteSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    UpdateBlackWhite();
}

void ClearBlackWhite()
{
    for (int client = 1; client <= MaxClients; client++)
        if (g_sourceKind[client] == Glow_BlackWhiteSurvivor) ReleaseSource(client);
}

void UpdateBlackWhite()
{
    if (!g_mapActive || g_roundEnded || !g_blackWhiteEnable.BoolValue)
    {
        ClearBlackWhite();
        return;
    }
    bool viewers[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++) viewers[client] = IsLivingGlowViewer(client);
    // Reuse the existing update cadence: inspect only player slots, not world
    // entities. Pills do not clear third strike; healing/state changes do.
    for (int survivor = 1; survivor <= MaxClients; survivor++)
    {
        if (!IsClientInGame(survivor) || GetClientTeam(survivor) != 2 || !IsPlayerAlive(survivor)
            || !GetEntProp(survivor, Prop_Send, "m_bIsOnThirdStrike"))
        {
            if (g_sourceKind[survivor] == Glow_BlackWhiteSurvivor) ReleaseSource(survivor);
            continue;
        }
        TrackSource(survivor, Glow_BlackWhiteSurvivor);
        bool selfViewer = viewers[survivor];
        viewers[survivor] = false;
        UpdateOutline(survivor, 255 | (255 << 8) | (255 << 16), viewers);
        viewers[survivor] = selfViewer;
    }
}
