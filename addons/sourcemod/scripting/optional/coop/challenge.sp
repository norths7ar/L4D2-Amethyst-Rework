#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <left4dhooks>

#define MENU_DISPLAY_TIME		15

#define TEAM_SURVIVORS          2

int tempTankDmg = -1;
int tempTankBhop = -1;
int tempTankRock = -1;
int tempPlayerInfected = -1;
int tempPlayerTank = -1;
int tempMorePills = -1;
int tempKillMapPills = -1;
int tempRatioDamage = -1;
int tempRehealth = -1;
int tempReammo = -1;
int tempSIDamage = -1;
int g_iOverrideMask;
Handle g_hEmptyResetTimer;
Handle g_hReminderTimer;

ConVar hRehealth;
ConVar hReammo;

Handle g_hVote;

ConVar hDmgThreshold;
ConVar hRatioDamage;

public Plugin myinfo =
{
	name = "Coop Challenge",
	author = "海洋空氣, norths7ar",
	description = "Difficulty Controller for Coop.",
	version = "2.6-integration",
	url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_tz", challengeRequest, "打开难度控制系统菜单");
	RegConsoleCmd("sm_ast", challengeRequest, "打开 Ast 玩法调整菜单");
	RegAdminCmd("sm_reset", ResetSettingsCommand, ADMFLAG_CONFIG, "立即恢复当前 Ast 模式默认设置");
	HookEvent("player_team", OnChangeTeam, EventHookMode_Post);

	hRehealth = FindConVar("kill_rewards_health_enable");
	hReammo = FindConVar("kill_rewards_ammo_enable");
	hDmgThreshold = FindConVar("si_damage_base");
	hRatioDamage = FindConVar("si_damage_ratio_enable");

	g_hReminderTimer = CreateTimer(300.0, Timer_RemindOverrides, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	// 出门输出特感刷新参数
	float fTimerCurrent = GetConVarFloat(FindConVar("wave_interval"));
	int iLimitCurrent = GetConVarInt(FindConVar("wave_size"));
	PrintToChatAll("\x04[Ast] \x01当前刷新速率：\x03%.1f秒%i特\x01.", fTimerCurrent, iLimitCurrent);
}

public Action challengeRequest(int client, int args)
{
	if (client) {
		drawPanel(client, 0);
	}
	return Plugin_Handled;
}

public Action ResetSettingsCommand(int client, int args)
{
	ResetSettings(true);
	return Plugin_Handled;
}

public Action drawPanel(int client, int first_item)
{
	char buffer[64];
	Menu menu = CreateMenu(MenuHandler);
	char status[64];
	GetGameplayStatus(status, sizeof(status));
	SetMenuTitle(menu, "Ast 玩法调整 | %s", status);
	SetMenuExitButton(menu, true);

	AddNamedToggleMenuItem(menu, "tank_bhop", "Tank 连跳", GetConVarBool(FindConVar("ai_tank_bhop")));
	AddNamedToggleMenuItem(menu, "tank_rock", "Tank 石头", GetConVarBool(FindConVar("ai_tank_rock")));
	Format(buffer, sizeof(buffer), "修改 Tank 伤害 [%i]", GetConVarInt(FindConVar("vs_tank_damage")));
	AddMenuItem(menu, "tank_damage", buffer);
	AddMenuItem(menu, "si", "特感刷新：使用 !si <间隔> <数量>");
	Format(buffer, sizeof(buffer), "[单人] 特感基础伤害 [%i]", GetConVarInt(hDmgThreshold));
	AddMenuItem(menu, "si_damage", buffer);
	AddNamedToggleMenuItem(menu, "ratio_damage", "[单人] 按特感血量比例扣血", GetConVarBool(hRatioDamage));
	AddNamedToggleMenuItem(menu, "rehealth", "击杀特感回血", GetConVarBool(hRehealth));
	AddNamedToggleMenuItem(menu, "reammo", "击杀回复备弹", GetConVarBool(hReammo));
	AddMenuItem(menu, "pills", "额外发药设定");
	AddMenuItem(menu, "player_infected", "玩家特感设定");
	AddMenuItem(menu, "reset", "恢复默认设置");

	DisplayMenuAtItem(menu, client, first_item, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}

public int MenuHandler(Handle menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select) {
		char item[32];
		GetMenuItem(menu, param, item, sizeof(item));
		if (StrEqual(item, "tank_bhop")) {
			TZ_CallVote(client, 2, !GetConVarBool(FindConVar("ai_tank_bhop")));
		} else if (StrEqual(item, "tank_rock")) {
			TZ_CallVote(client, 3, !GetConVarBool(FindConVar("ai_tank_rock")));
		} else if (StrEqual(item, "tank_damage")) {
			Menu_TankDmg(client, false);
		} else if (StrEqual(item, "si")) {
			FakeClientCommand(client, "sm_si");
			drawPanel(client, 0);
		} else if (StrEqual(item, "si_damage")) {
			if (CountHumanSurvivors() == 1 && GetDifficulty() == 1) {
				Menu_SIDamage(client, false);
			} else {
				PrintToChat(client, "\x04[Ast] \x01特感基础伤害只允许单人调整.");
				drawPanel(client, 0);
			}
		} else if (StrEqual(item, "ratio_damage")) {
			if (!IsClientSurvivor(client, true) || CountHumanSurvivors() != 1 || GetDifficulty() != 1) {
				PrintToChat(client, "\x04[Ast] \x01按特感血量比例扣血只允许单人调整.");
				drawPanel(client, 0);
				return 1;
			}
			TZ_CallVote(client, 11, !GetConVarBool(hRatioDamage));
			drawPanel(client, 0);
		} else if (StrEqual(item, "rehealth")) {
			if (!IsClientSurvivor(client, true)) {
				drawPanel(client, 0);
				return 1;
			}
			TZ_CallVote(client, 12, !GetConVarBool(hRehealth));
			drawPanel(client, 0);
		} else if (StrEqual(item, "reammo")) {
			if (!IsClientSurvivor(client, true)) {
				drawPanel(client, 0);
				return 1;
			}
			TZ_CallVote(client, 13, !GetConVarBool(hReammo));
			drawPanel(client, 0);
		} else if (StrEqual(item, "pills")) {
			Menu_MorePills(client, false);
		} else if (StrEqual(item, "player_infected")) {
			Menu_PlayerInfected(client, false);
		} else if (StrEqual(item, "reset")) {
			TZ_CallVote(client, 14, 0);
			drawPanel(client, 0);
		}
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 1;
}

int g_tankDamages[] = {24, 36, 48, 100};

public Action Menu_TankDmg(int client, int args)
{
	Handle menu = CreateMenu(Menu_TankDmgHandler);
	SetMenuTitle(menu, "修改 tank 伤害");
	SetMenuExitBackButton(menu, true);

	int currentDmg = GetConVarInt(FindConVar("vs_tank_damage"));

	for (int i = 0; i < sizeof(g_tankDamages); i++)
	{
		char label[16];
		Format(label, sizeof(label), "%s%d", (currentDmg == g_tankDamages[i]) ? "✔" : "", g_tankDamages[i]);
		
		char info[4];
		IntToString(i, info, sizeof(info));  // 用索引作为 info

		AddMenuItem(menu, info, label);
	}

	DisplayMenu(menu, client, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}

public int Menu_TankDmgHandler(Handle menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select)
	{
		if (0 <= param < sizeof(g_tankDamages))
		{
			TZ_CallVote(client, 1, g_tankDamages[param]);
		}
		drawPanel(client, 0);
	}
	else if (action == MenuAction_Cancel)
	{
		drawPanel(client, 0);
	}
	return 1;
}


public void TZ_CallVote(int client, int target, int value)
{
	if ( !IsClientSurvivor(client, true) ) return;
	if (CountHumanSurvivors() == 1) {
		ApplyGameplaySetting(target, value, true);
		return;
	}
	
	if ( IsNewBuiltinVoteAllowed() ) {
		int iNumPlayers;
		int iPlayers[MAXPLAYERS];
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsClientInGame(i) || IsFakeClient(i) || !isSurvivor(i)) {
				continue;
			}
			iPlayers[iNumPlayers++] = i;
		}

		char sBuffer[64];
		g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);

		switch (target) {
			case 1: { // Tank 伤害
				Format(sBuffer, sizeof(sBuffer), "修改 Tank 伤害为 [%i]", value);
				tempTankDmg = value;
				SetBuiltinVoteResultCallback(g_hVote, TankDmgVoteResultHandler);
			}
			case 2: { // Tank 连跳
				value ? Format(sBuffer, sizeof(sBuffer), "开启 Tank 连跳") : Format(sBuffer, sizeof(sBuffer), "关闭 Tank 连跳");
				tempTankBhop = value;
				SetBuiltinVoteResultCallback(g_hVote, TankBhopVoteResultHandler);
			}
			case 3: { // Tank 石头
				value ? Format(sBuffer, sizeof(sBuffer), "开启 Tank 丢石头") : Format(sBuffer, sizeof(sBuffer), "关闭 Tank 丢石头");
				tempTankRock = value;
				SetBuiltinVoteResultCallback(g_hVote, TankRockVoteResultHandler);
			}
			case 4: { // 玩家特感
				if (value == 0) {
					Format(sBuffer, sizeof(sBuffer), "禁止玩家加入特感");
				} else {
					Format(sBuffer, sizeof(sBuffer), "允许 %d 名玩家加入特感", value);
				}
				tempPlayerInfected = value;
				SetBuiltinVoteResultCallback(g_hVote, PlayerInfectedVoteResultHandler);
			}
			case 5: { // 玩家 Tank
				value ? Format(sBuffer, sizeof(sBuffer), "允许玩家扮演 Tank") : Format(sBuffer, sizeof(sBuffer), "禁止玩家扮演 Tank");
				tempPlayerTank = value;
				SetBuiltinVoteResultCallback(g_hVote, PlayerTankVoteResultHandler);
			}
			case 7: { // 额外发药
				value ? Format(sBuffer, sizeof(sBuffer), "开启额外发药") : Format(sBuffer, sizeof(sBuffer), "关闭额外发药");
				tempMorePills = value;
				SetBuiltinVoteResultCallback(g_hVote, MorePillsVoteResultHandler);
			}
			case 8: { // 删除地图药
				value ? Format(sBuffer, sizeof(sBuffer), "删除地图药（下回合生效）") : Format(sBuffer, sizeof(sBuffer), "保留地图药（下回合生效）");
				tempKillMapPills = value;
				SetBuiltinVoteResultCallback(g_hVote, KillMapPillsVoteResultHandler);
			}
			case 11: {
				value ? Format(sBuffer, sizeof(sBuffer), "开启按特感血量扣血") : Format(sBuffer, sizeof(sBuffer), "关闭按特感血量扣血");
				tempRatioDamage = value;
				SetBuiltinVoteResultCallback(g_hVote, RatioDamageVoteResultHandler);
			}
			case 12: {
				value ? Format(sBuffer, sizeof(sBuffer), "开启击杀特感回血") : Format(sBuffer, sizeof(sBuffer), "关闭击杀特感回血");
				tempRehealth = value;
				SetBuiltinVoteResultCallback(g_hVote, RehealthVoteResultHandler);
			}
			case 13: {
				value ? Format(sBuffer, sizeof(sBuffer), "开启击杀回复备弹") : Format(sBuffer, sizeof(sBuffer), "关闭击杀回复备弹");
				tempReammo = value;
				SetBuiltinVoteResultCallback(g_hVote, ReammoVoteResultHandler);
			}
			case 14: {
				Format(sBuffer, sizeof(sBuffer), "恢复当前模式默认设置");
				SetBuiltinVoteResultCallback(g_hVote, ResetVoteResultHandler);
			}
			case 15: {
				Format(sBuffer, sizeof(sBuffer), "修改特感基础伤害为 [%d]", value);
				tempSIDamage = value;
				SetBuiltinVoteResultCallback(g_hVote, SIDamageVoteResultHandler);
			}
		}

		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, MENU_DISPLAY_TIME);
		FakeClientCommand(client, "Vote Yes");
	}
}

