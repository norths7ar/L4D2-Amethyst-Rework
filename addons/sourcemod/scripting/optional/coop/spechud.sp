#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <colors>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>
#undef REQUIRE_PLUGIN
#include <readyup>
#include <pause>

#define HUD_INTERVAL 1.0

ConVar g_hostname, g_maxPlayers, g_tankBurnDuration;
char g_hostnameName[64];
int g_maxPlayersValue;
float g_tankBurnDurationValue;
bool g_specHud[MAXPLAYERS + 1], g_tankHud[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Spectator HUD",
    author = "Visor, Forgetest, AstRedux maintainers",
    description = "PVE subtraction of Hyper-V 3.9.1 spectator HUD.",
    version = "1.0.1"
};

public void OnPluginStart()
{
    LoadTranslations("spechud_pve.phrases");
    g_hostname = FindConVar("hostname");
    g_maxPlayers = FindConVar("sv_maxplayers");
    g_tankBurnDuration = FindConVar("tank_burn_duration");
    RefreshCvars();
    g_hostname.AddChangeHook(ChangedCvar);
    if (g_maxPlayers != null) g_maxPlayers.AddChangeHook(ChangedCvar);
    g_tankBurnDuration.AddChangeHook(ChangedCvar);
    RegConsoleCmd("sm_spechud", CommandToggleSpecHud);
    RegConsoleCmd("sm_tankhud", CommandToggleTankHud);
    CreateTimer(HUD_INTERVAL, TimerDrawHud, _, TIMER_REPEAT);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
}
public void OnClientPutInServer(int client) { g_specHud[client] = false; g_tankHud[client] = true; }
public void OnClientDisconnect(int client) { g_specHud[client] = false; g_tankHud[client] = true; }
public void ChangedCvar(ConVar convar, const char[] oldValue, const char[] newValue) { RefreshCvars(); }
void RefreshCvars()
{
    g_hostname.GetString(g_hostnameName, sizeof(g_hostnameName));
    g_maxPlayersValue = g_maxPlayers != null ? g_maxPlayers.IntValue : MaxClients;
    if (g_maxPlayersValue <= 0) g_maxPlayersValue = MaxClients;
    g_tankBurnDurationValue = g_tankBurnDuration.FloatValue;
}

public Action CommandToggleSpecHud(int client, int args)
{
    if (!IsSpectator(client)) return Plugin_Handled;
    g_specHud[client] = !g_specHud[client];
    CPrintToChat(client, "%t", g_specHud[client] ? "SpecHudEnabled" : "SpecHudDisabled");
    return Plugin_Handled;
}
public Action CommandToggleTankHud(int client, int args)
{
    if (!IsSpectator(client)) return Plugin_Handled;
    g_tankHud[client] = !g_tankHud[client];
    CPrintToChat(client, "%t", g_tankHud[client] ? "TankHudEnabled" : "TankHudDisabled");
    return Plugin_Handled;
}

public Action TimerDrawHud(Handle timer)
{
    if (IsReadyOrPaused()) return Plugin_Continue;
    int tank = FindTankClient(-1);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsSpectator(client) || GetClientMenu(client) != MenuSource_None) continue;
        Panel panel = null;
        if (g_specHud[client])
        {
            panel = new Panel();
            FillHeaderInfo(panel);
            FillSurvivorInfo(panel);
            if (tank > 0 && IsPlayerAlive(tank)) FillTankInfo(panel, tank, false);
        }
        else if (g_tankHud[client] && tank > 0 && IsPlayerAlive(tank))
        {
            panel = new Panel();
            FillTankInfo(panel, tank, true);
        }
        if (panel != null) { panel.Send(client, IgnorePanel, 2); delete panel; }
    }
    return Plugin_Continue;
}
int IgnorePanel(Menu menu, MenuAction action, int param1, int param2) { return 0; }
bool IsReadyOrPaused()
{
    if (GetFeatureStatus(FeatureType_Native, "IsInReady") == FeatureStatus_Available && IsInReady()) return true;
    return GetFeatureStatus(FeatureType_Native, "IsInPause") == FeatureStatus_Available && IsInPause();
}
bool IsSpectator(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == L4D2Team_Spectator;
}

