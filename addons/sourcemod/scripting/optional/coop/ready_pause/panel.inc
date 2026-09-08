// Panel presentation from Competitive Rework readyup/panel.inc, used by ZoneMod.
// Original readyup authors: CanadaRox, Target.
// The player-ready rendering is retained; only state access and command text
// are connected to ready_pause. Existing center-screen hints remain separate.

static const char readySymbol[2][] = {"☐", "☑"};
static const char g_readyPanelCommands[][] = {
	"->1. F1 准备 / F2 取消准备",
	"->2. !forcestart / !fs",
	"->3. !show / !hide",
	"->4. !join / !spec",
	"->5. !vote / !nextmap",
	"->6. !match / !rmatch",
	"->7. !pause / !unpause",
	"->8. !return",
	"->9. !ast"
};
static int g_readyPanelCommand;
static float g_readyPanelStarted;
float g_panelButtonTime[MAXPLAYERS + 1];
static ConVar g_readyPanelConfig, g_readyPanelServerCvar, g_readyPanelMaxPlayers;
Handle g_readyPanelCommandTimer;

void SetupReadyPanel()
{
	g_readyPanelConfig = CreateConVar("l4d_ready_cfg_name", "", "Configname to display on the ready-up panel", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY);
	g_readyPanelServerCvar = CreateConVar("l4d_ready_server_cvar", "sn_main_name", "ConVar to retrieve the server name for displaying on the ready-up panel", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY);
	g_readyPanelMaxPlayers = CreateConVar("l4d_ready_max_players", "12", "Maximum number of players to show on the ready-up panel.", FCVAR_NOTIFY, true, 0.0, true, MAXPLAYERS+1.0);
}