void ApplyGameplaySetting(int target, int value, bool announce)
{
	switch (target) {
		case 1: { tempTankDmg = value; SetConVarInt(FindConVar("vs_tank_damage"), value); }
		case 2: { tempTankBhop = value; SetConVarInt(FindConVar("ai_tank_bhop"), value); }
		case 3: { tempTankRock = value; SetConVarInt(FindConVar("ai_tank_rock"), value); }
		case 4: { tempPlayerInfected = value; SetConVarInt(FindConVar("ast_maxinfected"), value); }
		case 5: { tempPlayerTank = value; SetConVarInt(FindConVar("ast_allowhumantank"), value); }
		case 7: { tempMorePills = value; SetConVarInt(FindConVar("ast_pills_enabled"), value); }
		case 8: { tempKillMapPills = value; SetConVarInt(FindConVar("ast_pills_map_kill"), value); }
		case 11: { tempRatioDamage = value; SetConVarInt(hRatioDamage, value); }
		case 12: { tempRehealth = value; SetConVarInt(hRehealth, value); }
		case 13: { tempReammo = value; SetConVarInt(hReammo, value); }
		case 14: {
			ResetSettings(true);
			return;
		}
		case 15: { tempSIDamage = value; hDmgThreshold.FloatValue = float(value); }
		default: return;
	}

	MarkOverride(target);
	if (announce) {
		PrintToChatAll("\x04[Ast] \x01单人调整已直接生效；使用 \x03!ast \x01查看当前状态.");
	}
}

