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

enum
{
	Setting_TankDamage = 1,
	Setting_TankBhop = 2,
	Setting_TankRock = 3,
	Setting_ExtraPills = 7,
	Setting_RemoveMapPills = 8,
	Setting_RatioDamage = 11,
	Setting_KillHealth = 12,
	Setting_KillAmmo = 13,
	Setting_Reset = 14,
	Setting_SIDamage = 15,
	Setting_FiniteHordes = 16,
	Setting_Count
};

// Applied overrides belong to their player-count profile, not to an active vote.
int g_iSlotOverrideMask[5];
int g_iSlotOverride[5][Setting_Count];

// Captured when voting starts; profile changes must not overwrite these values.
int g_iPendingTarget;
int g_iPendingValue;
int g_iPendingSlot;
Handle g_hEmptyResetTimer;

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
	version = "2.8.1-integration",
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
	ConVar mobLimit = FindConVar("l4d2_heq_enabled");
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
			RequestGameplaySetting(client, Setting_TankBhop, !GetConVarBool(FindConVar("ai_tank_bhop")));
		} else if (StrEqual(item, "tank_rock")) {
			RequestGameplaySetting(client, Setting_TankRock, !GetConVarBool(FindConVar("ai_tank_rock")));
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
			RequestGameplaySetting(client, Setting_RatioDamage, !GetConVarBool(hRatioDamage));
			drawPanel(client, 0);
		} else if (StrEqual(item, "rehealth")) {
			if (!IsClientSurvivor(client, true)) {
				drawPanel(client, 0);
				return 1;
			}
			RequestGameplaySetting(client, Setting_KillHealth, !GetConVarBool(hRehealth));
			drawPanel(client, 0);
		} else if (StrEqual(item, "reammo")) {
			if (!IsClientSurvivor(client, true)) {
				drawPanel(client, 0);
				return 1;
			}
			RequestGameplaySetting(client, Setting_KillAmmo, !GetConVarBool(hReammo));
			drawPanel(client, 0);
		} else if (StrEqual(item, "mob_limit")) {
			ConVar mobLimit = FindConVar("l4d2_heq_enabled");
			if (mobLimit == null) PrintToChat(client, "\x04[Ast] \x01%t", "FiniteHordesPluginUnavailable");
			else RequestGameplaySetting(client, Setting_FiniteHordes, !mobLimit.BoolValue);
			drawPanel(client, 0);
		} else if (StrEqual(item, "pills")) {
			Menu_MorePills(client, false);
		} else if (StrEqual(item, "reset")) {
			RequestGameplaySetting(client, Setting_Reset, 0);
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
	if (action == MenuAction_End) {
		delete menu;
		return 1;
	}

	if (action == MenuAction_Select)
	{
		if (0 <= param < sizeof(g_tankDamages))
		{
			RequestGameplaySetting(client, Setting_TankDamage, g_tankDamages[param]);
		}
		drawPanel(client, 0);
	}
	else if (action == MenuAction_Cancel)
	{
		drawPanel(client, 0);
	}
	return 1;
}


public void RequestGameplaySetting(int client, int target, int value)
{
	if ( !IsClientSurvivor(client, true) ) return;
	if (CountHumanSurvivors() == 1) {
		ApplyGameplaySetting(target, value, true, GetCurrentProfile());
		return;
	}

	if ( IsNewBuiltinVoteAllowed() ) {
		g_iPendingTarget = target;
		g_iPendingValue = value;
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
			case Setting_TankDamage: { // Tank 伤害
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteTankDamage", client, value);
			}
			case Setting_TankBhop: { // Tank 连跳
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableTankBhop" : "VoteDisableTankBhop", client);
			}
			case Setting_TankRock: { // Tank 石头
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableTankRock" : "VoteDisableTankRock", client);
			}
			case Setting_ExtraPills: { // 额外发药
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableExtraPills" : "VoteDisableExtraPills", client);
			}
			case Setting_RemoveMapPills: { // 删除地图药
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteRemoveMapPills" : "VoteKeepMapPills", client);
			}
			case Setting_RatioDamage: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableRatioDamage" : "VoteDisableRatioDamage", client);
			}
			case Setting_KillHealth: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableRehealth" : "VoteDisableRehealth", client);
			}
			case Setting_KillAmmo: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableReammo" : "VoteDisableReammo", client);
			}
			case Setting_Reset: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteResetAll", client);
			}
			case Setting_SIDamage: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", "VoteSIDamage", client, value);
			}
			case Setting_FiniteHordes: {
				FormatEx(sBuffer, sizeof(sBuffer), "%T", value ? "VoteEnableFiniteHordes" : "VoteDisableFiniteHordes", client);
			}
		}

		SetBuiltinVoteResultCallback(g_hVote, GameplayVoteResultHandler);
		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, MENU_DISPLAY_TIME);
		FakeClientCommand(client, "Vote Yes");
	}
}

