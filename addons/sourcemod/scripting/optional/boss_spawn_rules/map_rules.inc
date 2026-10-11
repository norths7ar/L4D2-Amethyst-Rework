// Static rules and commands belong to boss_spawn_rules, not the admin menu.
static bool g_staticRules[2];

void InitBossMapRules()
{
	MapRules_Init();
	RegAdminCmd("sm_setstatictank", CommandStaticRule, ADMFLAG_GENERIC, "本图禁用路程 Tank 并保存。");
	RegAdminCmd("sm_unsetstatictank", CommandStaticRule, ADMFLAG_GENERIC, "本图允许路程 Tank 并保存。");
	RegAdminCmd("sm_getstatictank", CommandStaticRule, ADMFLAG_GENERIC, "查询本图路程 Tank 规则。");
	RegAdminCmd("sm_setstaticwitch", CommandStaticRule, ADMFLAG_GENERIC, "本图禁用路程 Witch 并保存。");
	RegAdminCmd("sm_unsetstaticwitch", CommandStaticRule, ADMFLAG_GENERIC, "本图允许路程 Witch 并保存。");
	RegAdminCmd("sm_getstaticwitch", CommandStaticRule, ADMFLAG_GENERIC, "查询本图路程 Witch 规则。");
}

bool LoadBossMapRules()
{
	KeyValues rules = MapRules_Load();
	if (rules == null) return false;
	MapRules_CurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	g_staticRules[0] = MapRules_ReadInt(rules, g_sCurrentMap, "static_tank") != 0;
	g_staticRules[1] = MapRules_ReadInt(rules, g_sCurrentMap, "static_witch") != 0;
	delete rules;
	return true;
}

bool ReadStaticRule(const char[] map, bool witch, bool &value)
{
	KeyValues rules = MapRules_Load();
	if (rules == null) return false;
	value = MapRules_ReadInt(rules, map, witch ? "static_witch" : "static_tank") != 0;
	delete rules;
	return true;
}

bool GetStaticRule(const char[] map, bool witch)
{
	if (StrEqual(map, g_sCurrentMap, false)) return g_staticRules[witch ? 1 : 0];
	bool value;
	ReadStaticRule(map, witch, value);
	return value;
}

bool SaveStaticRule(bool witch, bool value)
{
	if (!MapRules_Enabled() || !MapRules_SaveInt(witch ? "static_witch" : "static_tank", value ? 1 : 0)) return false;
	if (!MapRules_IsLive())
	{
		g_staticRules[witch ? 1 : 0] = value;
		if (value)
		{
			if (witch) SetWitchPercent(0);
			else ApplyBossPercents(0, -1);
		}
		else
		{
			// Static maps have no usable cached ranges. Rebuild those ranges using
			// the original map bans and Witch avoidance before selecting a position.
			AdjustBossFlows(!witch, true);
		}
	}
	return true;
}

int Native_GetStaticRule(Handle plugin, int numParams)
{
	bool witch = GetNativeCell(1) != 0;
	if (GetNativeCell(2))
	{
		bool value;
		if (!ReadStaticRule(g_sCurrentMap, witch, value)) return g_staticRules[witch ? 1 : 0];
		return value;
	}
	return g_staticRules[witch ? 1 : 0];
}

int Native_SetStaticRule(Handle plugin, int numParams)
{
	return SaveStaticRule(GetNativeCell(1) != 0, GetNativeCell(2) != 0);
}

Action CommandStaticRule(int client, int args)
{
	if (!MapRules_Enabled())
	{
		ReplyToCommand(client, "[地图规则] 当前模式未启用 map_rules.cfg。");
		return Plugin_Handled;
	}
	char command[40];
	GetCmdArg(0, command, sizeof(command));
	bool witch = StrContains(command, "witch") >= 0;
	if (StrContains(command, "sm_get") == 0)
	{
		bool saved;
		if (!ReadStaticRule(g_sCurrentMap, witch, saved))
			ReplyToCommand(client, "[地图规则] 读取配置失败，请检查服务器日志。");
		else
			ReplyToCommand(client, "[地图规则] %s 路程 %s：本轮%s，保存值%s。", g_sCurrentMap, witch ? "Witch" : "Tank",
				g_staticRules[witch ? 1 : 0] ? "禁止" : "允许", saved ? "禁止" : "允许");
		return Plugin_Handled;
	}
	bool value = StrContains(command, "sm_unset") != 0;
	if (!SaveStaticRule(witch, value)) ReplyToCommand(client, "[地图规则] 保存失败，设置未更改，请检查服务器日志。");
	else ReplyToCommand(client, "[地图规则] 路程 %s 已设为%s；%s，重开后保持。", witch ? "Witch" : "Tank",
		value ? "禁止" : "允许", MapRules_IsLive() ? "下轮生效" : "本轮生效");
	return Plugin_Handled;
}