void ReapplyGameplayOverrides()
{
	if (g_iOverrideMask == 0) return;
	if ((g_iOverrideMask & (1 << 1)) && tempTankDmg >= 0) ApplyGameplaySetting(1, tempTankDmg, false);
	if ((g_iOverrideMask & (1 << 2)) && tempTankBhop >= 0) ApplyGameplaySetting(2, tempTankBhop, false);
	if ((g_iOverrideMask & (1 << 3)) && tempTankRock >= 0) ApplyGameplaySetting(3, tempTankRock, false);
	if ((g_iOverrideMask & (1 << 4)) && tempPlayerInfected >= 0) ApplyGameplaySetting(4, tempPlayerInfected, false);
	if ((g_iOverrideMask & (1 << 5)) && tempPlayerTank >= 0) ApplyGameplaySetting(5, tempPlayerTank, false);
	if ((g_iOverrideMask & (1 << 7)) && tempMorePills >= 0) ApplyGameplaySetting(7, tempMorePills, false);
	if ((g_iOverrideMask & (1 << 8)) && tempKillMapPills >= 0) ApplyGameplaySetting(8, tempKillMapPills, false);
	if ((g_iOverrideMask & (1 << 11)) && tempRatioDamage >= 0) ApplyGameplaySetting(11, tempRatioDamage, false);
	if ((g_iOverrideMask & (1 << 12)) && tempRehealth >= 0) ApplyGameplaySetting(12, tempRehealth, false);
	if ((g_iOverrideMask & (1 << 13)) && tempReammo >= 0) ApplyGameplaySetting(13, tempReammo, false);
	if ((g_iOverrideMask & (1 << 15)) && tempSIDamage >= 0) ApplyGameplaySetting(15, tempSIDamage, false);
}

