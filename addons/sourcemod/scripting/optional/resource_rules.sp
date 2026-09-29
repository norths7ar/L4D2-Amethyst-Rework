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
bool g_policyFile, g_roundSettled, g_resourcesProcessed, g_itemsProcessed, g_startKitsProcessed;
bool g_replayingSupplies;
ArrayList g_replayedSupplies;
int g_roundGeneration;
bool g_allowed[ResourceGroup_Count];
char g_campaign[128];
int g_meleePickups;
bool g_limitPassPending;

#include "resource_rules/config.inc"
#include "resource_rules/spawns.inc"
#include "resource_rules/replacement.inc"
#include "resource_rules/limits.inc"
#include "resource_rules/distribution.inc"
#include "resource_rules/weapon_rules.inc"
#include "resource_rules/weapon_handling.inc"
#include "resource_rules/saferoom_items.inc"
#include "resource_rules/start_kits.inc"

public Plugin myinfo =
{
	name = "Map Resource Rules",
	author = "ProdigySim, norths7ar",
	description = "Owns map supplies, weapon replacements and campaign resource exceptions.",
	version = "2.1.0"
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
	g_replayedSupplies = new ArrayList();
	InitPolicy();
	g_mapEntries = new StringMap();
	g_rulesFile = CreateConVar("resource_rules_file", "", "Resource policy file relative to SourceMod configs; empty uses the existing framework cvars and weapon rules.");
	FrameworkRules_Init();
	WI_OnModuleStart();
	SafeItems_Init();
	StartKits_Init();
	HookEvent("round_start", RoundStartCb, EventHookMode_PostNoCopy);
	// A mode can load after round_start (or an administrator can reload it).
	BeginResourceRound();
}

public void OnMapStart()
{
	g_roundReady = false;
	g_configsReady = false;
	g_limitPassPending = false;
	g_roundSettled = false;
	g_resourcesProcessed = false;
	g_itemsProcessed = false;
	g_startKitsProcessed = false;
	g_replayingSupplies = false;
	g_roundGeneration++;
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
	// SourceMod also calls OnMapStart for a late load, after OnPluginStart.
	// Schedule this map's passes even if its round_start event already fired.
	BeginResourceRound();
}

public void OnMapEnd()
{
	g_roundReady = false;
	g_configsReady = false;
	g_limitPassPending = false;
	WI_OnMapEnd();
	g_roundGeneration++;
}

public void OnConfigsExecuted()
{
	LoadRules("", true);
	UpdateCampaign();
	g_configsReady = true;
	PrepareResources();
	FinishResources();
}

public void RoundStartCb(Event event, const char[] name, bool dontBroadcast)
{
	BeginResourceRound();
}

void BeginResourceRound()
{
	g_replayedSupplies.Clear();
	g_roundReady = false;
	g_roundSettled = false;
	g_resourcesProcessed = false;
	g_itemsProcessed = false;
	g_startKitsProcessed = false;
	g_replayingSupplies = false;
	g_roundGeneration++;
	if (g_configsReady && !g_policyFile)
	{
		StartKits_RoundStart();
		g_startKitsProcessed = true;
	}
	CreateTimer(0.3, RoundStartDelay, g_roundGeneration, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, RoundItemsDelay, g_roundGeneration, TIMER_FLAG_NO_MAPCHANGE);
}

public Action RoundStartDelay(Handle timer, int generation)
{
	if (generation != g_roundGeneration) return Plugin_Stop;
	g_roundReady = true;
	PrepareResources();
	return Plugin_Stop;
}

public Action RoundItemsDelay(Handle timer, int generation)
{
	if (generation != g_roundGeneration) return Plugin_Stop;
	g_roundSettled = true;
	FinishResources();
	return Plugin_Stop;
}

void PrepareResources()
{
	if (!g_configsReady || !g_roundReady || g_resourcesProcessed) return;
	g_resourcesProcessed = true;
	g_replayingSupplies = LGO_ItemTrackingWillReplay();
	if (g_policyFile) ScanResources();
	else
	{
		if (!g_startKitsProcessed) StartKits_RoundStart();
		FrameworkRules_Scan();
		WI_RoundStartLoop(null);
	}
}

void FinishResources()
{
	if (!g_configsReady || !g_roundSettled || !g_resourcesProcessed || g_itemsProcessed) return;
	g_itemsProcessed = true;
	g_replayingSupplies = LGO_ItemTrackingWillReplay();
	// A replay must restore supplies before category accounting. On the first
	// round, selection precedes recording. These are deliberately opposite orders.
	bool replay = g_replayingSupplies;
	if (g_policyFile && !g_replayingSupplies) ApplyLimits(0);
	else if (!g_policyFile) SafeItems_Run();
	// Reconstructed items are already the final selection. Do not register our
	// spawn hooks on them and send them through replacement/limiting again.
	g_creating = true;
	LGO_RunItemTracking(!g_policyFile);
	g_creating = false;
	g_replayingSupplies = false;
	if (g_policyFile && replay) ApplyLimits(0);
}

public void LGO_OnItemReplayed(int entity)
{
	if (g_policyFile) g_replayedSupplies.Push(EntIndexToEntRef(entity));
}

bool IsReplayedSupply(int entity)
{
	return g_replayedSupplies.FindValue(EntIndexToEntRef(entity)) != -1;
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
	if (!g_policyFile || g_creating || entity <= MaxClients) return;
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
	if (!g_policyFile) return;
	// Edict slots can have holes; entity count is not the highest valid index.
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
		if (IsValidEntity(entity)) ProcessResource(entity);
	QueueLimitPass();
}
