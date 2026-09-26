// Preserve random-item candidates; process their selected item after spawning.
// Gun selections and pickup flags retain their generation-time handling.
public void OnMapInit(const char[] mapName)
{
	LoadRules(mapName);
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

	// Convert fixed gun spawners in place in the lump: all targetnames, I/O,
	// parent links, count and map-authored properties survive unchanged.
	for (int i = 0; i < EntityLump.Length(); i++)
	{
		EntityLumpEntry entry = EntityLump.Get(i);
		char classname[64], name[64], target[256], origin[128];
		entry.GetNextKey("classname", classname, sizeof(classname));
		int suffix = StrContains(classname, "_spawn");
		if (strncmp(classname, "weapon_", 7) == 0 && suffix > 7 && !StrEqual(classname, "weapon_item_spawn"))
		{
			strcopy(name, sizeof(name), classname[7]);
			name[suffix - 7] = '\0';
			int id = WeaponNameToId2(name);
			if (IsGunId(id) && !IsAllowed(name))
			{
				float point[3];
				char parts[3][32];
				entry.GetNextKey("origin", origin, sizeof(origin));
				ExplodeString(origin, " ", parts, sizeof(parts), sizeof(parts[]));
				for (int j = 0; j < 3; j++) point[j] = StringToFloat(parts[j]);
				if (GetRuleInRegion(GetRegionAtPoint(point), name, target, sizeof(target)) && !StrEqual(target, "none"))
				{
					if (AreGunTargets(target) && !StrEqual(target, name))
					{
						char selection[80];
						FormatEx(selection, sizeof(selection), "weapon_%s", name);
						SetLumpKey(entry, "classname", "weapon_spawn");
						SetLumpKey(entry, "weapon_selection", selection);
						SetLumpKey(entry, "spawn_without_director", "1");
						// Existing fixed gun spawners default to five pickups.
						if (entry.FindKey("count") == -1) entry.Append("count", "5");
					}
				}
			}
		}
		delete entry;
	}
}

void SetLumpKey(EntityLumpEntry entry, const char[] key, const char[] value)
{
	int index = entry.FindKey(key);
	if (index == -1) entry.Append(key, value);
	else entry.Update(index, _, value);
}

bool IsGunId(int id)
{
	return id == WEPID_SMG || id == WEPID_SMG_SILENCED || id == WEPID_SMG_MP5
		|| id == WEPID_PUMPSHOTGUN || id == WEPID_SHOTGUN_CHROME || id == WEPID_AUTOSHOTGUN || id == WEPID_SHOTGUN_SPAS
		|| id == WEPID_RIFLE || id == WEPID_RIFLE_DESERT || id == WEPID_RIFLE_AK47 || id == WEPID_RIFLE_SG552
		|| id == WEPID_HUNTING_RIFLE || id == WEPID_SNIPER_MILITARY || id == WEPID_SNIPER_AWP || id == WEPID_SNIPER_SCOUT;
}

bool AreGunTargets(const char[] target)
{
	char candidates[16][64];
	int count = ExplodeString(target, ",", candidates, sizeof(candidates), sizeof(candidates[]));
	if (count < 1) return false;
	for (int i = 0; i < count; i++)
	{
		TrimString(candidates[i]);
		if (!IsGunId(WeaponNameToId2(candidates[i]))) return false;
	}
	return true;
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
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	NormalizePickupFlags(entity);
	if (StrEqual(classname, "weapon_spawn"))
	{
		char selection[80], target[256];
		GetEntPropString(entity, Prop_Data, "m_iszWeaponToSpawn", selection, sizeof(selection));
		int region = GetResourceRegion(entity);
		if ((region >= 0 && g_regionRules[region].GetString(selection, target, sizeof(target)))
			|| g_selections.GetString(selection, target, sizeof(target)))
			DispatchKeyValue(entity, "weapon_selection", target);
		else if (strncmp(selection, "weapon_", 7) == 0 && !IsAllowed(selection[7])
			&& GetResourceRule(entity, selection[7], target, sizeof(target)) && !StrEqual(target, "none"))
		{
			char choice[64];
			ChooseTarget(target, choice, sizeof(choice));
			if (IsGunId(WeaponNameToId2(choice)))
			{
				FormatEx(selection, sizeof(selection), "weapon_%s", choice);
				DispatchKeyValue(entity, "weapon_selection", selection);
			}
		}
	}
	return Plugin_Continue;
}

void NormalizePickupFlags(int entity)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	// Bit 8 means Infinite Items only on weapon resource spawners. It is not
	// a generic entity flag, and ammo piles retain their normal refill behavior.
	if (strncmp(classname, "weapon_", 7) != 0 || StrContains(classname, "_spawn") == -1
		|| StrEqual(classname, "weapon_ammo_spawn") || !HasEntProp(entity, Prop_Data, "m_spawnflags")) return;
	int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
	if (flags & 8)
	{
		SetEntProp(entity, Prop_Data, "m_spawnflags", flags & ~8);
		if (StrEqual(classname, "weapon_melee_spawn") && HasEntProp(entity, Prop_Data, "m_itemCount"))
			SetEntProp(entity, Prop_Data, "m_itemCount", g_meleePickups);
	}
}
