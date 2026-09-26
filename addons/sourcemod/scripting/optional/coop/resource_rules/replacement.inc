void GetResourceName(int entity, char[] name, int maxlen)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	// Ammo piles have no normal weapon ID, but participate in point limits.
	if (StrEqual(classname, "weapon_ammo_spawn"))
	{
		strcopy(name, maxlen, "ammo");
		return;
	}
	int id = IdentifyWeapon(entity);
	if (StrEqual(classname, "weapon_item_spawn") && HasEntProp(entity, Prop_Send, "m_weaponID"))
		id = GetEntProp(entity, Prop_Send, "m_weaponID");
	if (id > WEPID_NONE && id < WEPID_SIZE)
	{
		GetWeaponName(id, name, maxlen);
		if (strncmp(name, "weapon_", 7) == 0) strcopy(name, maxlen, name[7]);
		return;
	}
	if (StrEqual(classname, "prop_minigun") || StrEqual(classname, "prop_minigun_l4d1") || StrEqual(classname, "prop_mounted_machine_gun"))
		strcopy(name, maxlen, "mounted_gun");
	else if (strncmp(classname, "upgrade_", 8) == 0) strcopy(name, maxlen, "upgrade_item");
	else if (strncmp(classname, "prop_physics", 12) == 0)
	{
		char model[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
		if (StrEqual(model, "models/props_junk/gascan001a.mdl", false)) strcopy(name, maxlen, "gascan");
		else if (StrEqual(model, "models/props_junk/explosive_box001.mdl", false)) strcopy(name, maxlen, "fireworkcrate");
		else if (StrEqual(model, "models/props_junk/propanecanister001a.mdl", false)) strcopy(name, maxlen, "propanetank");
		else if (StrEqual(model, "models/props_equipment/oxygentank01.mdl", false)) strcopy(name, maxlen, "oxygentank");
	}
}

void ProcessResource(int entity)
{
	if (!IsValidEntity(entity)) return;
	if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") > 0) return;
	char name[64], target[256];
	GetResourceName(entity, name, sizeof(name));
	NormalizePickupFlags(entity);
	if (StrEqual(name, "melee")) SetMeleeCount(entity);
	if (!name[0] || IsAllowed(name) || !GetResourceRule(entity, name, target, sizeof(target))) return;
	if (StrEqual(target, "none"))
	{
		RemoveEntity(entity);
		return;
	}
	char choice[64];
	ChooseTarget(target, choice, sizeof(choice));
	if (choice[0] && !StrEqual(name, choice)) ReplaceResource(entity, choice);
}

void SetMeleeCount(int entity)
{
	// Infinite flags are normalized for every resource in spawns.inc.
	if (HasEntProp(entity, Prop_Data, "m_itemCount") && GetEntProp(entity, Prop_Data, "m_itemCount") > g_meleePickups)
		SetEntProp(entity, Prop_Data, "m_itemCount", g_meleePickups);
}

int WeaponNameToId2(const char[] name)
{
	char weapon[64];
	FormatEx(weapon, sizeof(weapon), "weapon_%s", name);
	return WeaponNameToId(weapon);
}

void CopyMapDefinition(int source, int target, StringMap outputs)
{
	if (!HasEntProp(source, Prop_Data, "m_iHammerID")) return;
	char id[24];
	IntToString(GetEntProp(source, Prop_Data, "m_iHammerID"), id, sizeof(id));
	int index;
	if (!g_mapEntries.GetValue(id, index)) return;
	EntityLumpEntry entry = EntityLump.Get(index);
	for (int i = 0; i < entry.Length; i++)
	{
		char key[128], value[2048];
		entry.Get(i, key, sizeof(key), value, sizeof(value));
		if (strncmp(key, "On", 2) == 0)
		{
			outputs.SetValue(key, 1);
			continue;
		}
		if (StrEqual(key, "classname") || StrEqual(key, "model") || StrEqual(key, "weapon_selection") || StrEqual(key, "melee_weapon")) continue;
		DispatchKeyValue(target, key, value);
	}
	delete entry;
}

bool CopyLiveOutputs(int source, int target, StringMap outputs)
{
	// These outputs also cover resources created by scripts, with no Hammer ID.
	static char common[][] = {"OnUser1", "OnUser2", "OnUser3", "OnUser4", "OnPlayerPickup", "OnNPCPickup", "OnPlayerUse", "OnItemSpawn", "OnItemSpawned", "OnCacheInteraction"};
	for (int i = 0; i < sizeof(common); i++) outputs.SetValue(common[i], 1);
	StringMapSnapshot names = outputs.Snapshot();
	bool success = true;
	for (int i = 0; i < names.Length; i++)
	{
		char name[128];
		names.GetKey(i, name, sizeof(name));
		// Only engine output identifiers belong in the script, never map values.
		bool valid = true;
		for (int j = 0; name[j]; j++)
			if (!IsCharAlpha(name[j]) && !IsCharNumeric(name[j]) && name[j] != '_') valid = false;
		if (!valid) { success = false; break; }
		char code[1006], result[8];
		FormatEx(code, sizeof(code),
			"local s=EntIndexToHScript(%d),d=EntIndexToHScript(%d),n=\"%s\",ok=true; if(EntityOutputs.HasAction(s,n)){if(!EntityOutputs.HasOutput(d,n))ok=false;else{for(local i=0;i<EntityOutputs.GetNumElements(s,n);i++){local t={};EntityOutputs.GetOutputTable(s,n,t,i);EntityOutputs.AddOutput(d,n,t.target,t.input,t.parameter,t.delay,t.times_to_fire);}}}; <RETURN>ok ? 1 : 0</RETURN>",
			source, target, name);
		if (!L4D2_GetVScriptOutput(code, result, sizeof(result)) || StringToInt(result) != 1)
		{
			LogError("Cannot preserve resource output %s on entity %d", name, source);
			success = false;
			break;
		}
	}
	delete names;
	return success;
}

