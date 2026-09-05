#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <left4dhooks>
#undef REQUIRE_PLUGIN
#include <profile_controller>
#include <wave_spawner>

#define MENU_DISPLAY_TIME		15

#define TEAM_SURVIVORS          2

int tempTankDmg = -1;
int tempTankBhop = -1;
int tempTankRock = -1;
int tempMorePills = -1;
int tempKillMapPills = -1;
int tempRatioDamage = -1;
int tempRehealth = -1;
int tempReammo = -1;
int tempSIDamage = -1;
int pendingMobLimit = -1;
int g_iOverrideMask;
int g_iSlotOverrideMask[5];
int g_iSlotOverride[5][17];
int g_iPendingSlot;
Handle g_hEmptyResetTimer;
Handle g_hReminderTimer;

ConVar hRehealth;
ConVar hReammo;

Handle g_hVote;
int g_iVoteInitiator;

ConVar hDmgThreshold;
ConVar hRatioDamage;

public Plugin myinfo =
{
	name = "Coop Challenge",
	author = "海洋空氣, norths7ar",
	description = "Difficulty Controller for Coop.",
	version = "2.7-integration",
	url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

public void OnPluginStart()
{
	LoadTranslations("challenge.phrases");
	RegConsoleCmd("sm_tz", challengeRequest, "Open the difficulty menu");
	RegConsoleCmd("sm_ast", challengeRequest, "Open the Ast gameplay menu");
	RegConsoleCmd("sm_info", Command_Info, "Show current Coop status");
	RegAdminCmd("sm_reset", ResetSettingsCommand, ADMFLAG_CONFIG, "Clear temporary overrides and restore the baseline");
	HookEvent("player_team", OnChangeTeam, EventHookMode_Post);

	hRehealth = FindConVar("kill_rewards_health_enable");
	hReammo = FindConVar("kill_rewards_ammo_enable");
	hDmgThreshold = FindConVar("si_damage_base");
	hRatioDamage = FindConVar("si_damage_ratio_enable");

	g_hReminderTimer = CreateTimer(300.0, Timer_RemindOverrides, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	ClearAllSlotOverrides();
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	// 出门输出特感刷新参数
	float fTimerCurrent = GetConVarFloat(FindConVar("wave_interval"));
	int iLimitCurrent = GetConVarInt(FindConVar("wave_size"));
	PrintToChatAll("\x04[Ast] \x01%t", "WaveStart", fTimerCurrent, iLimitCurrent);
}

public Action challengeRequest(int client, int args)
{
	if (client) {
		drawPanel(client, 0);
	}
	return Plugin_Handled;
}

public Action Command_Info(int client, int args)
{
	if (client > 0 && IsClientInGame(client))
	{
		PrintGameplayStatus(client);
		PrintOverrideDetails(client);
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
	GetGameplayStatus(client, status, sizeof(status));
	char title[128]; FormatEx(title, sizeof(title), "%T", "MainTitle", client, status); SetMenuTitle(menu, title);
	SetMenuExitButton(menu, true);

	FormatEx(buffer, sizeof(buffer), "%T", "TankBhop", client); AddNamedToggleMenuItem(menu, "tank_bhop", buffer, GetConVarBool(FindConVar("ai_tank_bhop")));
	FormatEx(buffer, sizeof(buffer), "%T", "TankRock", client); AddNamedToggleMenuItem(menu, "tank_rock", buffer, GetConVarBool(FindConVar("ai_tank_rock")));
	FormatEx(buffer, sizeof(buffer), "%T", "TankDamageMenu", client, GetConVarInt(FindConVar("vs_tank_damage")));
	AddMenuItem(menu, "tank_damage", buffer);
	FormatEx(buffer, sizeof(buffer), "%T", "SIWavesMenu", client); AddMenuItem(menu, "si", buffer);
	FormatEx(buffer, sizeof(buffer), "%T", "SIDamageMenu", client, GetConVarInt(hDmgThreshold));
	AddMenuItem(menu, "si_damage", buffer);
	FormatEx(buffer, sizeof(buffer), "%T", "RatioDamageMenu", client); AddNamedToggleMenuItem(menu, "ratio_damage", buffer, GetConVarBool(hRatioDamage));
	FormatEx(buffer, sizeof(buffer), "%T", "RehealthMenu", client); AddNamedToggleMenuItem(menu, "rehealth", buffer, GetConVarBool(hRehealth));
	FormatEx(buffer, sizeof(buffer), "%T", "ReammoMenu", client); AddNamedToggleMenuItem(menu, "reammo", buffer, GetConVarBool(hReammo));
	ConVar mobLimit = FindConVar("mob_spawn_limit_enabled");
	if (mobLimit != null) { FormatEx(buffer, sizeof(buffer), "%T", "FiniteHordesMenu", client); AddNamedToggleMenuItem(menu, "mob_limit", buffer, mobLimit.BoolValue); }
	else { FormatEx(buffer, sizeof(buffer), "%T", "FiniteHordesUnavailable", client); AddMenuItem(menu, "mob_limit", buffer, ITEMDRAW_DISABLED); }
	FormatEx(buffer, sizeof(buffer), "%T", "ExtraPillsMenu", client); AddMenuItem(menu, "pills", buffer);
	FormatEx(buffer, sizeof(buffer), "%T", "ResetMenu", client); AddMenuItem(menu, "reset", buffer);

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
				PrintToChat(client, "\x04[Ast] \x01%t", "SIDamageSoloOnly");
				drawPanel(client, 0);
			}
		} else if (StrEqual(item, "ratio_damage")) {
			if (!IsClientSurvivor(client, true) || CountHumanSurvivors() != 1 || GetDifficulty() != 1) {
				PrintToChat(client, "\x04[Ast] \x01%t", "RatioDamageSoloOnly");
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
		} else if (StrEqual(item, "mob_limit")) {
			ConVar mobLimit = FindConVar("mob_spawn_limit_enabled");
			if (mobLimit == null) PrintToChat(client, "\x04[Ast] \x01%t", "FiniteHordesPluginUnavailable");
			else TZ_CallVote(client, 16, !mobLimit.BoolValue);
			drawPanel(client, 0);
		} else if (StrEqual(item, "pills")) {
			Menu_MorePills(client, false);
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
	char title[64];
	FormatEx(title, sizeof(title), "%T", "TankDamageTitle", client);
	SetMenuTitle(menu, title);
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
		ApplyGameplaySetting(target, value, true, GetCurrentProfile());
		return;
	}

	if ( IsNewBuiltinVoteAllowed() ) {
		g_iPendingSlot = GetCurrentProfile();
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
		g_iVoteInitiator = client;

		switch (target) {
			case 1: { // Tank 伤害
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteTankDamage", client, value);
				tempTankDmg = value;
				SetBuiltinVoteResultCallback(g_hVote, TankDmgVoteResultHandler);
			}
			case 2: { // Tank 连跳
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableTankBhop" : "VoteDisableTankBhop", client);
				tempTankBhop = value;
				SetBuiltinVoteResultCallback(g_hVote, TankBhopVoteResultHandler);
			}
			case 3: { // Tank 石头
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableTankRock" : "VoteDisableTankRock", client);
				tempTankRock = value;
				SetBuiltinVoteResultCallback(g_hVote, TankRockVoteResultHandler);
			}
			case 7: { // 额外发药
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableExtraPills" : "VoteDisableExtraPills", client);
				tempMorePills = value;
				SetBuiltinVoteResultCallback(g_hVote, MorePillsVoteResultHandler);
			}
			case 8: { // 删除地图药
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteRemoveMapPills" : "VoteKeepMapPills", client);
				tempKillMapPills = value;
				SetBuiltinVoteResultCallback(g_hVote, KillMapPillsVoteResultHandler);
			}
			case 11: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableRatioDamage" : "VoteDisableRatioDamage", client);
				tempRatioDamage = value;
				SetBuiltinVoteResultCallback(g_hVote, RatioDamageVoteResultHandler);
			}
			case 12: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableRehealth" : "VoteDisableRehealth", client);
				tempRehealth = value;
				SetBuiltinVoteResultCallback(g_hVote, RehealthVoteResultHandler);
			}
			case 13: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableReammo" : "VoteDisableReammo", client);
				tempReammo = value;
				SetBuiltinVoteResultCallback(g_hVote, ReammoVoteResultHandler);
			}
			case 14: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteResetAll", client);
				SetBuiltinVoteResultCallback(g_hVote, ResetVoteResultHandler);
			}
			case 15: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteSIDamage", client, value);
				tempSIDamage = value;
				SetBuiltinVoteResultCallback(g_hVote, SIDamageVoteResultHandler);
			}
			case 16: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableFiniteHordes" : "VoteDisableFiniteHordes", client);
				pendingMobLimit = value;
				SetBuiltinVoteResultCallback(g_hVote, MobLimitVoteResultHandler);
			}
		}

		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, MENU_DISPLAY_TIME);
		FakeClientCommand(client, "Vote Yes");
	}
}

