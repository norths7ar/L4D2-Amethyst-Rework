#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"

bool g_RestartPending;
int g_Countdown;
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
        "Restart the dedicated server after a 10 second warning");
    RegAdminCmd("sm_restartserver", Command_Restart, ADMFLAG_RCON,
        "Restart the dedicated server after a 10 second warning");
}

public Action Command_Restart(int client, int args)
{
    if (g_RestartPending)
    {
        ReplyToCommand(client, "[Server] A restart is already pending.");
        return Plugin_Handled;
    }

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

    g_RestartPending = true;
    g_Countdown = 10;
    LogAction(client, -1, "\"%s\" requested a systemd restart: %s", g_Requester, g_Reason);
    PrintToServer("[Server Restart] requester=%s reason=%s", g_Requester, g_Reason);
    PrintToChatAll("\x04[Server]\x01 %s requested a restart: %s", g_Requester, g_Reason);
    PrintToChatAll("\x04[Server]\x01 Restarting in 10 seconds.");
    CreateTimer(1.0, Timer_Restart, _, TIMER_REPEAT);
    return Plugin_Handled;
}

public Action Timer_Restart(Handle timer)
{
    g_Countdown--;
    if (g_Countdown <= 0)
    {
        PrintToServer("[Server Restart] executing clean quit for systemd restart");
        LogMessage("Restart countdown completed; executing quit. Requester: %s; reason: %s",
            g_Requester, g_Reason);
        ServerCommand("quit");
        ServerExecute();
        return Plugin_Stop;
    }

    if (g_Countdown <= 5)
    {
        PrintToChatAll("\x04[Server]\x01 Restarting in %d second%s.",
            g_Countdown, g_Countdown == 1 ? "" : "s");
    }
    return Plugin_Continue;
}