// Directly reduced from Hyper-V 3.9.1's header/survivor path. Versus scores,
// infected roster and player-transfer data are deliberately not present.
void FillHeaderInfo(Panel panel)
{
    static int tickrate;
    if (!tickrate && IsServerProcessing()) tickrate = RoundToNearest(1.0 / GetTickInterval());
    char line[96];
    FormatEx(line, sizeof(line), "%s [%d/%d | %dT]", g_hostnameName, GetRealClientCount(), g_maxPlayersValue, tickrate);
    DrawPanelText(panel, line);
}
void GetMeleePrefix(int client, char[] prefix, int length)
{
    int secondary = GetPlayerWeaponSlot(client, L4D2WeaponSlot_Secondary);
    if (secondary == -1) return;
    switch (IdentifyWeapon(secondary))
    {
        case WEPID_NONE: strcopy(prefix, length, "N");
        case WEPID_PISTOL: strcopy(prefix, length, GetEntProp(secondary, Prop_Send, "m_isDualWielding") ? "DP" : "P");
        case WEPID_PISTOL_MAGNUM: strcopy(prefix, length, "DE");
        case WEPID_MELEE: strcopy(prefix, length, "M");
        default: strcopy(prefix, length, "?");
    }
}
void GetWeaponInfo(int client, char[] info, int length)
{
    char buffer[32];
    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int primary = GetPlayerWeaponSlot(client, L4D2WeaponSlot_Primary);
    int activeId = IdentifyWeapon(active), primaryId = IdentifyWeapon(primary);
    if (activeId == WEPID_PISTOL || activeId == WEPID_PISTOL_MAGNUM)
    {
        if (activeId == WEPID_PISTOL && GetEntProp(active, Prop_Send, "m_isDualWielding")) strcopy(buffer, sizeof(buffer), "DP");
        else GetLongWeaponName(activeId, buffer, sizeof(buffer));
        FormatEx(info, length, "%s %d", buffer, GetWeaponClipAmmo(active));
    }
    else { GetLongWeaponName(primaryId, buffer, sizeof(buffer)); FormatEx(info, length, "%s %d/%d", buffer, GetWeaponClipAmmo(primary), GetWeaponExtraAmmo(client, primaryId)); }
    if (primary == -1 && (activeId == WEPID_MELEE || activeId == WEPID_CHAINSAW)) GetLongMeleeWeaponName(IdentifyMeleeWeapon(active), info, length);
    else if (primary != -1)
    {
        if (GetSlotFromWeaponId(activeId) != L4D2WeaponSlot_Secondary || activeId == WEPID_MELEE || activeId == WEPID_CHAINSAW)
        { GetMeleePrefix(client, buffer, sizeof(buffer)); Format(info, length, "%s | %s", info, buffer); }
        else { GetLongWeaponName(primaryId, buffer, sizeof(buffer)); Format(info, length, "%s | %s %d", info, buffer, GetWeaponClipAmmo(primary) + GetWeaponExtraAmmo(client, primaryId)); }
    }
}
int SortSurvivors(int first, int second, const int[] array, Handle hndl) { return IdentifySurvivor(first) - IdentifySurvivor(second); }
void FillSurvivorInfo(Panel panel)
{
    char line[128], name[MAX_NAME_LENGTH], latency[8];
    DrawPanelText(panel, " "); DrawPanelText(panel, "-> 生还者");
    int clients[MAXPLAYERS], total;
    for (int client = 1; client <= MaxClients; client++) if (IsClientInGame(client) && GetClientTeam(client) == L4D2Team_Survivor) clients[total++] = client;
    SortCustom1D(clients, total, SortSurvivors);
    for (int index = 0; index < total; index++)
    {
        int client = clients[index]; GetClientFixedName(client, name, sizeof(name));
        if (IsFakeClient(client)) strcopy(latency, sizeof(latency), "BOT"); else FormatEx(latency, sizeof(latency), "%dms", RoundToNearest(GetClientAvgLatency(client, NetFlow_Both) * 1000.0));
        if (!IsPlayerAlive(client)) FormatEx(line, sizeof(line), "%s | %s: Dead", latency, name);
        else if (IsHangingFromLedge(client)) FormatEx(line, sizeof(line), "%s | %s: <%dHP@Hang>", latency, name, GetClientHealth(client));
        else if (IsIncapacitated(client))
        {
            int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"); GetLongWeaponName(IdentifyWeapon(active), line, sizeof(line));
            Format(line, sizeof(line), "%s | %s: <%dHP@%s> [%s %d]", latency, name, GetClientHealth(client), GetSurvivorIncapCount(client) == 1 ? "2nd" : "1st", line, GetWeaponClipAmmo(active));
        }
        else
        {
            GetWeaponInfo(client, line, sizeof(line)); int temporary = GetSurvivorTemporaryHealth(client); int health = GetClientHealth(client) + temporary; int incap = GetSurvivorIncapCount(client);
            if (!incap) Format(line, sizeof(line), "%s | %s: %dHP%s [%s]", latency, name, health, temporary > 0 ? "#" : "", line);
            else Format(line, sizeof(line), "%s | %s: %dHP (#%s) [%s]", latency, name, health, incap == 2 ? "2nd" : "1st", line);
        }
        DrawPanelText(panel, line);
    }
}
// Hyper-V FillTankInfo reduced to PVE health/fire state; no controller, pass,
// frustration, network or any other player-infected transfer information.
void FillTankInfo(Panel panel, int tank, bool tankOnly)
{
    char line[96];
    if (tankOnly) DrawPanelText(panel, "Tank HUD"); else { DrawPanelText(panel, " "); DrawPanelText(panel, "-> Tank"); }
    int health = GetClientHealth(tank), maximum = GetEntProp(tank, Prop_Send, "m_iMaxHealth");
    if (health <= 0 || IsIncapacitated(tank)) strcopy(line, sizeof(line), "HP: Dead");
    else FormatEx(line, sizeof(line), "HP: %d / %d%%", health, L4D2Util_GetMax(1, RoundFloat(L4D2Util_IntToPercentFloat(health, maximum))));
    DrawPanelText(panel, line);
    if (GetEntityFlags(tank) & FL_ONFIRE)
    {
        int remaining = RoundToCeil(L4D2Util_IntToPercentFloat(health, maximum) / 100.0 * g_tankBurnDurationValue);
        FormatEx(line, sizeof(line), "Fire: %ds", remaining); DrawPanelText(panel, line);
    }
}