void ApplyGameplaySetting(int target, int value, bool announce, int slot)
{
	if (slot < 1 || slot > 4) slot = GetCurrentProfile();
	if (slot < 1 || slot > 4 || target < 1 || target > 16) return;
	g_iSlotOverride[slot][target] = value;
	g_iSlotOverrideMask[slot] |= (1 << target);
	if (slot != GetCurrentProfile()) return;
	g_iOverrideMask = g_iSlotOverrideMask[slot];
	switch (target) {
		case 1: { tempTankDmg = value; SetConVarInt(FindConVar("vs_tank_damage"), value); }
		case 2: { tempTankBhop = value; SetConVarInt(FindConVar("ai_tank_bhop"), value); }
		case 3: { tempTankRock = value; SetConVarInt(FindConVar("ai_tank_rock"), value); }
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
		case 16: {
			ConVar mobLimit = FindConVar("mob_spawn_limit_enabled");
			if (mobLimit == null) return;
			mobLimit.IntValue = value;
		}
		default: return;
	}

	if (announce) {
		PrintToChatAll("\x04[Ast] \x01%t", "SoloOverrideApplied");
	}
}

void ApplyVoteSetting(int target, int value)
{
	int slot = g_iPendingSlot;
	if (slot < 1 || slot > 4) slot = GetCurrentProfile();
	ApplyGameplaySetting(target, value, false, slot);
	g_iPendingSlot = 0;
}