void ApplyGameplaySetting(int target, int value, bool announce, int slot)
{
	if (slot < 1 || slot > 4) slot = GetCurrentProfile();
	if (slot < 1 || slot > 4 || target < 1 || target >= Setting_Count) return;
	if (target == Setting_Reset) {
		ResetSettings(true);
		return;
	}

	ConVar setting = GetChallengeSetting(target);
	if (setting == null) return;
	g_iSlotOverride[slot][target] = value;
	g_iSlotOverrideMask[slot] |= (1 << target);
	if (slot != GetCurrentProfile()) return;
	if (target == Setting_SIDamage) setting.FloatValue = float(value);
	else setting.IntValue = value;

	if (announce) {
		PrintToChatAll("\x04[Ast] \x01%t", "SoloOverrideApplied");
	}
}

void ReapplyGameplayOverrides()
{
	int slot = GetCurrentProfile();
	if (slot < 1 || slot > 4) return;
	for (int target = 1; target < Setting_Count; target++)
	{
		if ((g_iSlotOverrideMask[slot] & (1 << target)) != 0)
		{
			ApplyGameplaySetting(target, g_iSlotOverride[slot][target], false, slot);
		}
	}
}

public void GameplayVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (!DidVotePass(num_votes, num_items, item_info)) {
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
		return;
	}

	int target = g_iPendingTarget;
	int value = g_iPendingValue;
	int slot = g_iPendingSlot;
	switch (target) {
		case Setting_TankDamage: DisplayVotePassPhrase(vote, "VotePassTankDamage");
		case Setting_TankBhop: DisplayVotePassPhrase(vote, "VotePassTankBhop");
		case Setting_TankRock: DisplayVotePassPhrase(vote, "VotePassTankRock");
		case Setting_ExtraPills: DisplayVotePassPhrase(vote, value ? "VotePassEnableExtraPills" : "VotePassDisableExtraPills");
		case Setting_RemoveMapPills: DisplayVotePassPhrase(vote, value ? "VotePassRemoveMapPills" : "VotePassKeepMapPills");
		case Setting_RatioDamage: DisplayVotePassPhrase(vote, "VotePassRatioDamage");
		case Setting_KillHealth: DisplayVotePassPhrase(vote, "VotePassRehealth");
		case Setting_KillAmmo: DisplayVotePassPhrase(vote, "VotePassReammo");
		case Setting_Reset: DisplayVotePassPhrase(vote, "VotePassResetAll");
		case Setting_SIDamage: DisplayVotePassPhrase(vote, "VotePassSIDamage");
		case Setting_FiniteHordes: DisplayVotePassPhrase(vote, "VotePassFiniteHordes");
	}
	ApplyGameplaySetting(target, value, false, slot);
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

