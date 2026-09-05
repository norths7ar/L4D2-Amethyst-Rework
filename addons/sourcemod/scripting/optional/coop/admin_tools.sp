#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_INFECTED 3

public Plugin myinfo =
{
	name = "Coop admin tools",
	author = "海洋空氣, norths7ar",
	description = "Administrator-only emergency controls for Coop",
	version = "1.0.0"
};

public void OnPluginStart()
{
	LoadTranslations("admin_tools.phrases");
	RegAdminCmd("sm_fuck", CommandCleanup, ADMFLAG_BAN, "Remove matching AI special infected.");
}

public Action CommandCleanup(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "%t", "AdminCleanupSyntax");
		return Plugin_Handled;
	}
	char requested[64];
	GetCmdArg(1, requested, sizeof(requested));
	int count = CleanupAiSpecialInfected(requested);
	if (StrEqual(requested, "all", false))
	{
		if (client > 0) PrintToChatAll("%t", "AdminCleanupAll", client, count);
		else PrintToServer("%t", "AdminCleanupAllConsole", count);
	}
	else if (count > 0)
	{
		if (client > 0) PrintToChatAll("%t", "AdminCleanupSome", client, count, requested);
		else PrintToServer("%t", "AdminCleanupSomeConsole", count, requested);
	}
	else ReplyToCommand(client, "%t", "AdminCleanupNone", requested);
	return Plugin_Handled;
}

int CleanupAiSpecialInfected(const char[] query)
{
	int count;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target) || !IsFakeClient(target) || GetClientTeam(target) != TEAM_INFECTED) continue;
		if (!StrEqual(query, "all", false) && !MatchesInfectedName(target, query)) continue;
		ForcePlayerSuicide(target);
		count++;
	}
	return count;
}

bool MatchesInfectedName(int client, const char[] query)
{
	char name[64];
	GetClientName(client, name, sizeof(name));
	return StrContains(name, query, false) >= 0;
}