public Action Timer_ReapplyGameplayOverrides(Handle timer)
{
	ReapplyGameplayOverrides();
	return Plugin_Stop;
}

public void OnConfigsExecuted()
{
	CreateTimer(0.5, Timer_ReapplyGameplayOverrides, _, TIMER_FLAG_NO_MAPCHANGE);
}

void MarkOverride(int target)
{
	if (target > 0 && target < 31) {
		g_iOverrideMask |= (1 << target);
	}
}

public void TankDmgVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayBuiltinVotePass(vote, "正在更改 Tank 伤害...");
				ApplyGameplaySetting(1, tempTankDmg, false);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void TankBhopVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayBuiltinVotePass(vote, "正在更改 Tank 连跳...");
				ApplyGameplaySetting(2, tempTankBhop, false);
				return;
			}
		}
	}
	tempTankBhop = GetConVarInt(FindConVar("ai_tank_bhop"));
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void TankRockVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayBuiltinVotePass(vote, "正在更改 Tank 丢石头...");
				ApplyGameplaySetting(3, tempTankRock, false);
				return;
			}
		}
	}
	tempTankRock = GetConVarInt(FindConVar("ai_tank_rock"));
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void PlayerInfectedVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				char sBuffer[64];
				Format(sBuffer, sizeof(sBuffer), "正在更改特感玩家数量为 %d ...", tempPlayerInfected);
				DisplayBuiltinVotePass(vote, sBuffer);
				ApplyGameplaySetting(4, tempPlayerInfected, false);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void PlayerTankVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				char sBuffer[64];
				tempPlayerTank == 0 ? Format(sBuffer, sizeof(sBuffer), "禁止") : Format(sBuffer, sizeof(sBuffer), "允许");
				Format(sBuffer, sizeof(sBuffer), "%s玩家扮演 Tank", sBuffer);
				DisplayBuiltinVotePass(vote, sBuffer);
				ApplyGameplaySetting(5, tempPlayerTank, false);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void MorePillsVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				char sBuffer[64];
				tempMorePills == 0 ? Format(sBuffer, sizeof(sBuffer), "关闭") : Format(sBuffer, sizeof(sBuffer), "开启");
				Format(sBuffer, sizeof(sBuffer), "正在 %s 额外发药...", sBuffer);
				DisplayBuiltinVotePass(vote, sBuffer);
				ApplyGameplaySetting(7, tempMorePills, false);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void KillMapPillsVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				char sBuffer[64];
				tempKillMapPills == 0 ? Format(sBuffer, sizeof(sBuffer), "保留") : Format(sBuffer, sizeof(sBuffer), "删除");
				Format(sBuffer, sizeof(sBuffer), "已设置为 %s 地图药，下回合生效", sBuffer);
				DisplayBuiltinVotePass(vote, sBuffer);
				ApplyGameplaySetting(8, tempKillMapPills, false);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