void ClearPendingVote()
{
	g_iPendingTarget = 0;
	g_iPendingValue = 0;
	g_iPendingSlot = 0;
	g_iVoteInitiator = 0;
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action) {
		case BuiltinVoteAction_End: {
			ClearPendingVote();
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
			return;
		}
		case BuiltinVoteAction_Cancel: {
			ClearPendingVote();
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
	if (action == MenuAction_End) {
		delete menu;
		return 1;
	}
	if (action != MenuAction_Select && action != MenuAction_Cancel) return 1;
	if (!IsClientAndInGame(client)) return 1;

	if (!IsClientSurvivor(client, true)) {
		drawPanel(client, 0);
		return 1;
	}

	if (action == MenuAction_Select) {
		if (param < 0 || param >= sizeof(SIDamageOptions)) return 1;
		RequestGameplaySetting(client, Setting_SIDamage, SIDamageOptions[param]);
		drawPanel(client, 0);
	} else if (action == MenuAction_Cancel) {
		drawPanel(client, 0);
	}
	return 1;
}


public void ResetSettings(bool announce)
{
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
		for (int target = 0; target < Setting_Count; target++)
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
	if (action == MenuAction_End) {
		delete menu;
		return 1;
	}

	if (action == MenuAction_Select) {
		switch (param)
		{
			case 0: {
				bool bPillsEnabled = GetConVarBool(FindConVar("ast_pills_enabled"));
				RequestGameplaySetting(client, Setting_ExtraPills, !bPillsEnabled);
			}
			case 1: {
				bool bPillsMapKill = GetConVarBool(FindConVar("ast_pills_map_kill"));
				RequestGameplaySetting(client, Setting_RemoveMapPills, !bPillsMapKill);
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
	if (slot >= 1 && slot <= 4 && (g_iSlotOverrideMask[slot] & (1 << Setting_TankBhop)) != 0) {
		SetConVarInt(FindConVar("ai_tank_bhop"), g_iSlotOverride[slot][Setting_TankBhop]);
	}
	if (slot >= 1 && slot <= 4 && (g_iSlotOverrideMask[slot] & (1 << Setting_TankRock)) != 0) {
		SetConVarInt(FindConVar("ai_tank_rock"), g_iSlotOverride[slot][Setting_TankRock]);
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
	for (int target = 1; target < Setting_Count; target++)
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
		case Setting_TankDamage: return FindConVar("vs_tank_damage");
		case Setting_TankBhop: return FindConVar("ai_tank_bhop");
		case Setting_TankRock: return FindConVar("ai_tank_rock");
		case Setting_ExtraPills: return FindConVar("ast_pills_enabled");
		case Setting_RemoveMapPills: return FindConVar("ast_pills_map_kill");
		case Setting_RatioDamage: return hRatioDamage;
		case Setting_KillHealth: return hRehealth;
		case Setting_KillAmmo: return hReammo;
		case Setting_SIDamage: return hDmgThreshold;
		case Setting_FiniteHordes: return FindConVar("l4d2_heq_enabled");
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
	else if (count == 0) return;
	else PrintToChat(client, "\x04[Ast] \x01%t", "InfoOverridesSummary", count);
}

void PrintOverrideDetails(int client)
{
	for (int target = 1; target < Setting_Count; target++)
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
	return target == Setting_TankBhop || target == Setting_TankRock || target == Setting_ExtraPills || target == Setting_RemoveMapPills
		|| target == Setting_RatioDamage || target == Setting_KillHealth || target == Setting_KillAmmo || target == Setting_FiniteHordes;
}

void GetChallengePhrase(int target, char[] phrase, int maxlen)
{
	switch (target)
	{
		case Setting_TankDamage: strcopy(phrase, maxlen, "InfoTankDamage");
		case Setting_TankBhop: strcopy(phrase, maxlen, "InfoTankBhop");
		case Setting_TankRock: strcopy(phrase, maxlen, "InfoTankRock");
		case Setting_ExtraPills: strcopy(phrase, maxlen, "InfoExtraPills");
		case Setting_RemoveMapPills: strcopy(phrase, maxlen, "InfoMapPills");
		case Setting_RatioDamage: strcopy(phrase, maxlen, "InfoRatioDamage");
		case Setting_KillHealth: strcopy(phrase, maxlen, "InfoRehealth");
		case Setting_KillAmmo: strcopy(phrase, maxlen, "InfoReammo");
		case Setting_SIDamage: strcopy(phrase, maxlen, "InfoSIDamage");
		case Setting_FiniteHordes: strcopy(phrase, maxlen, "InfoMobLimit");
		default: strcopy(phrase, maxlen, "InfoNoOverrides");
	}
}

void GetWavePhrase(int field, char[] phrase, int maxlen)
{
	static char phrases[][] = {"InfoWaveInterval", "InfoWaveSize", "InfoHunterLimit", "InfoSmokerLimit", "InfoBoomerLimit", "InfoSpitterLimit", "InfoJockeyLimit", "InfoChargerLimit", "InfoWaveDirection"};
	strcopy(phrase, maxlen, phrases[field]);
}

// Called only when the shared advertisement rotation reaches this entry.
public Action Advertisements_OnDynamicChat(const char[] key, int client, char[] buffer, int maxlen)
{
    if (!StrEqual(key, "ast_overrides") || CountOverrides() <= 0) return Plugin_Continue;
    char status[64];
    GetGameplayStatus(client, status, sizeof(status));
    FormatEx(buffer, maxlen, "\x04[Ast] \x01%T", "OverrideReminder", client, status);
    return Plugin_Handled;
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

public void OnMapEnd()
{
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
