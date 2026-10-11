// Presentation only. Feature plugins own validation, commands and persistence.
static char g_mapMenuMap[MAXPLAYERS + 1][64];

bool MapMenu_Native(const char[] name)
{
	return GetFeatureStatus(FeatureType_Native, name) == FeatureStatus_Available;
}

Action CommandMapMenu(int client, int args)
{
	if (client == 0) ReplyToCommand(client, "[地图规则] 请在游戏内打开菜单。");
	else ShowMapMenu(client);
	return Plugin_Handled;
}

void MapMenu_AddToggle(Menu menu, const char[] key, const char[] label, bool active, bool saved, bool intro = false)
{
	char text[192], now[24], next[24];
	strcopy(now, sizeof(now), intro ? (active ? "始终跳过" : "按次数") : (active ? "允许" : "禁止"));
	strcopy(next, sizeof(next), intro ? (saved ? "始终跳过" : "按次数") : (saved ? "允许" : "禁止"));
	if (active != saved) FormatEx(text, sizeof(text), "%s：%s → 下轮%s", label, now, next);
	else FormatEx(text, sizeof(text), "%s：%s", label, now);
	menu.AddItem(key, text);
}

void ShowMapMenu(int client)
{
	if (!IsClientInGame(client) || !CheckCommandAccess(client, "sm_mset", ADMFLAG_GENERIC)) return;
	if (!MapRules_Enabled())
	{
		PrintToChat(client, "[地图规则] 当前模式未启用 map_rules.cfg。");
		return;
	}
	MapRules_CurrentMap(g_mapMenuMap[client], sizeof(g_mapMenuMap[]));
	Menu menu = new Menu(MapMenu_Handler);
	menu.SetTitle("地图规则：%s\n%s", g_mapMenuMap[client], MapRules_IsLive() ? "已开局，修改下轮生效" : "修改本轮生效并保存");
	if (MapMenu_Native("BossRules_GetStatic") && MapMenu_Native("BossRules_SetStatic"))
	{
		MapMenu_AddToggle(menu, "tank", "路程 Tank", !BossRules_GetStatic(false), !BossRules_GetStatic(false, true));
		MapMenu_AddToggle(menu, "witch", "路程 Witch", !BossRules_GetStatic(true), !BossRules_GetStatic(true, true));
	}
	else menu.AddItem("", "路程 Boss：插件未加载", ITEMDRAW_DISABLED);
	if (MapMenu_Native("FinaleRules_CanEdit") && MapMenu_Native("FinaleRules_GetRound") && MapMenu_Native("FinaleRules_SetRound") && FinaleRules_CanEdit())
	{
		MapMenu_AddToggle(menu, "round1", "救援 Tank 第1轮", FinaleRules_GetRound(0), FinaleRules_GetRound(0, true));
		MapMenu_AddToggle(menu, "round2", "救援 Tank 第2轮", FinaleRules_GetRound(1), FinaleRules_GetRound(1, true));
		MapMenu_AddToggle(menu, "round3", "救援 Tank 第3轮以后", FinaleRules_GetRound(2), FinaleRules_GetRound(2, true));
	}
	else if (L4D_IsMissionFinalMap()) menu.AddItem("", "救援轮次：沿用原规则，暂不支持编辑", ITEMDRAW_DISABLED);
	if (MapMenu_Native("SkipIntro_IsOfficialForced") && MapMenu_Native("SkipIntro_GetAlways") && MapMenu_Native("SkipIntro_SetAlways"))
	{
		if (SkipIntro_IsOfficialForced()) menu.AddItem("", "开场动画：始终跳过（官图开关）", ITEMDRAW_DISABLED);
		else MapMenu_AddToggle(menu, "intro", "开场动画", SkipIntro_GetAlways(), SkipIntro_GetAlways(true), true);
	}
	else menu.AddItem("", "开场动画：插件未加载", ITEMDRAW_DISABLED);
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
		if (saved) PrintToChat(client, "[地图规则] 已保存；%s，重开后保持。", MapRules_IsLive() ? "下轮生效" : "本轮生效");
		else PrintToChat(client, "[地图规则] 未能修改，请确认功能可用并检查服务器日志。");
		ShowMapMenu(client);
	}
	return 0;
}
