#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name = "Dynamic Server Name",
    author = "AstRedux contributors",
    description = "Displays mode, SI wave settings and open survivor slots.",
    version = "1.0.0",
    url = ""
};

ConVar g_hostname;
ConVar g_watched[4];
char g_baseName[256];
bool g_writing;
bool g_pending;

public void OnPluginStart()
{
    g_hostname = FindConVar("hostname");
    g_hostname.GetString(g_baseName, sizeof(g_baseName));
    g_hostname.AddChangeHook(HostnameChanged);
    HookEvent("player_team", PlayersChanged);
    HookEvent("player_bot_replace", PlayersChanged);
    HookEvent("bot_player_replace", PlayersChanged);
    RefreshHooks();
    QueueUpdate();
}

void RefreshHooks()
{
    static const char names[][] = {"l4d_ready_cfg_name", "wave_interval", "wave_size", "survivor_limit"};
    for (int i = 0; i < sizeof(names); i++)
    {
        if (g_watched[i] == null)
        {
            g_watched[i] = FindConVar(names[i]);
            if (g_watched[i] != null)
                g_watched[i].AddChangeHook(SettingsChanged);
        }
    }
}

public void OnAllPluginsLoaded() { RefreshHooks(); QueueUpdate(); }
public void OnConfigsExecuted() { RefreshHooks(); QueueUpdate(); }
public void OnLibraryAdded(const char[] name) { RefreshHooks(); QueueUpdate(); }
public void OnLibraryRemoved(const char[] name) { QueueUpdate(); }
public void OnClientPutInServer(int client) { QueueUpdate(); }
public void OnClientDisconnect_Post(int client) { QueueUpdate(); }
public void PlayersChanged(Event event, const char[] name, bool dontBroadcast) { QueueUpdate(); }
public void SettingsChanged(ConVar cvar, const char[] oldValue, const char[] newValue) { QueueUpdate(); }

public void HostnameChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    if (g_writing) return;
    strcopy(g_baseName, sizeof(g_baseName), newValue);
    QueueUpdate();
}

void QueueUpdate()
{
    if (g_pending) return;
    g_pending = true;
    RequestFrame(UpdateName);
}

public void UpdateName(any data)
{
    g_pending = false;
    char name[256], mode[128], wave[48];
    // ConVars survive plugin unloading; only use wave values while their owner is loaded.
    if (LibraryExists("wave_spawner"))
    {
        if (g_watched[0] != null) g_watched[0].GetString(mode, sizeof(mode));
        if (g_watched[1] != null && g_watched[2] != null)
        {
            char interval[24];
            g_watched[1].GetString(interval, sizeof(interval));
            if (StrContains(interval, ".") != -1)
            {
                int end = strlen(interval) - 1;
                while (end > 0 && interval[end] == '0') interval[end--] = '\0';
                if (interval[end] == '.') interval[end] = '\0';
            }
            FormatEx(wave, sizeof(wave), "[%s秒%d特]", interval, g_watched[2].IntValue);
        }
    }
    else if (LibraryExists("readyup") && g_watched[0] != null)
        g_watched[0].GetString(mode, sizeof(mode));

    int survivors;
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 2)
            survivors++;

    FormatEx(name, sizeof(name), "%s%s", g_baseName, wave);
    if (mode[0] != '\0') Format(name, sizeof(name), "%s[%s]", name, mode);
    if (g_watched[3] != null && survivors < g_watched[3].IntValue)
        StrCat(name, sizeof(name), "[缺人]");
    g_writing = true;
    g_hostname.SetString(name);
    g_writing = false;
}

public void OnPluginEnd()
{
    g_writing = true;
    g_hostname.SetString(g_baseName);
}
