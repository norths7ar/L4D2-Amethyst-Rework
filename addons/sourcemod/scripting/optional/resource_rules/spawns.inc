// Preserve map weapon/item candidates. Replace the selected resources only
// after spawning, so the Director can resolve weapon clusters consistently.
public void OnMapInit(const char[] mapName)
{
	FinaleSupplies_NewMap();
	// ServerActivate can dispatch the initial round events before OnMapStart.
	// Reset here so their Director notification survives until configs are ready.
	g_configsReady = false;
	ResetResourceRound();
	LoadRules(mapName);
	if (!g_policyFile) return; // Framework modes retain their Stripper generation rules.
	// CurrentMission still describes the previous map during OnMapInit.
	// Resolve the incoming BSP before applying campaign-scoped permissions.
	ConVar mode = FindConVar("mp_gamemode");
	char modeName[64], campaign[128];
	mode.GetString(modeName, sizeof(modeName));
	MissionSymbol mission;
	int chapter;
	if (GetModeSymbol(modeName).ExportChapterByFile(mapName, mission, chapter) && MissionSymbol.IsValid(mission))
		mission.GetName(campaign, sizeof(campaign));
	else strcopy(campaign, sizeof(campaign), mapName);
	if (g_campaign[0] && !StrEqual(campaign, g_campaign, false)) ClearExceptions();
	strcopy(g_campaign, sizeof(g_campaign), campaign);
}

bool IsGunId(int id)
{
	return id == WEPID_SMG || id == WEPID_SMG_SILENCED || id == WEPID_SMG_MP5
		|| id == WEPID_PUMPSHOTGUN || id == WEPID_SHOTGUN_CHROME || id == WEPID_AUTOSHOTGUN || id == WEPID_SHOTGUN_SPAS
		|| id == WEPID_RIFLE || id == WEPID_RIFLE_DESERT || id == WEPID_RIFLE_AK47 || id == WEPID_RIFLE_SG552
		|| id == WEPID_HUNTING_RIFLE || id == WEPID_SNIPER_MILITARY || id == WEPID_SNIPER_AWP || id == WEPID_SNIPER_SCOUT;
}

void ChooseTarget(const char[] target, char[] choice, int maxlen)
{
	char candidates[16][64];
	int count = ExplodeString(target, ",", candidates, sizeof(candidates), sizeof(candidates[]));
	if (count < 1) { choice[0] = '\0'; return; }
	strcopy(choice, maxlen, candidates[GetRandomInt(0, count - 1)]);
	TrimString(choice);
}

public Action BeforeResourceSpawn(int entity)
{
	NormalizePickupFlags(entity);
	return Plugin_Continue;
}

void NormalizePickupFlags(int entity)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	// Bit 8 means Infinite Items only on weapon resource spawners. It is not
	// a generic entity flag, and ammo piles retain their normal refill behavior.
	if (strncmp(classname, "weapon_", 7) != 0 || StrContains(classname, "_spawn") == -1
		|| StrEqual(classname, "weapon_ammo_spawn") || StrEqual(classname, "weapon_scavenge_item_spawn")
		|| !HasEntProp(entity, Prop_Data, "m_spawnflags")) return;
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
	if (flags & 8)
	{
		SetEntProp(entity, Prop_Data, "m_spawnflags", flags & ~8);
		if (StrEqual(classname, "weapon_melee_spawn") && HasEntProp(entity, Prop_Data, "m_itemCount"))
			SetEntProp(entity, Prop_Data, "m_itemCount", g_meleePickups);
	}
}
