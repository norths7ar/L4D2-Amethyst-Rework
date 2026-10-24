#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <map_rules>
#include <map_rules_api>

#include "admin_tools/player_actions.inc"
#include "admin_tools/map_menu.inc"
#include "admin_tools/guns.inc"

#define TEAM_INFECTED 3

public Plugin myinfo =
{
	name = "Coop admin tools",
	author = "海洋空氣, norths7ar",
	description = "Administrator player operations and emergency controls for Coop",
	version = "1.5.2"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	MapRules_MarkAPIsOptional();
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("admin_tools.phrases");
	InitPlayerActions();
	MapRules_Init();
	InitBasicGuns();
	RegAdminCmd("sm_mset", CommandMapMenu, ADMFLAG_GENERIC, "本图路程 Boss、救援轮次和开场动画设置。");
	RegAdminCmd("sm_guns", CommandGuns, ADMFLAG_CHEATS, "准备阶段按配置在瞄准的地面生成 T1 武器各一把。");
	RegAdminCmd("sm_fuck", CommandCleanup, ADMFLAG_BAN, "清理匹配名称的 AI 特感。");
}

public void OnRoundIsLive() { MapRules_Lock(); }

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
