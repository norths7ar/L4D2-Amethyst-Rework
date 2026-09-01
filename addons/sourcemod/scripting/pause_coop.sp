#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"
#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2

/**
 * Coop pause is based on CanadaRox and 海洋空氣's pause_coop.sp from
 * L4D2-AstMod-Scriptings commit 9e7179187dd71d846a8a622d20a2fe43f0a312f1.
 * It intentionally tracks each human survivor instead of one ready bit for an
 * entire team. Lifecycle and late-join handling are maintained here rather
 * than inherited from the old ReadyUp-free fork.
 */

public Plugin myinfo =
{
	name = "Pause plugin (Coop)",
	author = "CanadaRox, 海洋空氣, Amethyst Rework",
	description = "Coop pause with per-survivor ready status",
	version = PLUGIN_VERSION,
	url = "https://github.com/Sglight/L4D2-AstMod-Scriptings"
};

bool g_isPaused;
bool g_adminPause;
bool g_internalPauseCommand;
bool g_playerReady[MAXPLAYERS + 1];
bool g_panelHidden[MAXPLAYERS + 1];

ConVar g_svPausable;
ConVar g_svNoclipDuringPause;
ConVar g_pauseDelayCvar;
ConVar g_unpauseDelayCvar;
ConVar g_readyBlipsCvar;

Handle g_pauseForward;
Handle g_unpauseForward;
Handle g_pauseDelayTimer;
Handle g_deferredPauseTimer;
Handle g_countdownTimer;
Handle g_panelTimer;

int g_pauseDelayRemaining;
int g_countdownRemaining;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorLength)
{
	CreateNative("IsInPause", Native_IsInPause);
	g_pauseForward = CreateGlobalForward("OnPause", ET_Ignore);
	g_unpauseForward = CreateGlobalForward("OnUnpause", ET_Ignore);
	RegPluginLibrary("pause");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_svPausable = FindConVar("sv_pausable");
	g_svNoclipDuringPause = FindConVar("sv_noclipduringpause");
	g_pauseDelayCvar = CreateConVar("sm_pausedelay", "0", "Seconds before a normal coop pause begins.", _, true, 0.0);
	g_unpauseDelayCvar = CreateConVar("sm_unpausedelay", "5", "Ready countdown before a coop pause ends.", _, true, 0.0);
	g_readyBlipsCvar = CreateConVar("sm_pause_ready_blips", "1", "Play a countdown sound before unpausing.", _, true, 0.0, true, 1.0);

	RegConsoleCmd("sm_pause", Command_Pause, "Pause the game");
	RegConsoleCmd("sm_p", Command_Pause, "Pause the game");
	RegConsoleCmd("sm_unpause", Command_Ready, "Mark yourself ready to unpause");
	RegConsoleCmd("sm_ready", Command_Ready, "Mark yourself ready to unpause");
	RegConsoleCmd("sm_r", Command_Ready, "Mark yourself ready to unpause");
	RegConsoleCmd("sm_unready", Command_Unready, "Cancel your ready status");
	RegConsoleCmd("sm_ur", Command_Unready, "Cancel your ready status");
	RegConsoleCmd("sm_nr", Command_Unready, "Cancel your ready status");
	RegConsoleCmd("sm_toggleready", Command_ToggleReady, "Toggle your ready status");
	RegConsoleCmd("sm_pausepanel", Command_ShowPanel, "Show the coop pause panel");
	RegConsoleCmd("sm_show", Command_ShowPanel, "Show the coop pause panel");
	RegConsoleCmd("sm_hide", Command_HidePanel, "Hide the coop pause panel");

	RegAdminCmd("sm_forcepause", Command_ForcePause, ADMFLAG_BAN, "Pause until an admin unpauses");
	RegAdminCmd("sm_forceunpause", Command_ForceUnpause, ADMFLAG_BAN, "Unpause regardless of ready status");
	RegAdminCmd("sm_forcestart", Command_ForceUnpause, ADMFLAG_BAN, "Unpause regardless of ready status");
	RegAdminCmd("sm_fs", Command_ForceUnpause, ADMFLAG_BAN, "Unpause regardless of ready status");

	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_TeamSay, "say_team");
	AddCommandListener(Listener_BlockEngineUnpause, "unpause");

	HookEvent("round_end", Event_RoundBoundary, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundBoundary, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
}