void ReapplyGameplayOverrides()
{
	int slot = GetCurrentProfile();
	if (slot < 1 || slot > 4) return;
	SyncTempMirrors(slot);
	g_iOverrideMask = g_iSlotOverrideMask[slot];
	for (int target = 1; target <= 16; target++)
	{
		if ((g_iOverrideMask & (1 << target)) != 0)
		{
			ApplyGameplaySetting(target, g_iSlotOverride[slot][target], false, slot);
		}
	}
}

void SyncTempMirrors(int slot)
{
	tempTankDmg = (g_iSlotOverrideMask[slot] & (1 << 1)) ? g_iSlotOverride[slot][1] : -1;
	tempTankBhop = (g_iSlotOverrideMask[slot] & (1 << 2)) ? g_iSlotOverride[slot][2] : -1;
	tempTankRock = (g_iSlotOverrideMask[slot] & (1 << 3)) ? g_iSlotOverride[slot][3] : -1;
	tempMorePills = (g_iSlotOverrideMask[slot] & (1 << 7)) ? g_iSlotOverride[slot][7] : -1;
	tempKillMapPills = (g_iSlotOverrideMask[slot] & (1 << 8)) ? g_iSlotOverride[slot][8] : -1;
	tempRatioDamage = (g_iSlotOverrideMask[slot] & (1 << 11)) ? g_iSlotOverride[slot][11] : -1;
	tempRehealth = (g_iSlotOverrideMask[slot] & (1 << 12)) ? g_iSlotOverride[slot][12] : -1;
	tempReammo = (g_iSlotOverrideMask[slot] & (1 << 13)) ? g_iSlotOverride[slot][13] : -1;
	tempSIDamage = (g_iSlotOverrideMask[slot] & (1 << 15)) ? g_iSlotOverride[slot][15] : -1;
}

public void TankDmgVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayVotePassPhrase(vote, "VotePassTankDamage");
		ApplyVoteSetting(1, tempTankDmg);
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
				DisplayVotePassPhrase(vote, "VotePassTankBhop");
		ApplyVoteSetting(2, tempTankBhop);
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
				DisplayVotePassPhrase(vote, "VotePassTankRock");
		ApplyVoteSetting(3, tempTankRock);
				return;
			}
		}
	}
	tempTankRock = GetConVarInt(FindConVar("ai_tank_rock"));
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