bool DidVotePass(int num_votes, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES && item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
			return true;
		}
	}
	return false;
}

public void RatioDamageVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVotePass(vote, "正在更改比例伤害设置...");
		ApplyGameplaySetting(11, tempRatioDamage, false);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void RehealthVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVotePass(vote, "正在更改击杀回血设置...");
		ApplyGameplaySetting(12, tempRehealth, false);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void ReammoVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVotePass(vote, "正在更改击杀回备弹设置...");
		ApplyGameplaySetting(13, tempReammo, false);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void ResetVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVotePass(vote, "正在恢复当前模式默认设置...");
		ResetSettings(true);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void SIDamageVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVotePass(vote, "正在更改特感基础伤害...");
		ApplyGameplaySetting(15, tempSIDamage, false);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action) {
		case BuiltinVoteAction_End: {
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
			return;
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail( vote, view_as<BuiltinVoteFailReason>(param1) );
			return;
		}
	}
	return;
}


public Action Menu_SITimer(int client, int args)
{
	Menu menu = new Menu(Menu_SITimerHandler);
	ConVar waveTimer = FindConVar("wave_interval");
	ConVar waveLimit = FindConVar("wave_size");
	if (waveTimer != null && waveLimit != null) {
		menu.SetTitle("当前刷新速率：%.1f秒%i特", waveTimer.FloatValue, waveLimit.IntValue);
	} else {
		menu.SetTitle("特感刷新参数尚未就绪");
	}
	menu.ExitBackButton = true;
	menu.AddItem("", "使用 !si 修改刷新参数", ITEMDRAW_DISABLED);
	menu.Display(client, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}

public int Menu_SITimerHandler(Menu menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Cancel && param == MenuCancel_ExitBack) {
		drawPanel(client, 0);
	} else if (action == MenuAction_End) {
		delete menu;
	}
	return 0;
}