public void OnMapStart()
{
	PrecacheSound("buttons/blip2.wav");
	ResetPauseState(false);
}

public void OnMapEnd()
{
	ResetPauseState(true);
}

public void OnPluginEnd()
{
	if (g_isPaused)
		SetEnginePaused(false);
	ResetPauseState(false);
}

public void OnClientPutInServer(int client)
{
	g_playerReady[client] = false;
	g_panelHidden[client] = false;
	if (g_isPaused && !IsFakeClient(client))
		PrintToChatAll("\x04[暂停] \x03%N \x01已进入服务器；加入生还者后需要输入 \x05!r \x01准备。", client);
}

public void OnClientDisconnect_Post(int client)
{
	g_playerReady[client] = false;
	g_panelHidden[client] = false;
	if (g_isPaused)
		CreateTimer(0.1, Timer_ReevaluateRoster, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Event_RoundBoundary(Event event, const char[] name, bool dontBroadcast)
{
	ResetPauseState(true);
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && !IsFakeClient(client))
	{
		g_playerReady[client] = false;
		if (g_isPaused)
			CreateTimer(0.1, Timer_ReevaluateRoster, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

public Action Timer_ReevaluateRoster(Handle timer)
{
	if (g_isPaused)
		EvaluateReadyState();
	return Plugin_Stop;
}

public Action Command_Pause(int client, int args)
{
	if (!IsHumanSurvivor(client) || g_isPaused || g_pauseDelayTimer != null || g_deferredPauseTimer != null)
		return Plugin_Handled;

	g_pauseDelayRemaining = g_pauseDelayCvar.IntValue;
	PrintToChatAll("\x04[暂停] \x03%N \x01请求暂停。暂停后每位生还者输入 \x05!r \x01准备。", client);

	if (g_pauseDelayRemaining <= 0)
		AttemptPause(false);
	else
	{
		PrintToChatAll("\x04[暂停] \x01将在 %d 秒后暂停。", g_pauseDelayRemaining);
		g_pauseDelayTimer = CreateTimer(1.0, Timer_PauseDelay, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Handled;
}

public Action Timer_PauseDelay(Handle timer)
{
	g_pauseDelayRemaining--;
	if (g_pauseDelayRemaining <= 0)
	{
		g_pauseDelayTimer = null;
		AttemptPause(false);
		return Plugin_Stop;
	}

	PrintToChatAll("\x04[暂停] \x01将在 %d 秒后暂停。", g_pauseDelayRemaining);
	return Plugin_Continue;
}

void AttemptPause(bool adminPause)
{
	if (g_isPaused)
		return;

	if (adminPause || CanPauseNow())
	{
		BeginPause(adminPause);
		return;
	}

	PrintToChatAll("\x04[暂停] \x01有人正在救援，暂停将在动作结束后生效。");
	g_adminPause = adminPause;
	g_deferredPauseTimer = CreateTimer(0.1, Timer_DeferredPause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DeferredPause(Handle timer)
{
	if (!CanPauseNow())
		return Plugin_Continue;

	g_deferredPauseTimer = null;
	BeginPause(g_adminPause);
	return Plugin_Stop;
}

void BeginPause(bool adminPause)
{
	CancelTimerHandle(g_pauseDelayTimer);
	CancelTimerHandle(g_deferredPauseTimer);
	CancelTimerHandle(g_countdownTimer);

	g_isPaused = true;
	g_adminPause = adminPause;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_playerReady[client] = false;
		g_panelHidden[client] = false;
	}

	SetEnginePaused(true);
	if (adminPause)
		PrintToChatAll("\x04[暂停] \x01管理员强制暂停；需要管理员解除。");
	else
		PrintToChatAll("\x04[暂停] \x01游戏已暂停。所有生还者输入 \x05!r \x01后继续。");

	RenderPausePanel();
	g_panelTimer = CreateTimer(1.0, Timer_RefreshPanel, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	Call_StartForward(g_pauseForward);
	Call_Finish();
}

public Action Command_Ready(int client, int args)
{
	if (!g_isPaused || !IsHumanSurvivor(client))
		return Plugin_Handled;

	if (!g_playerReady[client])
	{
		g_playerReady[client] = true;
		PrintToChatAll("\x04[暂停] \x03%N \x01已准备。", client);
	}
	EvaluateReadyState();
	RenderPausePanel();
	return Plugin_Handled;
}

public Action Command_Unready(int client, int args)
{
	if (!g_isPaused || !IsHumanSurvivor(client))
		return Plugin_Handled;

	if (g_playerReady[client])
	{
		g_playerReady[client] = false;
		PrintToChatAll("\x04[暂停] \x03%N \x01取消准备。", client);
	}
	CancelCountdown(client);
	RenderPausePanel();
	return Plugin_Handled;
}

public Action Command_ToggleReady(int client, int args)
{
	return g_playerReady[client] ? Command_Unready(client, args) : Command_Ready(client, args);
}

void EvaluateReadyState()
{
	if (!g_isPaused)
		return;

	if (g_adminPause)
	{
		CancelCountdown(0);
		return;
	}

	if (AreAllSurvivorsReady())
		StartCountdown();
	else
		CancelCountdown(0);
}

bool AreAllSurvivorsReady()
{
	int humans;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanSurvivor(client))
			continue;
		humans++;
		if (!g_playerReady[client])
			return false;
	}
	return humans > 0;
}

void StartCountdown()
{
	if (g_countdownTimer != null)
		return;

	g_countdownRemaining = g_unpauseDelayCvar.IntValue;
	if (g_countdownRemaining <= 0)
	{
		EndPause();
		return;
	}

	PrintToChatAll("\x04[暂停] \x01全员准备，输入 \x05!ur \x01可取消倒计时。");
	PrintToChatAll("\x04[暂停] \x01%d……", g_countdownRemaining);
	if (g_readyBlipsCvar.BoolValue)
		EmitSoundToAll("buttons/blip2.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	g_countdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Countdown(Handle timer)
{
	if (!g_isPaused || !AreAllSurvivorsReady())
	{
		g_countdownTimer = null;
		return Plugin_Stop;
	}

	g_countdownRemaining--;
	if (g_countdownRemaining <= 0)
	{
		g_countdownTimer = null;
		EndPause();
		return Plugin_Stop;
	}

	PrintToChatAll("\x04[暂停] \x01%d……", g_countdownRemaining);
	if (g_readyBlipsCvar.BoolValue)
		EmitSoundToAll("buttons/blip2.wav", _, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
	RenderPausePanel();
	return Plugin_Continue;
}

void CancelCountdown(int client)
{
	if (g_countdownTimer == null)
		return;

	CancelTimerHandle(g_countdownTimer);
	if (client > 0)
		PrintToChatAll("\x04[暂停] \x03%N \x01中断了倒计时。", client);
}

void EndPause()
{
	if (!g_isPaused)
		return;

	CancelTimerHandle(g_countdownTimer);
	CancelTimerHandle(g_panelTimer);
	SetEnginePaused(false);
	g_isPaused = false;
	g_adminPause = false;

	PrintToChatAll("\x04[暂停] \x01游戏继续。");
	Call_StartForward(g_unpauseForward);
	Call_Finish();
}

public Action Command_ForcePause(int client, int args)
{
	if (!g_isPaused)
		AttemptPause(true);
	else
	{
		g_adminPause = true;
		CancelCountdown(0);
		PrintToChatAll("\x04[暂停] \x01暂停已转为管理员强制暂停。");
	}
	return Plugin_Handled;
}

public Action Command_ForceUnpause(int client, int args)
{
	if (g_isPaused)
	{
		g_adminPause = false;
		EndPause();
	}
	return Plugin_Handled;
}

public Action Command_ShowPanel(int client, int args)
{
	if (client > 0)
	{
		g_panelHidden[client] = false;
		if (g_isPaused)
			RenderPausePanel();
	}
	return Plugin_Handled;
}

public Action Command_HidePanel(int client, int args)
{
	if (client > 0)
		g_panelHidden[client] = true;
	return Plugin_Handled;
}

public Action Timer_RefreshPanel(Handle timer)
{
	if (!g_isPaused)
	{
		g_panelTimer = null;
		return Plugin_Stop;
	}
	RenderPausePanel();
	return Plugin_Continue;
}

void RenderPausePanel()
{
	if (!g_isPaused)
		return;

	Panel panel = new Panel();
	panel.SetTitle(g_adminPause ? "合作模式暂停\n管理员强制暂停" : "合作模式暂停\n全体生还者准备后继续");

	char line[96];
	int humans;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsHumanSurvivor(client))
			continue;
		humans++;
		FormatEx(line, sizeof(line), g_playerReady[client] ? "☑ %N" : "☐ %N", client);
		panel.DrawText(line);
	}

	if (!humans)
		panel.DrawText("暂无人类生还者");
	panel.DrawText(" ");
	if (g_countdownTimer != null)
	{
		FormatEx(line, sizeof(line), "将在 %d 秒后继续", g_countdownRemaining);
		panel.DrawText(line);
	}
	else if (!g_adminPause)
		panel.DrawText("输入 !r 准备，!ur 取消准备");

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client) && !g_panelHidden[client])
			panel.Send(client, PanelHandler, 2);
	}
	delete panel;
}

public int PanelHandler(Menu menu, MenuAction action, int param1, int param2)
{
	return 0;
}

void SetEnginePaused(bool pause)
{
	bool oldPausable = g_svPausable.BoolValue;
	g_svPausable.BoolValue = true;
	g_internalPauseCommand = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		FakeClientCommand(client, pause ? "pause" : "unpause");
		break;
	}

	g_internalPauseCommand = false;
	g_svPausable.BoolValue = oldPausable;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SPECTATOR)
			SendConVarValue(client, g_svNoclipDuringPause, pause ? "1" : "0");
	}
}

bool CanPauseNow()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_SURVIVOR)
			continue;

		if (GetEntProp(client, Prop_Send, "m_isIncapacitated"))
		{
			if (GetEntProp(client, Prop_Send, "m_reviveOwner") > 0)
				return false;
		}
		else if (GetEntProp(client, Prop_Send, "m_reviveTarget") > 0)
		{
			return false;
		}
	}
	return true;
}

