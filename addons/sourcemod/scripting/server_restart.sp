#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"

char g_Requester[96];
char g_Reason[192];

public Plugin myinfo =
{
    name = "L4D2 systemd restart",
    author = "L4D2-Amethyst-Rework",
    description = "Lets an authorized admin request a clean systemd-managed restart",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    RegAdminCmd("sm_restart", Command_Restart, ADMFLAG_RCON,
        "Restart the dedicated server through systemd");
    RegAdminCmd("sm_restartserver", Command_Restart, ADMFLAG_RCON,
        "Restart the dedicated server through systemd");
}

public Action Command_Restart(int client, int args)
{
    if (client > 0)
    {
        char steamId[32];
        GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true);
        FormatEx(g_Requester, sizeof(g_Requester), "%N <%s>", client, steamId);
    }
    else
    {
        strcopy(g_Requester, sizeof(g_Requester), "Console");
    }

    if (args > 0)
    {
        GetCmdArgString(g_Reason, sizeof(g_Reason));
        StripQuotes(g_Reason);
        TrimString(g_Reason);
    }
    else
    {
        strcopy(g_Reason, sizeof(g_Reason), "admin request");
    }

    LogAction(client, -1, "\"%s\" requested a systemd restart: %s", g_Requester, g_Reason);
    PrintToServer("[Server Restart] requester=%s reason=%s", g_Requester, g_Reason);
    PrintToChatAll("\x04[Server]\x01 %s requested a restart: %s", g_Requester, g_Reason);
    PrintToChatAll("\x04[Server]\x01 Restarting now.");
    LogMessage("Executing clean quit. Requester: %s; reason: %s", g_Requester, g_Reason);
    ServerCommand("quit");
    ServerExecute();
    return Plugin_Handled;
}