int SIDamageOptions[] = {8, 12, 24};

public Action Menu_SIDamage(int client, int args)
{
	Handle menu = CreateMenu(Menu_SIDamageHandler);
	int dmg = GetConVarInt(hDmgThreshold);
	SetMenuTitle(menu, "修改特感基础伤害");
	SetMenuExitBackButton(menu, true);

	char sBuffer[16];
	for (int i = 0; i < sizeof(SIDamageOptions); i++) {
		bool selected = (SIDamageOptions[i] == dmg);
		Format(sBuffer, sizeof(sBuffer), "%i", SIDamageOptions[i]);
		AddToggleMenuItem(menu, sBuffer, selected);
	}

	DisplayMenu(menu, client, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}

public int Menu_SIDamageHandler(Handle menu, MenuAction action, int client, int param)
{
	if (!IsClientSurvivor(client, true)) {
		drawPanel(client, 0);
		return 1;
	}

	if (action == MenuAction_Select) {
		if ( param > sizeof(SIDamageOptions) ) return 1;
		TZ_CallVote(client, 15, SIDamageOptions[param]);
		drawPanel(client, 0);
	} else if (action == MenuAction_Cancel) {
		drawPanel(client, 0);
	}
	return 1;
}


public void ResetSettings(bool announce)
{
	g_iOverrideMask = 0;
	tempTankBhop = -1;
	tempTankRock = -1;
	tempTankDmg = -1;
	tempPlayerInfected = -1;
	tempPlayerTank = -1;
	tempMorePills = -1;
	tempKillMapPills = -1;
	tempRatioDamage = -1;
	tempRehealth = -1;
	tempReammo = -1;
	tempSIDamage = -1;
	ServerCommand("sm_wave_reset_override");
	ServerCommand("sm_profile_reapply");
	if (announce) {
		PrintToChatAll("\x04[Ast] \x01已恢复当前模式和人数档位的默认设置.");
	}
}

public void ProfileController_OnProfileApplied(int profile)
{
	ReapplyGameplayOverrides();
}

public Action Menu_MorePills(int client, int args)
{
	if (FindConVar("ast_pills_map_kill") == null) {
		PrintToChat(client, "\x04[Ast] \x05pills_giver.smx \x01插件未安装，请联系管理员.");
		drawPanel(client, 0);
		return Plugin_Handled;
	}

	// 开关，删除地图药
	Handle menu = CreateMenu(Menu_MorePillsHandler);
	SetMenuTitle(menu, "额外发药设定");
	SetMenuExitBackButton(menu, true);

	AddToggleMenuItem(menu, "自动发药", GetConVarBool(FindConVar("ast_pills_enabled")));
	AddToggleMenuItem(menu, "删除地图药", GetConVarBool(FindConVar("ast_pills_map_kill")));

	DisplayMenu(menu, client, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}

public int Menu_MorePillsHandler(Handle menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select) {
		switch (param)
		{
			case 0: {
				bool bPillsEnabled = GetConVarBool(FindConVar("ast_pills_enabled"));
				TZ_CallVote(client, 7, !bPillsEnabled);
			}
			case 1: {
				bool bPillsMapKill = GetConVarBool(FindConVar("ast_pills_map_kill"));
				TZ_CallVote(client, 8, !bPillsMapKill);
			}
		}
		drawPanel(client, 7);
	}
	else if (action == MenuAction_Cancel) drawPanel(client, 7);
	return 1;
}

public Action Menu_PlayerInfected(int client, int args)
{
	ConVar hMaxInfected = FindConVar("ast_maxinfected");
	ConVar hAllowHumanTank = FindConVar("ast_allowhumantank");

	if (hMaxInfected == null) {
		PrintToChat(client, "\x04[Ast] \x05jointeam.smx \x01插件未安装，请联系管理员.");
		drawPanel(client, 0);
		return Plugin_Handled;
	}

	Handle menu = CreateMenu(Menu_PlayerInfectedHandler);
	SetMenuTitle(menu, "玩家特感设定");
	SetMenuExitBackButton(menu, true);

	int iMaxInfected = GetConVarInt(hMaxInfected);

	for (int i = 0; i <= 4; i++) {
		if (i == 0)
			AddToggleMenuItem(menu, "禁止玩家加入特感", !iMaxInfected);
		else {
			char buffer[32];
			Format(buffer, sizeof(buffer), "允许 %d 位特感", i);
			AddToggleMenuItem(menu, buffer, iMaxInfected == i);
		}
	}

	bool bAllowHumanTank = GetConVarBool(hAllowHumanTank);
	AddToggleMenuItem(menu, "禁止玩家扮演 Tank", !bAllowHumanTank);
	AddToggleMenuItem(menu, "允许玩家扮演 Tank", bAllowHumanTank);

	DisplayMenu(menu, client, MENU_DISPLAY_TIME);
	return Plugin_Handled;

}

public int Menu_PlayerInfectedHandler(Handle menu, MenuAction action, int client, int param)
{
	if (action == MenuAction_Select) {
		if (param >= 0 && param <= 4) {
			TZ_CallVote(client, 4, param);
		} else if (param == 5 || param == 6) {
			TZ_CallVote(client, 5, param - 5);
		}
		// DisplayMenu(menu, client, MENU_DISPLAY_TIME);
		drawPanel(client, 7);
	}
	else if (action == MenuAction_Cancel) drawPanel(client, 7);
	return 1;
}

///////////////////////////
//           Event           //
//////////////////////////
// 延迟设置 Tank 连跳和饼状态，覆盖 cfg 设置
public Action OnChangeTeam(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int newteam = GetEventInt(event, "team");
	int oldteam = GetEventInt(event, "oldteam");
	if (client > 0 && IsClientInGame(client) && IsFakeClient(client) 
	&& (newteam == TEAM_SURVIVORS || oldteam == TEAM_SURVIVORS)) {
		ArrayList cvar = new ArrayList();
		cvar.Push(tempTankBhop);
		cvar.Push(tempTankRock);
		
		CreateTimer(1.0, Timer_SetTankConVar, cvar);
	}
	return Plugin_Continue;
}

public Action Timer_SetTankConVar(Handle timer, ArrayList cvar)
{
	if (cvar.Get(0) != -1) {
		SetConVarInt(FindConVar("ai_tank_bhop"), tempTankBhop);
	}
	if (cvar.Get(1) != -1) {
		SetConVarInt(FindConVar("ai_tank_rock"), tempTankRock);
	}
	return Plugin_Continue;
}

stock bool IsClientAndInGame(int index) {
	return (index > 0 && index <= MaxClients && IsClientInGame(index));
}

public bool IsClientSurvivor(int client, bool isMenu) {
	if ( !IsClientAndInGame(client) ) return false;
	if (!isSurvivor(client)) {
		if (isMenu) {
			PrintToChat(client, "\x04[Ast] \x01仅限生还者选择!");
		}
		return false;
	}
	return true;
}

public int GetDifficulty() {
	ConVar cDifficulty = FindConVar("profile_current");
	if (cDifficulty == null) {
		PrintToServer("[Coop Challenge] profile_controller.smx is not loaded.");
		LogError("profile_controller.smx is not loaded");
		return 4;
	}
	return GetConVarInt(cDifficulty);
}

void AddToggleMenuItem(Handle menu, const char[] label, bool enabled)
{
    char sBuffer[32];
    Format(sBuffer, sizeof(sBuffer), "%s%s", enabled ? "✔" : "", label);
    AddMenuItem(menu, "", sBuffer);
}

void AddNamedToggleMenuItem(Handle menu, const char[] info, const char[] label, bool enabled)
{
	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%s%s", enabled ? "✔" : "", label);
	AddMenuItem(menu, info, sBuffer);
}

int CountHumanSurvivors()
{
	int count;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i) && isSurvivor(i)) count++;
	}
	return count;
}