public Action Listener_BlockEngineUnpause(int client, const char[] command, int argc)
{
	return g_isPaused && !g_internalPauseCommand ? Plugin_Handled : Plugin_Continue;
}

public Action Listener_Say(int client, const char[] command, int argc)
{
	if (!g_isPaused)
		return Plugin_Continue;

	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (!message[0] || message[0] == '!' || message[0] == '/')
		return Plugin_Continue;

	if (client == 0)
		PrintToChatAll("Console: %s", message);
	else
		PrintToChatAll("%N: %s", client, message);
	return Plugin_Handled;
}

public Action Listener_TeamSay(int client, const char[] command, int argc)
{
	if (!g_isPaused || client <= 0)
		return Plugin_Continue;

	char message[256];
	GetCmdArgString(message, sizeof(message));
	StripQuotes(message);
	if (!message[0] || message[0] == '!' || message[0] == '/')
		return Plugin_Continue;

	int team = GetClientTeam(client);
	for (int target = 1; target <= MaxClients; target++)
	{
		if (IsClientInGame(target) && GetClientTeam(target) == team)
			PrintToChat(target, "(团队) %N: %s", client, message);
	}
	return Plugin_Handled;
}

int Native_IsInPause(Handle plugin, int numParams)
{
	return g_isPaused;
}

bool IsHumanSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR;
}

void CancelTimerHandle(Handle &timer)
{
	if (timer != null)
	{
		delete timer;
		timer = null;
	}
}

void ResetPauseState(bool unpauseEngine)
{
	if (unpauseEngine && g_isPaused)
		SetEnginePaused(false);

	CancelTimerHandle(g_pauseDelayTimer);
	CancelTimerHandle(g_deferredPauseTimer);
	CancelTimerHandle(g_countdownTimer);
	CancelTimerHandle(g_panelTimer);
	g_isPaused = false;
	g_adminPause = false;
	g_internalPauseCommand = false;
	for (int client = 1; client <= MaxClients; client++)
	{
		g_playerReady[client] = false;
		g_panelHidden[client] = false;
	}
}