// Hyper-V 3.9.1 helper stocks retained by the survivor information path.
#define ASSAULT_RIFLE_OFFSET_IAMMO 12
#define SMG_OFFSET_IAMMO 20
#define PUMPSHOTGUN_OFFSET_IAMMO 28
#define AUTO_SHOTGUN_OFFSET_IAMMO 32
#define HUNTING_RIFLE_OFFSET_IAMMO 36
#define MILITARY_SNIPER_OFFSET_IAMMO 40
#define GRENADE_LAUNCHER_OFFSET_IAMMO 68
stock int GetWeaponExtraAmmo(int client, int wepid)
{
    static int ammoOffset;
    if (!ammoOffset) ammoOffset = FindSendPropInfo("CCSPlayer", "m_iAmmo");
    int offset;
    switch (wepid)
    {
        case WEPID_RIFLE, WEPID_RIFLE_AK47, WEPID_RIFLE_DESERT, WEPID_RIFLE_SG552: offset = ASSAULT_RIFLE_OFFSET_IAMMO;
        case WEPID_SMG, WEPID_SMG_SILENCED: offset = SMG_OFFSET_IAMMO;
        case WEPID_PUMPSHOTGUN, WEPID_SHOTGUN_CHROME: offset = PUMPSHOTGUN_OFFSET_IAMMO;
        case WEPID_AUTOSHOTGUN, WEPID_SHOTGUN_SPAS: offset = AUTO_SHOTGUN_OFFSET_IAMMO;
        case WEPID_HUNTING_RIFLE: offset = HUNTING_RIFLE_OFFSET_IAMMO;
        case WEPID_SNIPER_MILITARY, WEPID_SNIPER_AWP, WEPID_SNIPER_SCOUT: offset = MILITARY_SNIPER_OFFSET_IAMMO;
        case WEPID_GRENADE_LAUNCHER: offset = GRENADE_LAUNCHER_OFFSET_IAMMO;
        default: return -1;
    }
    return GetEntData(client, ammoOffset + offset);
}
stock int GetWeaponClipAmmo(int weapon) { return weapon > 0 ? GetEntProp(weapon, Prop_Send, "m_iClip1") : -1; }
stock void GetClientFixedName(int client, char[] name, int length)
{
    GetClientName(client, name, length);
    if (name[0] == '[') name[0] = ' ';
    if (strlen(name) > 12) { name[9] = name[10] = name[11] = '.'; name[12] = '\0'; }
}
stock int GetRealClientCount()
{
    int clients;
    for (int client = 1; client <= MaxClients; client++) if (IsClientConnected(client) && !IsFakeClient(client)) clients++;
    return clients;
}