int CountHumanPlayers()
{
	int count;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && !IsFakeClient(i)) count++;
	}
	return count;
}

int CountOverrides()
{
	int mask = g_iOverrideMask;
	int count;
	while (mask != 0) {
		count += mask & 1;
		mask >>>= 1;
	}
	ConVar waveOverride = FindConVar("wave_override_active");
	if (waveOverride != null && waveOverride.BoolValue) count++;
	return count;
}

void GetGameplayStatus(char[] buffer, int maxlen)
{
	int difficulty = GetDifficulty();
	if (difficulty < 1 || difficulty > 4) difficulty = CountHumanSurvivors();
	Format(buffer, maxlen, "%dP | 临时调整 %d", difficulty, CountOverrides());
}

void PrintGameplayStatus(int client)
{
	char status[64];
	GetGameplayStatus(status, sizeof(status));
	ConVar waveTimer = FindConVar("wave_interval");
	ConVar waveLimit = FindConVar("wave_size");
	if (waveTimer != null && waveLimit != null) {
		PrintToChat(client, "\x04[Ast] \x01当前：\x03%s\x01，刷新 %.1f 秒 / %d 特.", status, waveTimer.FloatValue, waveLimit.IntValue);
	} else {
		PrintToChat(client, "\x04[Ast] \x01当前：\x03%s\x01.", status);
	}
}

