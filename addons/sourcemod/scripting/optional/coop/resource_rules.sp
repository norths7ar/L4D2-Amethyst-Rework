/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
 * Map resource handling based on ProdigySim's L4D2 Weapon Rules and
 * l4d2util/Confogl weapon conversion code (GPL-3.0-or-later).
 * Existing weapon identification and round/config readiness are retained.
 */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <entitylump>
#include <imatchext>
#include <left4dhooks>
#include <resource_rules>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>

StringMap g_rules;
StringMap g_mapEntries;
ConVar g_rulesFile;
bool g_roundReady, g_configsReady, g_creating;
bool g_allowed[ResourceGroup_Count];
char g_campaign[128];
int g_meleePickups;

public Plugin myinfo =
{
	name = "Map Resource Rules",
	author = "ProdigySim, norths7ar",
	description = "Owns map supplies, weapon replacements and campaign resource exceptions.",
	version = "1.0.0"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
	RegPluginLibrary("resource_rules");
	CreateNative("ResourceRules_IsAllowed", Native_IsAllowed);
	CreateNative("ResourceRules_SetAllowed", Native_SetAllowed);
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_rules = new StringMap();
	g_mapEntries = new StringMap();
	g_rulesFile = CreateConVar("resource_rules_file", "resource_rules.cfg", "Resource policy file relative to SourceMod configs.");
	LoadRules();
	HookEvent("round_start", RoundStartCb, EventHookMode_PostNoCopy);
	// A mode can load after round_start (or an administrator can reload it).
	CreateTimer(0.3, RoundStartDelay, _, TIMER_FLAG_NO_MAPCHANGE);
}

void LoadRules()
{
	char file[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	g_rulesFile.GetString(file, sizeof(file));
	BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);
	KeyValues rules = new KeyValues("ResourceRules");
	if (!rules.ImportFromFile(path)) SetFailState("Cannot read resource policy %s", path);
	g_meleePickups = rules.GetNum("melee_pickups", 1);
	g_rules.Clear();
	if (rules.JumpToKey("rules") && rules.GotoFirstSubKey(false))
	{
		do
		{
			char name[64], target[256];
			rules.GetSectionName(name, sizeof(name));
			rules.GetString(NULL_STRING, target, sizeof(target));
			g_rules.SetString(name, target);
		}
		while (rules.GotoNextKey(false));
	}
	delete rules;
}

public void OnMapStart()
{
	g_roundReady = false;
	g_configsReady = false;
	g_mapEntries.Clear();
	// The parsed map lump also retains duplicate output keys. Keep their
	// association by Hammer ID when a static resource needs a new class.
	for (int i = 0; i < EntityLump.Length(); i++)
	{
		EntityLumpEntry entry = EntityLump.Get(i);
		char id[24];
		if (entry.GetNextKey("hammerid", id, sizeof(id)) != -1) g_mapEntries.SetValue(id, i);
		delete entry;
	}
}

public void OnMapEnd()
{
	g_roundReady = false;
	g_configsReady = false;
}

public void OnConfigsExecuted()
{
	LoadRules();
	UpdateCampaign();
	g_configsReady = true;
	if (g_roundReady) ScanResources();
}

