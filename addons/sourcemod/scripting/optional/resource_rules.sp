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
bool g_policyFile, g_directorReady, g_initializationPending;
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
	version = "2.2.0"
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
	HookEvent("round_start_pre_entity", RoundResetCb, EventHookMode_Pre);
	HookEvent("round_start_post_nav", DirectorReadyCb, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
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
	g_configsReady = false;
	ResetResourceRound();
	WI_OnMapEnd();
}

public void OnConfigsExecuted()
{
	LoadRules();
	UpdateCampaign();
	g_configsReady = true;
	QueueResourceInitialization();
}

public void RoundResetCb(Event event, const char[] name, bool dontBroadcast)
{
	// Invalidate the previous round before CleanUpMap rebuilds its entities.
	// post_nav is dispatched inside round_start; resetting in its Post hook
	// would erase the Director notification belonging to this new round.
	ResetResourceRound();
}

void ResetResourceRound()
{
	g_resourceDecisions.Clear();
	g_distributionWarnings.Clear();
	g_replayedSupplies.Clear();
	g_roundReady = false;
	g_directorReady = false;
	g_initializationPending = false;
	g_limitPassPending = false;
	g_replayingSupplies = false;
	g_roundGeneration++;
}

public void DirectorReadyCb(Event event, const char[] name, bool dontBroadcast)
{
	// The engine's synchronous event listeners have finished selecting resources.
	g_directorReady = true;
	QueueResourceInitialization();
}

void QueueResourceInitialization()
{
	if (!g_configsReady || !g_directorReady || g_roundReady || g_initializationPending) return;
	g_initializationPending = true;
	// Leave event/config dispatch before replacing the Director's selected entities.
	RequestFrame(InitializeResources, g_roundGeneration);
}

public void InitializeResources(int generation)
{
	if (generation != g_roundGeneration) return;
	g_roundReady = true;
	g_replayingSupplies = LGO_ItemTrackingWillReplay();
	if (g_policyFile) ScanResources();
	else
	{
		StartKits_RoundStart();
		FrameworkRules_Scan();
		WI_RoundStartLoop(null);
	}

	// On the first round, limit before recording; on replay, restore before limiting.
	bool replay = g_replayingSupplies;
	if (g_policyFile && !replay) ApplyLimits();
	else if (!g_policyFile) SafeItems_Run();
	// Restored items are already selected: do not hook their creation for replacement.
	g_creating = true;
	LGO_RunItemTracking(!g_policyFile);
	g_creating = false;
	g_replayingSupplies = false;
	if (g_policyFile && replay) ApplyLimits();
	g_initializationPending = false;
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
	// Initial map resources are handled together after the Director's event.
	if (!g_roundReady) return;
	// Give the caller time to equip a newly created weapon or finish setting
	// its model. Ent references avoid processing an edict reused meanwhile.
	DataPack data = new DataPack();
	data.WriteCell(g_roundGeneration);
	data.WriteCell(EntIndexToEntRef(entity));
	RequestFrame(ProcessSpawnedResource, data);
}

public void ProcessSpawnedResource(DataPack data)
{
	data.Reset();
	int generation = data.ReadCell();
	int reference = data.ReadCell();
	delete data;
	if (generation != g_roundGeneration) return;
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