public Action Timer_RemindOverrides(Handle timer)
{
	if (CountOverrides() > 0) {
		char status[64];
		GetGameplayStatus(status, sizeof(status));
		PrintToChatAll("\x04[Ast] \x01当前存在临时玩法调整：\x03%s\x01；输入 \x03!ast \x01查看或投票恢复默认.", status);
	}
	return Plugin_Continue;
}

public Action Timer_ShowJoinStatus(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) PrintGameplayStatus(client);
	return Plugin_Stop;
}

public Action Timer_EmptyServerReset(Handle timer)
{
	g_hEmptyResetTimer = null;
	if (CountHumanPlayers() == 0) {
		ResetSettings(false);
		PrintToServer("[Ast] Empty server detected; temporary gameplay overrides were reset.");
	}
	return Plugin_Stop;
}

public void OnMapStart() {
	if (g_hReminderTimer == null) g_hReminderTimer = CreateTimer(300.0, Timer_RemindOverrides, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	g_hReminderTimer = null;
	g_hEmptyResetTimer = null;
}

public void OnClientPutInServer(int client)
{
	if ( client > 0 && client < MaxClients) {
		if (!IsFakeClient(client)) {
			if (g_hEmptyResetTimer != null) {
				delete g_hEmptyResetTimer;
				g_hEmptyResetTimer = null;
			}
			CreateTimer(5.0, Timer_ShowJoinStatus, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void OnClientDisconnect(int client)
{
	bool wasHuman = client > 0 && client < MaxClients && IsClientConnected(client) && !IsFakeClient(client);
	if (wasHuman) {
		if (g_hEmptyResetTimer != null) delete g_hEmptyResetTimer;
		g_hEmptyResetTimer = CreateTimer(10.0, Timer_EmptyServerReset, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

stock bool isSurvivor(int client) {
	return IsClientAndInGame(client) && GetClientTeam(client) == TEAM_SURVIVORS;
}
