// Presentation only. Feature plugins own validation, commands and persistence.
static char g_mapMenuMap[MAXPLAYERS + 1][64];

bool MapMenu_Native(const char[] name)
{
	return GetFeatureStatus(FeatureType_Native, name) == FeatureStatus_Available;
}

Action CommandMapMenu(int client, int args)
{
	if (client == 0) ReplyToCommand(client, "%t", "MapMenuInGame");
	else ShowMapMenu(client);
	return Plugin_Handled;
}

void MapMenu_AddToggle(Menu menu, int client, const char[] key, const char[] label, bool active, bool saved, bool intro = false)
{
	char text[256], title[96], now[48], next[48];
	FormatEx(title, sizeof(title), "%T", label, client);
	FormatEx(now, sizeof(now), "%T", intro ? (active ? "MapMenuAlwaysSkip" : "MapMenuSkipCount") : (active ? "MapMenuAllowed" : "MapMenuBlocked"), client);
	FormatEx(next, sizeof(next), "%T", intro ? (saved ? "MapMenuAlwaysSkip" : "MapMenuSkipCount") : (saved ? "MapMenuAllowed" : "MapMenuBlocked"), client);
	if (active != saved) FormatEx(text, sizeof(text), "%T", "MapMenuPending", client, title, now, next);
	else FormatEx(text, sizeof(text), "%T", "MapMenuCurrent", client, title, now);
	menu.AddItem(key, text);
}

void MapMenu_AddDisabled(Menu menu, int client, const char[] phrase)
{
	char text[256];
	FormatEx(text, sizeof(text), "%T", phrase, client);
	menu.AddItem("", text, ITEMDRAW_DISABLED);
}

void ShowMapMenu(int client)
{
	if (!IsClientInGame(client) || !CheckCommandAccess(client, "sm_mset", ADMFLAG_GENERIC)) return;
	if (!MapRules_Enabled())
	{
		PrintToChat(client, "%t", "MapMenuDisabled");
		return;
	}
	MapRules_CurrentMap(g_mapMenuMap[client], sizeof(g_mapMenuMap[]));
	Menu menu = new Menu(MapMenu_Handler);
	char status[128];
	FormatEx(status, sizeof(status), "%T", MapRules_IsLive() ? "MapMenuLive" : "MapMenuReady", client);
	menu.SetTitle("%T", "MapMenuTitle", client, g_mapMenuMap[client], status);
	if (MapMenu_Native("BossRules_GetStatic") && MapMenu_Native("BossRules_SetStatic"))
	{
		MapMenu_AddToggle(menu, client, "tank", "MapMenuTank", !BossRules_GetStatic(false), !BossRules_GetStatic(false, true));
		MapMenu_AddToggle(menu, client, "witch", "MapMenuWitch", !BossRules_GetStatic(true), !BossRules_GetStatic(true, true));
	}
	else MapMenu_AddDisabled(menu, client, "MapMenuBossMissing");
	if (MapMenu_Native("FinaleRules_CanEdit") && MapMenu_Native("FinaleRules_GetRound") && MapMenu_Native("FinaleRules_SetRound") && FinaleRules_CanEdit())
	{
		MapMenu_AddToggle(menu, client, "round1", "MapMenuWave1", FinaleRules_GetRound(0), FinaleRules_GetRound(0, true));
		MapMenu_AddToggle(menu, client, "round2", "MapMenuWave2", FinaleRules_GetRound(1), FinaleRules_GetRound(1, true));
		MapMenu_AddToggle(menu, client, "round3", "MapMenuWave3", FinaleRules_GetRound(2), FinaleRules_GetRound(2, true));
	}
	else if (L4D_IsMissionFinalMap()) MapMenu_AddDisabled(menu, client, "MapMenuFinaleUnavailable");
	if (MapMenu_Native("SkipIntro_IsOfficialForced") && MapMenu_Native("SkipIntro_GetAlways") && MapMenu_Native("SkipIntro_SetAlways"))
	{
		if (SkipIntro_IsOfficialForced()) MapMenu_AddDisabled(menu, client, "MapMenuOfficialIntro");
		else MapMenu_AddToggle(menu, client, "intro", "MapMenuIntro", SkipIntro_GetAlways(), SkipIntro_GetAlways(true), true);
	}
	else MapMenu_AddDisabled(menu, client, "MapMenuIntroMissing");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MapMenu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End) delete menu;
	else if (action == MenuAction_Select)
	{
		if (!IsClientInGame(client) || !CheckCommandAccess(client, "sm_mset", ADMFLAG_GENERIC) || !MapRules_Enabled()) return 0;
		char map[64], key[16];
		MapRules_CurrentMap(map, sizeof(map));
		if (!StrEqual(map, g_mapMenuMap[client])) return 0;
		menu.GetItem(item, key, sizeof(key));
		bool saved;
		if ((StrEqual(key, "tank") || StrEqual(key, "witch")) && MapMenu_Native("BossRules_GetStatic") && MapMenu_Native("BossRules_SetStatic"))
		{
			bool witch = StrEqual(key, "witch");
			saved = BossRules_SetStatic(witch, !BossRules_GetStatic(witch, true));
		}
		else if (StrContains(key, "round") == 0 && MapMenu_Native("FinaleRules_CanEdit") && MapMenu_Native("FinaleRules_GetRound") && MapMenu_Native("FinaleRules_SetRound") && FinaleRules_CanEdit())
		{
			int slot = StringToInt(key[5]) - 1;
			if (slot >= 0 && slot < 3) saved = FinaleRules_SetRound(slot, !FinaleRules_GetRound(slot, true));
		}
		else if (StrEqual(key, "intro") && MapMenu_Native("SkipIntro_IsOfficialForced") && MapMenu_Native("SkipIntro_GetAlways") && MapMenu_Native("SkipIntro_SetAlways") && !SkipIntro_IsOfficialForced())
			saved = SkipIntro_SetAlways(!SkipIntro_GetAlways(true));
		if (saved) PrintToChat(client, "%t", MapRules_IsLive() ? "MapMenuSavedNext" : "MapMenuSavedNow");
		else PrintToChat(client, "%t", "MapMenuSaveFailed");
		ShowMapMenu(client);
	}
	return 0;
}