void ReplaceResource(int entity, const char[] target)
{
	int id = WeaponNameToId2(target);
	if (!IsValidWeaponId(id) || id == WEPID_NONE) return;
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	bool spawner = StrEqual(classname, "weapon_spawn") || StrContains(classname, "_spawn") != -1;
	int count = HasEntProp(entity, Prop_Data, "m_itemCount") ? GetEntProp(entity, Prop_Data, "m_itemCount") : 1;
	if (spawner && count <= 0) return;

	// Confogl already changes weapon_spawn in place. Keep its outputs,
	// parent and targetname rather than rebuilding a generic gun spawner.
	if (StrEqual(classname, "weapon_spawn") && id != WEPID_MELEE && HasValidWeaponModel(id))
	{
		char model[PLATFORM_MAX_PATH];
		GetWeaponModel(id, model, sizeof(model));
		Format(model, sizeof(model), "models%s", model);
		PrecacheModel(model);
		SetEntProp(entity, Prop_Send, "m_weaponID", id);
		SetEntityModel(entity, model);
		return;
	}

	char replacement[64];
	if (spawner && IsGunId(id)) strcopy(replacement, sizeof(replacement), "weapon_spawn");
	else FormatEx(replacement, sizeof(replacement), "weapon_%s%s", target, spawner ? "_spawn" : "");
	g_creating = true;
	int created = CreateEntityByName(replacement);
	g_creating = false;
	if (created == -1) { LogError("Cannot replace %s with %s", classname, replacement); return; }
	StringMap outputs = new StringMap();
	CopyMapDefinition(entity, created, outputs);
	if (StrEqual(replacement, "weapon_spawn"))
	{
		char selection[80];
		FormatEx(selection, sizeof(selection), "weapon_%s", target);
		DispatchKeyValue(created, "weapon_selection", selection);
		DispatchKeyValueInt(created, "spawn_without_director", 1);
	}
	char targetname[128];
	GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
	DispatchKeyValue(created, "targetname", targetname);
	if (HasEntProp(entity, Prop_Data, "m_spawnflags")) DispatchKeyValueInt(created, "spawnflags", GetEntProp(entity, Prop_Data, "m_spawnflags"));
	DispatchKeyValueInt(created, "count", id == WEPID_MELEE ? g_meleePickups : count);
	if (id == WEPID_MELEE)
	{
		// The melee unlock plugin owns the mission's available weapon list.
		// Resolve one script here, including for direct weapon_melee entities.
		int table = FindStringTable("MeleeWeapons");
		int available = table == INVALID_STRING_TABLE ? 0 : GetStringTableNumStrings(table);
		if (available < 1) { delete outputs; RemoveEntity(created); LogError("No precached melee weapons available"); return; }
		char melee[64];
		ConVar meleeList = FindConVar("l4d2_melee_spawn");
		char allowed[512], candidates[32][64];
		if (meleeList != null) meleeList.GetString(allowed, sizeof(allowed));
		int choices = ExplodeString(allowed, ",", candidates, sizeof(candidates), sizeof(candidates[]));
		if (allowed[0] && choices > 0)
		{
			strcopy(melee, sizeof(melee), candidates[GetRandomInt(0, choices - 1)]);
			TrimString(melee);
		}
		else ReadStringTable(table, GetRandomInt(0, available - 1), melee, sizeof(melee));
		DispatchKeyValue(created, "melee_script_name", melee);
		DispatchKeyValue(created, "melee_weapon", melee);
	}
	float origin[3], angles[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Send, "m_angRotation", angles);
	TeleportEntity(created, origin, angles, NULL_VECTOR);
	if (!DispatchSpawn(created)) { delete outputs; RemoveEntity(created); LogError("Cannot spawn replacement %s", replacement); return; }
	bool copied = CopyLiveOutputs(entity, created, outputs);
	delete outputs;
	if (!copied) { RemoveEntity(created); return; }
	if (GetEntityMoveType(entity) == MOVETYPE_NONE) SetEntityMoveType(created, MOVETYPE_NONE);
	int parent = GetEntPropEnt(entity, Prop_Data, "m_hMoveParent");
	if (parent > 0)
	{
		SetVariantString("!activator");
		AcceptEntityInput(created, "SetParent", parent);
	}
	if (id == WEPID_MELEE) SetMeleeCount(created);
	// Never remove the source before the replacement has successfully spawned.
	RemoveEntity(entity);
}