public void RoundStartCb(Event event, const char[] name, bool dontBroadcast)
{
	g_roundReady = false;
	CreateTimer(0.3, RoundStartDelay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action RoundStartDelay(Handle timer)
{
	g_roundReady = true;
	if (g_configsReady) ScanResources();
	return Plugin_Stop;
}

void UpdateCampaign()
{
	char campaign[128];
	if (MissionSymbol.IsValid(CurrentMission)) CurrentMission.GetName(campaign, sizeof(campaign));
	else GetCurrentMap(campaign, sizeof(campaign));
	if (g_campaign[0] && !StrEqual(g_campaign, campaign, false)) ClearExceptions();
	strcopy(g_campaign, sizeof(g_campaign), campaign);
}

public void CampaignSwitcher_OnNewCampaign()
{
	ClearExceptions();
}

void ClearExceptions()
{
	for (int i = 0; i < view_as<int>(ResourceGroup_Count); i++) g_allowed[i] = false;
}

public any Native_IsAllowed(Handle plugin, int numParams)
{
	int group = GetNativeCell(1);
	if (group < 0 || group >= view_as<int>(ResourceGroup_Count)) return ThrowNativeError(SP_ERROR_NATIVE, "Invalid resource group");
	return g_allowed[group];
}

public any Native_SetAllowed(Handle plugin, int numParams)
{
	int group = GetNativeCell(1);
	if (group < 0 || group >= view_as<int>(ResourceGroup_Count)) return ThrowNativeError(SP_ERROR_NATIVE, "Invalid resource group");
	g_allowed[group] = GetNativeCell(2) != 0;
	// No spawning and no removal from inventories. Recheck loose resources
	// when permission is revoked; granting permission cannot resurrect items.
	if (!g_allowed[group] && g_roundReady && g_configsReady) ScanResources();
	return 0;
}

bool IsAllowed(const char[] name)
{
	if (StrEqual(name, "grenade_launcher")) return g_allowed[ResourceGroup_Grenade];
	if (StrEqual(name, "gascan") || StrEqual(name, "fireworkcrate")) return g_allowed[ResourceGroup_Fire];
	if (StrEqual(name, "propanetank") || StrEqual(name, "oxygentank")) return g_allowed[ResourceGroup_Explosive];
	return false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (g_creating || entity <= MaxClients) return;
	if (strncmp(classname, "weapon_", 7) == 0 || strncmp(classname, "upgrade_", 8) == 0
		|| strncmp(classname, "prop_", 5) == 0)
	{
		SDKHook(entity, SDKHook_SpawnPost, ResourceSpawned);
	}
}

public void ResourceSpawned(int entity)
{
	// Give the caller time to equip a newly created weapon or finish setting
	// its model. Ent references avoid processing an edict reused meanwhile.
	RequestFrame(ProcessSpawnedResource, EntIndexToEntRef(entity));
}

public void ProcessSpawnedResource(int reference)
{
	int entity = EntRefToEntIndex(reference);
	if (entity != INVALID_ENT_REFERENCE && g_configsReady && g_roundReady) ProcessResource(entity);
}

void ScanResources()
{
	// Edict slots can have holes; entity count is not the highest valid index.
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
		if (IsValidEntity(entity)) ProcessResource(entity);
}

void GetResourceName(int entity, char[] name, int maxlen)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	int id = IdentifyWeapon(entity);
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
	if (StrEqual(name, "melee")) SetMeleeCount(entity);
	if (!name[0] || IsAllowed(name) || !g_rules.GetString(name, target, sizeof(target))) return;
	if (StrEqual(target, "none"))
	{
		RemoveEntity(entity);
		return;
	}
	char candidates[16][64];
	int count = ExplodeString(target, ",", candidates, sizeof(candidates), sizeof(candidates[]));
	if (count < 1) return;
	int choice = GetRandomInt(0, count - 1);
	TrimString(candidates[choice]);
	if (!StrEqual(name, candidates[choice])) ReplaceResource(entity, candidates[choice]);
}

void SetMeleeCount(int entity)
{
	bool infinite;
	if (HasEntProp(entity, Prop_Data, "m_spawnflags"))
	{
		int flags = GetEntProp(entity, Prop_Data, "m_spawnflags");
		infinite = (flags & 8) != 0;
		if (infinite) SetEntProp(entity, Prop_Data, "m_spawnflags", flags & ~8);
	}
	if (HasEntProp(entity, Prop_Data, "m_itemCount")
		&& (infinite || GetEntProp(entity, Prop_Data, "m_itemCount") > g_meleePickups))
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
	FormatEx(replacement, sizeof(replacement), "weapon_%s%s", target, spawner ? "_spawn" : "");
	g_creating = true;
	int created = CreateEntityByName(replacement);
	g_creating = false;
	if (created == -1) { LogError("Cannot replace %s with %s", classname, replacement); return; }
	StringMap outputs = new StringMap();
	CopyMapDefinition(entity, created, outputs);
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