public void MorePillsVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++) {
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
				DisplayVotePassPhrase(vote, tempMorePills ? "VotePassEnableExtraPills" : "VotePassDisableExtraPills");
		ApplyVoteSetting(7, tempMorePills);
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
				DisplayVotePassPhrase(vote, tempKillMapPills ? "VotePassRemoveMapPills" : "VotePassKeepMapPills");
		ApplyVoteSetting(8, tempKillMapPills);
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
		DisplayVotePassPhrase(vote, "VotePassRatioDamage");
		ApplyVoteSetting(11, tempRatioDamage);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void RehealthVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayVotePassPhrase(vote, "VotePassRehealth");
		ApplyVoteSetting(12, tempRehealth);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void ReammoVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayVotePassPhrase(vote, "VotePassReammo");
		ApplyVoteSetting(13, tempReammo);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void ResetVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayVotePassPhrase(vote, "VotePassResetAll");
		ResetSettings(true);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void SIDamageVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayVotePassPhrase(vote, "VotePassSIDamage");
		ApplyVoteSetting(15, tempSIDamage);
		return;
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void MobLimitVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (DidVotePass(num_votes, num_items, item_info)) {
		DisplayVotePassPhrase(vote, "VotePassFiniteHordes");
		ApplyVoteSetting(16, pendingMobLimit);
		pendingMobLimit = -1;
		return;
	}
	pendingMobLimit = -1;
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action) {
		case BuiltinVoteAction_End: {
			g_iPendingSlot = 0;
			g_iVoteInitiator = 0;
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
			return;
		}
		case BuiltinVoteAction_Cancel: {
			g_iPendingSlot = 0;
			pendingMobLimit = -1;
			DisplayBuiltinVoteFail( vote, view_as<BuiltinVoteFailReason>(param1) );
			return;
		}
	}
	return;
}

void DisplayVotePassPhrase(Handle vote, const char[] phrase)
{
	char message[128];
	int languageClient = IsClientAndInGame(g_iVoteInitiator) ? g_iVoteInitiator : LANG_SERVER;
	FormatEx(message, sizeof(message), "%T", phrase, languageClient);
	DisplayBuiltinVotePass(vote, message);
}


public Action Menu_SITimer(int client, int args)
{
	Menu menu = new Menu(Menu_SITimerHandler);
	ConVar waveTimer = FindConVar("wave_interval");
	ConVar waveLimit = FindConVar("wave_size");
	char title[96];
	if (waveTimer != null && waveLimit != null) {
		FormatEx(title, sizeof(title), "%T", "SIWaveTitle", client, waveTimer.FloatValue, waveLimit.IntValue);
	} else {
		FormatEx(title, sizeof(title), "%T", "SIWaveUnavailableTitle", client);
	}
	menu.SetTitle(title);
	menu.ExitBackButton = true;
	char instruction[64];
	FormatEx(instruction, sizeof(instruction), "%T", "SIWaveInstruction", client);
	menu.AddItem("", instruction, ITEMDRAW_DISABLED);
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
	char title[64];
	FormatEx(title, sizeof(title), "%T", "SIDamageTitle", client);
	SetMenuTitle(menu, title);
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
	tempMorePills = -1;
	tempKillMapPills = -1;
	tempRatioDamage = -1;
	tempRehealth = -1;
	tempReammo = -1;
	tempSIDamage = -1;
	pendingMobLimit = -1;
	ClearAllSlotOverrides();
	if (CanUseWaveSpawner()) WaveSpawner_ResetAllOverrides();
	else LogError("[Ast] wave_spawner.smx is not available; wave overrides were not reset.");
	if (CanUseProfileController()) ProfileController_Reapply();
	else LogError("[Ast] profile_controller.smx is not available; profile baseline was not reapplied.");
	if (announce) {
		PrintToChatAll("\x04[Ast] \x01%t", "ResetComplete");
	}
}

public void ProfileController_OnProfileApplied(int profile)
{
	ReapplyGameplayOverrides();
}

int GetCurrentProfile()
{
	if (CanUseProfileController()) return ProfileController_GetCurrentProfile();
	ConVar profile = FindConVar("profile_current");
	return profile == null ? 1 : profile.IntValue;
}

bool CanUseProfileController()
{
	return LibraryExists("profile_controller") && GetFeatureStatus(FeatureType_Native, "ProfileController_GetCurrentProfile") == FeatureStatus_Available;
}

bool CanUseWaveSpawner()
{
	return LibraryExists("wave_spawner") && GetFeatureStatus(FeatureType_Native, "WaveSpawner_ResetAllOverrides") == FeatureStatus_Available;
}

