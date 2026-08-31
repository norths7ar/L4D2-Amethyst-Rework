#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define ANNOUNCEMENT_LENGTH 512

public Plugin myinfo =
{
    name = "Ast Server Announcements",
    author = "norths7ar",
    description = "Displays configurable server information in player chat.",
    version = "1.0.0"
};

ArrayList g_Announcements;
ConVar g_Enabled;
ConVar g_File;
ConVar g_Interval;
ConVar g_Random;
Handle g_Timer;
int g_CurrentAnnouncement;
int g_LastRandomAnnouncement = -1;

public void OnPluginStart()
{
    g_Announcements = new ArrayList(ByteCountToCells(ANNOUNCEMENT_LENGTH));
    g_Enabled = CreateConVar("sm_server_announcements_enabled", "1", "Enable server chat announcements.");
    g_File = CreateConVar("sm_server_announcements_file", "server_announcements.txt", "Announcement file under addons/sourcemod/configs.");
    g_Interval = CreateConVar("sm_server_announcements_interval", "120", "Seconds between announcements.", _, true, 30.0);
    g_Random = CreateConVar("sm_server_announcements_random", "0", "Display announcements in random order.");

    g_File.AddChangeHook(OnSettingsChanged);
    g_Interval.AddChangeHook(OnSettingsChanged);
    RegAdminCmd("sm_announcements_reload", Command_Reload, ADMFLAG_CONFIG, "Reload server announcements.");

    // sharedplugins.cfg may load this plugin after the map's normal config pass.
    LoadAnnouncements();
    RestartTimer();
}

public void OnConfigsExecuted()
{
    LoadAnnouncements();
    RestartTimer();
}

public void OnSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    LoadAnnouncements();
    RestartTimer();
}

public Action Command_Reload(int client, int args)
{
    LoadAnnouncements();
    RestartTimer();
    ReplyToCommand(client, "[Ast] Server announcements reloaded: %d message(s).", g_Announcements.Length);
    return Plugin_Handled;
}

public Action Timer_Announce(Handle timer)
{
    if (!g_Enabled.BoolValue || g_Announcements.Length == 0)
    {
        return Plugin_Continue;
    }

    int index = g_CurrentAnnouncement;
    if (g_Random.BoolValue)
    {
        do
        {
            index = GetRandomInt(0, g_Announcements.Length - 1);
        }
        while (g_Announcements.Length > 1 && index == g_LastRandomAnnouncement);
        g_LastRandomAnnouncement = index;
    }
    else
    {
        g_CurrentAnnouncement = (g_CurrentAnnouncement + 1) % g_Announcements.Length;
    }

    char message[ANNOUNCEMENT_LENGTH];
    g_Announcements.GetString(index, message, sizeof(message));
    ReplaceString(message, sizeof(message), "{default}", "\x01", false);
    ReplaceString(message, sizeof(message), "{team}", "\x03", false);
    ReplaceString(message, sizeof(message), "{green}", "\x04", false);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
        {
            PrintToChat(client, "%s", message);
        }
    }
    return Plugin_Continue;
}

void LoadAnnouncements()
{
    g_Announcements.Clear();
    g_CurrentAnnouncement = 0;
    g_LastRandomAnnouncement = -1;

    char fileName[PLATFORM_MAX_PATH];
    char filePath[PLATFORM_MAX_PATH];
    g_File.GetString(fileName, sizeof(fileName));
    BuildPath(Path_SM, filePath, sizeof(filePath), "configs/%s", fileName);

    KeyValues config = new KeyValues("ServerAnnouncements");
    if (!config.ImportFromFile(filePath) || !config.GotoFirstSubKey())
    {
        LogError("Unable to read server announcements: %s", filePath);
        delete config;
        return;
    }

    char message[ANNOUNCEMENT_LENGTH];
    do
    {
        config.GetString("text", message, sizeof(message));
        TrimString(message);
        if (message[0] != '\0')
        {
            g_Announcements.PushString(message);
        }
    }
    while (config.GotoNextKey());

    delete config;
}

void RestartTimer()
{
    delete g_Timer;
    g_Timer = null;

    if (g_Interval.FloatValue >= 30.0)
    {
        g_Timer = CreateTimer(g_Interval.FloatValue, Timer_Announce, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}