void InitReadyPanel()
{
	g_readyPanelStarted = GetGameTime();
	g_readyPanelCommand = 0;
	CancelTimer(g_readyPanelCommandTimer);
	g_readyPanelCommandTimer = CreateTimer(4.0, MenuCmd_Timer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

int ReadyPanelHandler(Handle menu, MenuAction action, int param1, int param2) { return 1; }

Action MenuCmd_Timer(Handle timer)
{
	if (g_readyPhase && g_readyEnabled.BoolValue)
	{
		g_readyPanelCommand = (g_readyPanelCommand + 1) % sizeof(g_readyPanelCommands);
		return Plugin_Continue;
	}
	g_readyPanelCommandTimer = null;
	return Plugin_Stop;
}

void UpdateReadyPanel()
{
	char survivorBuffer[400] = "";
	char infectedBuffer[400] = "";
	char casterBuffer[300] = "";
	char specBuffer[200] = "";
	int playerCount = 0;
	int casterCount = 0;
	int specCount = 0;

	Panel menuPanel = new Panel();

	char ServerBuffer[128];
	char ServerName[32];
	char cfgName[32];

	int iPassTime = RoundToFloor(GetGameTime() - g_readyPanelStarted);

	bool casterSystemAvailable = LibraryExists("caster_system");

	char serverCvar[64];
	g_readyPanelServerCvar.GetString(serverCvar, sizeof(serverCvar));
	ConVar serverNameCvar = FindConVar(serverCvar);
	if (serverNameCvar == null) serverNameCvar = FindConVar("hostname");
	serverNameCvar.GetString(ServerName, sizeof(ServerName));

	g_readyPanelConfig.GetString(cfgName, sizeof(cfgName));
	FormatEx(ServerBuffer, sizeof(ServerBuffer), "▸ Server: %s \n▸ Slots: %d/%d\n▸ Config: %s", ServerName, GetSeriousClientCount(), FindConVar("sv_maxplayers").IntValue, cfgName);
	menuPanel.DrawText(ServerBuffer);

	FormatTime(ServerBuffer, sizeof(ServerBuffer), "%m/%d/%Y - %I:%M%p");
	Format(ServerBuffer, sizeof(ServerBuffer), "▸ %s (%02d:%02d)", ServerBuffer, iPassTime / 60, iPassTime % 60);
	menuPanel.DrawText(ServerBuffer);

	menuPanel.DrawText(" ");
	menuPanel.DrawText("▸ Commands:");
	menuPanel.DrawText(g_readyPanelCommands[g_readyPanelCommand]);
	menuPanel.DrawText(" ");

	char nameBuf[64];

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			++playerCount;
			GetClientFixedName(client, nameBuf, sizeof(nameBuf));

			if (IsPlayer(client))
			{
				bool type = (GetClientTeam(client) == TEAM_SURVIVORS);
				int isReady = view_as<int>(g_playerReady[client]);

				Format(nameBuf, sizeof(nameBuf), "%s %s%s\n", readySymbol[isReady], nameBuf, IsPlayerAfk(client) ? " [AFK]" : "");
				type ? StrCat(survivorBuffer, sizeof(survivorBuffer), nameBuf) : StrCat(infectedBuffer, sizeof(infectedBuffer), nameBuf);
			}
			else
			{
				++specCount;
				if (casterSystemAvailable && IsClientCaster(client))
				{
					++casterCount;
					Format(nameBuf, sizeof(nameBuf), "%s\n", nameBuf);
					StrCat(casterBuffer, sizeof(casterBuffer), nameBuf);
				}
				else
				{
					if (playerCount <= g_readyPanelMaxPlayers.IntValue)
					{
						Format(nameBuf, sizeof(nameBuf), "%s\n", nameBuf);
						StrCat(specBuffer, sizeof(specBuffer), nameBuf);
					}
				}
			}
		}
	}

	int textCount = 0;
	int bufLen = strlen(survivorBuffer);
	if (bufLen != 0)
	{
		survivorBuffer[bufLen] = '\0';
		ReplaceString(survivorBuffer, sizeof(survivorBuffer), "#", "_");
		FormatEx(nameBuf, sizeof(nameBuf), "->%d. Survivors%s", ++textCount, "");
		menuPanel.DrawText(nameBuf);
		menuPanel.DrawText(survivorBuffer);
	}

	bufLen = strlen(infectedBuffer);
	if (bufLen != 0)
	{
		infectedBuffer[bufLen] = '\0';
		ReplaceString(infectedBuffer, sizeof(infectedBuffer), "#", "_");
		FormatEx(nameBuf, sizeof(nameBuf), "->%d. Infected%s", ++textCount, "");
		menuPanel.DrawText(nameBuf);
		menuPanel.DrawText(infectedBuffer);
	}

	if (specCount && textCount) menuPanel.DrawText(" ");

	if (casterSystemAvailable)
	{
		bufLen = strlen(casterBuffer);
		if (bufLen != 0)
		{
			casterBuffer[bufLen] = '\0';
			FormatEx(nameBuf, sizeof(nameBuf), "->%d. Caster%s", ++textCount, casterCount > 1 ? "s" : "");
			menuPanel.DrawText(nameBuf);
			ReplaceString(casterBuffer, sizeof(casterBuffer), "#", "_", true);
			menuPanel.DrawText(casterBuffer);
		}
	}

	bufLen = strlen(specBuffer);
	if (bufLen != 0)
	{
		specBuffer[bufLen] = '\0';
		FormatEx(nameBuf, sizeof(nameBuf), "->%d. Spectator%s", ++textCount, specCount > 1 ? "s" : "");
		menuPanel.DrawText(nameBuf);
		ReplaceString(specBuffer, sizeof(specBuffer), "#", "_");
		if (playerCount > g_readyPanelMaxPlayers.IntValue && specCount - casterCount > 1)
			FormatEx(specBuffer, sizeof(specBuffer), "**Many** (%d)", specCount - casterCount);
		menuPanel.DrawText(specBuffer);
	}

	if (g_footer.Length)
	{
		menuPanel.DrawText(" ");
		for (int i = 0; i < g_footer.Length; i++)
		{
			char footer[MAX_FOOTER_LEN];
			g_footer.GetString(i, footer, sizeof(footer));
			menuPanel.DrawText(footer);
		}
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !g_panelHidden[client])
		{
			if (BuiltinVote_IsVoteInProgress() && IsClientInBuiltinVotePool(client))
			{
				continue;
			}

			if (Game_IsVoteInProgress())
			{
				int voteteam = Game_GetVoteTeam();
				if (voteteam == -1 || voteteam == GetClientTeam(client))
				{
					continue;
				}
			}

			switch (GetClientMenu(client))
			{
				case MenuSource_External, MenuSource_Normal: continue;
			}

			menuPanel.Send(client, ReadyPanelHandler, 1);
		}
	}

	delete menuPanel;
}
// ZoneMod pause.sp::UpdatePanel. Team status rows become survivor player rows;
// the remaining text, order and spacing are unchanged. Both vote types take priority.
void UpdatePausePanel()
{
	Panel menuPanel = new Panel();
	char info[512], serverCvar[64];
	g_readyPanelServerCvar.GetString(serverCvar, sizeof(serverCvar));
	ConVar serverNameCvar = FindConVar(serverCvar);
	if (serverNameCvar == null) serverNameCvar = FindConVar("hostname");
	serverNameCvar.GetString(info, sizeof(info));
	Format(info, sizeof(info), "▸ Server: %s\n▸ Slots: %d/%d", info, GetSeriousClientCount(), FindConVar("sv_maxplayers").IntValue);
	menuPanel.DrawText(info);
	// passing NULL_STRING will use the rules defined in sm_datetime_format
	FormatTime(info, sizeof(info), NULL_STRING);
	Format(info, sizeof(info), "▸ %s", info);
	menuPanel.DrawText(info);
	menuPanel.DrawText(" ");
	menuPanel.DrawText("▸ Ready Status");
	if (g_adminPause) menuPanel.DrawText("->0. Require Admin to Unpause");
	int player;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanSurvivor(client)) continue;
		FormatEx(info, sizeof(info), "->%d. %N: [%s]", ++player, client, g_playerReady[client] ? "√" : "X");
		menuPanel.DrawText(info);
	}
	menuPanel.DrawText(" ");
	if (g_adminPause) FormatEx(info, sizeof(info), "▸ Force Pause -> %s (Admin)", g_pauseInitiator);
	else FormatEx(info, sizeof(info), "▸ Initiator -> %s (Survivors)", g_pauseInitiator);
	menuPanel.DrawText(info);
	int duration = RoundToNearest(GetEngineTime() - g_panelStarted);
	FormatEx(info, sizeof(info), "▸ Duration: %02d:%02d", duration / 60, duration % 60);
	menuPanel.DrawText(info);
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !g_panelHidden[client])
		{
			if (BuiltinVote_IsVoteInProgress() && IsClientInBuiltinVotePool(client)) continue;
			if (Game_IsVoteInProgress())
			{
				int voteTeam = Game_GetVoteTeam();
				if (voteTeam == -1 || voteTeam == GetClientTeam(client)) continue;
			}
			menuPanel.Send(client, ReadyPanelHandler, 1);
		}
	}
	delete menuPanel;
}

#define AFK_DURATION 15.0
bool IsPlayerAfk(int client)
{
	return GetEngineTime() - g_panelButtonTime[client] > AFK_DURATION;
}

void GetClientFixedName(int client, char[] name, int length)
{
	GetClientName(client, name, length);

	if (name[0] == '[')
	{
		char temp[MAX_NAME_LENGTH];
		strcopy(temp, sizeof(temp), name);
		temp[sizeof(temp)-2] = 0;
		strcopy(name[1], length-1, temp);
		name[0] = ' ';
	}
}

bool IsPlayer(int client)
{
	if (!IsClientInGame(client))
		return false;

	int team = GetClientTeam(client);
	return (team == TEAM_SURVIVORS || team == 3);
}

int GetSeriousClientCount(bool inGame = false)
{
	int clients = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (inGame)
		{
			if (IsClientInGame(i) && !IsFakeClient(i)) clients++;
		}
		else
		{
			if (IsClientConnected(i) && !IsFakeClient(i)) clients++;
		}
	}

	return clients;
}
