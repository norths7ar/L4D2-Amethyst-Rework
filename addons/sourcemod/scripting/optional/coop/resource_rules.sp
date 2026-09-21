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
#include <l4d2_saferoom_detect>
#include <confogl>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>

StringMap g_rules;
StringMap g_mapEntries;
ConVar g_rulesFile;
bool g_roundReady, g_configsReady, g_creating;
bool g_allowed[ResourceGroup_Count];
char g_campaign[128];
int g_meleePickups;
bool g_limitPassPending;

#include "resource_rules/config.inc"
#include "resource_rules/spawns.inc"
#include "resource_rules/replacement.inc"
#include "resource_rules/limits.inc"
#include "resource_rules/pill_flow.inc"

public Plugin myinfo =
{
	name = "Map Resource Rules",
	author = "ProdigySim, norths7ar",
	description = "Owns map supplies, weapon replacements and campaign resource exceptions.",
	version = "1.1.0"
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
	InitPolicy();
	g_mapEntries = new StringMap();
	g_rulesFile = CreateConVar("resource_rules_file", "resource_rules.cfg", "Resource policy file relative to SourceMod configs.");
	LoadRules();
	HookEvent("round_start", RoundStartCb, EventHookMode_PostNoCopy);
	// A mode can load after round_start (or an administrator can reload it).
	CreateTimer(0.3, RoundStartDelay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
	g_roundReady = false;
	g_configsReady = false;
	g_limitPassPending = false;
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
	g_limitPassPending = false;
}

public void OnConfigsExecuted()
{
	LoadRules();
	LoadChapterLimits();
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
		SDKHook(entity, SDKHook_Spawn, BeforeResourceSpawn);
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
	if (entity != INVALID_ENT_REFERENCE && g_configsReady && g_roundReady)
	{
		ProcessResource(entity);
		QueueLimitPass();
	}
}

void ScanResources()
{
	// Edict slots can have holes; entity count is not the highest valid index.
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
		if (IsValidEntity(entity)) ProcessResource(entity);
	QueueLimitPass();
}