void ClearAllSlotOverrides()
{
	for (int slot = 1; slot <= 4; slot++)
	{
		g_iSlotOverrideMask[slot] = 0;
		for (int target = 0; target <= 16; target++)
		{
			g_iSlotOverride[slot][target] = -1;
		}
	}
}

public Action Menu_MorePills(int client, int args)
{
	if (FindConVar("ast_pills_map_kill") == null) {
		PrintToChat(client, "\x04[Ast] \x01%t", "PillsPluginUnavailable");
		drawPanel(client, 0);
		return Plugin_Handled;
	}

	// 开关，删除地图药
	Handle menu = CreateMenu(Menu_MorePillsHandler);
	char buffer[64];
	FormatEx(buffer, sizeof(buffer), "%T", "ExtraPillsTitle", client);
	SetMenuTitle(menu, buffer);
	SetMenuExitBackButton(menu, true);

	FormatEx(buffer, sizeof(buffer), "%T", "AutomaticPills", client);
	AddToggleMenuItem(menu, buffer, GetConVarBool(FindConVar("ast_pills_enabled")));
	FormatEx(buffer, sizeof(buffer), "%T", "RemoveMapPills", client);
	AddToggleMenuItem(menu, buffer, GetConVarBool(FindConVar("ast_pills_map_kill")));

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
		CreateTimer(1.0, Timer_SetTankConVar);
	}
	return Plugin_Continue;
}

public Action Timer_SetTankConVar(Handle timer)
{
	int slot = GetCurrentProfile();
	if (slot >= 1 && slot <= 4 && (g_iSlotOverrideMask[slot] & (1 << 2)) != 0) {
		SetConVarInt(FindConVar("ai_tank_bhop"), g_iSlotOverride[slot][2]);
	}
	if (slot >= 1 && slot <= 4 && (g_iSlotOverrideMask[slot] & (1 << 3)) != 0) {
		SetConVarInt(FindConVar("ai_tank_rock"), g_iSlotOverride[slot][3]);
	}
	return Plugin_Stop;
}

stock bool IsClientAndInGame(int index) {
	return (index > 0 && index <= MaxClients && IsClientInGame(index));
}

public bool IsClientSurvivor(int client, bool isMenu) {
	if ( !IsClientAndInGame(client) ) return false;
	if (!isSurvivor(client)) {
		if (isMenu) {
			PrintToChat(client, "\x04[Ast] \x01%t", "SurvivorsOnly");
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
	if (!CanReadProfileDefaults()) return -1;
	int count;
	for (int target = 1; target <= 16; target++)
		if (DiffersFromProfile(GetChallengeSetting(target))) count++;
	for (int field = 0; field < 9; field++)
		if (DiffersFromProfile(GetWaveSetting(field))) count++;
	return count;
}

bool CanReadProfileDefaults()
{
	return CanUseProfileController() && GetCurrentProfile() > 0
		&& GetFeatureStatus(FeatureType_Native, "ProfileController_GetDefaultValue") == FeatureStatus_Available;
}

bool DiffersFromProfile(ConVar cvar)
{
	if (cvar == null || !CanReadProfileDefaults()) return false;
	char name[64];
	cvar.GetName(name, sizeof(name));
	float baseline;
	return ProfileController_GetDefaultValue(name, baseline) && FloatAbs(cvar.FloatValue - baseline) > 0.0001;
}

ConVar GetChallengeSetting(int target)
{
	switch (target)
	{
		case 1: return FindConVar("vs_tank_damage");
		case 2: return FindConVar("ai_tank_bhop");
		case 3: return FindConVar("ai_tank_rock");
		case 7: return FindConVar("ast_pills_enabled");
		case 8: return FindConVar("ast_pills_map_kill");
		case 11: return hRatioDamage;
		case 12: return hRehealth;
		case 13: return hReammo;
		case 15: return hDmgThreshold;
		case 16: return FindConVar("mob_spawn_limit_enabled");
	}
	return null;
}

ConVar GetWaveSetting(int field)
{
	static char names[][] = {"wave_interval", "wave_size", "wave_hunter_limit", "wave_smoker_limit", "wave_boomer_limit", "wave_spitter_limit", "wave_jockey_limit", "wave_charger_limit", "wave_preferred_direction"};
	return FindConVar(names[field]);
}

void GetGameplayStatus(int client, char[] buffer, int maxlen)
{
	int difficulty = GetDifficulty();
	if (difficulty < 1 || difficulty > 4) difficulty = CountHumanSurvivors();
	int count = CountOverrides();
	if (count < 0) FormatEx(buffer, maxlen, "%T", "InfoDefaultsUnavailable", client);
	else FormatEx(buffer, maxlen, "%T", "GameplayStatus", client, difficulty, count);
}

void PrintGameplayStatus(int client)
{
	ConVar waveTimer = FindConVar("wave_interval");
	ConVar waveLimit = FindConVar("wave_size");
	if (waveTimer != null && waveLimit != null) {
		PrintToChat(client, "\x04[Ast] \x01%t", "InfoHeader", GetDifficulty(), waveTimer.FloatValue, waveLimit.IntValue);
	} else {
		PrintToChat(client, "\x04[Ast] \x01%t", "InfoWaveUnavailable");
	}
	PrintOverrideSummary(client);
}

void PrintOverrideSummary(int client)
{
	int count = CountOverrides();
	if (count < 0) PrintToChat(client, "\x04[Ast] \x01%t", "InfoDefaultsUnavailable");
	else if (count == 0) PrintToChat(client, "\x04[Ast] \x01%t", "InfoNoOverrides");
	else PrintToChat(client, "\x04[Ast] \x01%t", "InfoOverridesSummary", count);
}

void PrintOverrideDetails(int client)
{
	for (int target = 1; target <= 16; target++)
	{
		ConVar setting = GetChallengeSetting(target);
		if (!DiffersFromProfile(setting)) continue;
		char value[32];
		if (IsBooleanChallengeTarget(target))
		{
			Format(value, sizeof(value), "%T", setting.BoolValue ? "InfoEnabled" : "InfoDisabled", client);
		}
		else
		{
			setting.GetString(value, sizeof(value));
		}
		char phrase[32];
		GetChallengePhrase(target, phrase, sizeof(phrase));
		PrintToChat(client, "\x04[Ast] \x01%t", phrase, value);
	}

	for (int field = 0; field < 9; field++)
	{
		ConVar setting = GetWaveSetting(field);
		if (!DiffersFromProfile(setting)) continue;
		char value[32];
		setting.GetString(value, sizeof(value));
		char phrase[32];
		GetWavePhrase(field, phrase, sizeof(phrase));
		PrintToChat(client, "\x04[Ast] \x01%t", phrase, value);
	}
}

bool IsBooleanChallengeTarget(int target)
{
	return target == 2 || target == 3 || target == 7 || target == 8
		|| target == 11 || target == 12 || target == 13 || target == 16;
}

void GetChallengePhrase(int target, char[] phrase, int maxlen)
{
	switch (target)
	{
		case 1: strcopy(phrase, maxlen, "InfoTankDamage");
		case 2: strcopy(phrase, maxlen, "InfoTankBhop");
		case 3: strcopy(phrase, maxlen, "InfoTankRock");
		case 7: strcopy(phrase, maxlen, "InfoExtraPills");
		case 8: strcopy(phrase, maxlen, "InfoMapPills");
		case 11: strcopy(phrase, maxlen, "InfoRatioDamage");
		case 12: strcopy(phrase, maxlen, "InfoRehealth");
		case 13: strcopy(phrase, maxlen, "InfoReammo");
		case 15: strcopy(phrase, maxlen, "InfoSIDamage");
		case 16: strcopy(phrase, maxlen, "InfoMobLimit");
		default: strcopy(phrase, maxlen, "InfoNoOverrides");
	}
}

void GetWavePhrase(int field, char[] phrase, int maxlen)
{
	static char phrases[][] = {"InfoWaveInterval", "InfoWaveSize", "InfoHunterLimit", "InfoSmokerLimit", "InfoBoomerLimit", "InfoSpitterLimit", "InfoJockeyLimit", "InfoChargerLimit", "InfoWaveDirection"};
	strcopy(phrase, maxlen, phrases[field]);
}

public Action Timer_RemindOverrides(Handle timer)
{
	if (CountOverrides() > 0) {
		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsClientInGame(client) || IsFakeClient(client)) continue;
			char status[64];
			GetGameplayStatus(client, status, sizeof(status));
			PrintToChat(client, "\x04[Ast] \x01%t", "OverrideReminder", status);
		}
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
