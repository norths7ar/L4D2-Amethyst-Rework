#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#define L4D2UTIL_STOCKS_ONLY 1
#include <l4d2util>

#define ENTITY_LIMIT 2048

ConVar g_mode;
ConVar g_range;
ConVar g_color;
ConVar g_items;
ConVar g_survivorsOnly;
int g_glowRef[ENTITY_LIMIT];
int g_itemRef[ENTITY_LIMIT];
int g_rgb;
bool g_pills;
bool g_rebuilding;

public Plugin myinfo =
{
	name = "Coop item glow",
	author = "norths7ar",
	description = "Visible-item outlines with per-player line-of-sight checks.",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_mode = CreateConVar("item_glow_mode", "0", "0: off; 1: nearby visible items; 2: visible items without a distance cap.", _, true, 0.0, true, 2.0);
	g_range = CreateConVar("item_glow_range", "600", "Maximum distance in mode 1 (Source units).", _, true, 1.0);
	g_color = CreateConVar("item_glow_color", "100 200 255", "Outline color: R G B, each 0-255.");
	g_items = CreateConVar("item_glow_items", "pain_pills", "Comma-separated item names. Currently supported: pain_pills. Empty disables all items.");
	g_survivorsOnly = CreateConVar("item_glow_survivors_only", "1", "Only show outlines to living survivors; 0 allows all human players.", _, true, 0.0, true, 1.0);
	g_mode.AddChangeHook(OnSettingsChanged);
	g_range.AddChangeHook(OnSettingsChanged);
	g_color.AddChangeHook(OnSettingsChanged);
	g_items.AddChangeHook(OnSettingsChanged);
	g_survivorsOnly.AddChangeHook(OnSettingsChanged);
}

public void OnConfigsExecuted()
{
	RebuildGlows();
}

public void OnMapEnd()
{
	ClearGlows();
}

public void OnPluginEnd()
{
	ClearGlows();
}

void OnSettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RebuildGlows();
}

void ClearGlows()
{
	g_rebuilding = true;
	for (int entity = MaxClients + 1; entity < ENTITY_LIMIT; entity++)
	{
		int glow = EntRefToEntIndex(g_glowRef[entity]);
		g_glowRef[entity] = INVALID_ENT_REFERENCE;
		if (glow > MaxClients && IsValidEntity(glow)) RemoveEntity(glow);
		g_itemRef[entity] = INVALID_ENT_REFERENCE;
	}
	g_rebuilding = false;
}

void RebuildGlows()
{
	ClearGlows();
	char buffer[128], parts[16][32];
	g_items.GetString(buffer, sizeof(buffer));
	int count = ExplodeString(buffer, ",", parts, sizeof(parts), sizeof(parts[]));
	g_pills = false;
	for (int i = 0; i < count; i++)
	{
		TrimString(parts[i]);
		if (StrEqual(parts[i], "pain_pills", false)) g_pills = true;
	}
	g_color.GetString(buffer, sizeof(buffer));
	char rgb[3][8];
	ExplodeString(buffer, " ", rgb, sizeof(rgb), sizeof(rgb[]));
	g_rgb = 0;
	for (int i = 0; i < 3; i++)
	{
		int value = StringToInt(rgb[i]);
		if (value < 0) value = 0;
		if (value > 255) value = 255;
		g_rgb |= value << (8 * i);
	}
	if (!g_mode.IntValue || !g_pills) return;
	// One scan on configuration changes; later spawns are handled by SpawnPost.
	for (int entity = MaxClients + 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
	{
		if (IsValidEntity(entity)) AddGlow(entity);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity <= MaxClients || entity >= ENTITY_LIMIT) return;
	g_glowRef[entity] = INVALID_ENT_REFERENCE;
	g_itemRef[entity] = INVALID_ENT_REFERENCE;
	if (StrEqual(classname, "weapon_pain_pills") || StrEqual(classname, "weapon_pain_pills_spawn") || StrEqual(classname, "weapon_spawn"))
		SDKHook(entity, SDKHook_SpawnPost, OnItemSpawned);
}

void OnItemSpawned(int entity)
{
	// Allow the spawner to finish assigning its weapon type and model.
	RequestFrame(AddGlowNextFrame, EntIndexToEntRef(entity));
}

void AddGlowNextFrame(int reference)
{
	int entity = EntRefToEntIndex(reference);
	if (entity > MaxClients) AddGlow(entity);
}

void AddGlow(int entity)
{
	if (!g_mode.IntValue || !g_pills || entity >= ENTITY_LIMIT || IdentifyWeapon(entity) != WEPID_PAIN_PILLS) return;
	if (EntRefToEntIndex(g_glowRef[entity]) > MaxClients) return;
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));
	if (!model[0]) return;
	int glow = CreateEntityByName("prop_dynamic_override");
	if (glow == -1) return;
	if (glow >= ENTITY_LIMIT) { RemoveEntity(glow); return; }
	// Same invisible glow-proxy technique as l4d2_tank_props_glow.
	SetEntityModel(glow, model);
	DispatchSpawn(glow);
	SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
	SetEntProp(glow, Prop_Send, "m_iGlowType", 2);
	SetEntProp(glow, Prop_Send, "m_nGlowRange", 0);
	SetEntProp(glow, Prop_Send, "m_glowColorOverride", g_rgb);
	SetEntityRenderMode(glow, RENDER_NONE);
	SetEntityRenderColor(glow, 0, 0, 0, 0);
	float origin[3], angles[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(entity, Prop_Data, "m_angRotation", angles);
	TeleportEntity(glow, origin, angles, NULL_VECTOR);
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", entity);
	AcceptEntityInput(glow, "StartGlowing");
	g_glowRef[entity] = EntIndexToEntRef(glow);
	g_itemRef[glow] = EntIndexToEntRef(entity);
	SDKHook(glow, SDKHook_SetTransmit, OnGlowTransmit);
}

public void OnEntityDestroyed(int entity)
{
	if (g_rebuilding || entity <= MaxClients || entity >= ENTITY_LIMIT) return;
	int glow = EntRefToEntIndex(g_glowRef[entity]);
	g_glowRef[entity] = INVALID_ENT_REFERENCE;
	g_itemRef[entity] = INVALID_ENT_REFERENCE;
	if (glow > MaxClients && IsValidEntity(glow)) RemoveEntity(glow);
}

Action OnGlowTransmit(int glow, int client)
{
	if (!g_mode.IntValue || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
	if (g_survivorsOnly.BoolValue && (GetClientTeam(client) != 2 || !IsPlayerAlive(client))) return Plugin_Handled;
	int item = EntRefToEntIndex(g_itemRef[glow]);
	if (item <= MaxClients) return Plugin_Handled;
	// Keep the proxy attached while carried, but only display dropped/world items.
	if (HasEntProp(item, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(item, Prop_Send, "m_hOwnerEntity") != -1) return Plugin_Handled;
	if (GetEntProp(item, Prop_Send, "m_fEffects") & 32) return Plugin_Handled; // EF_NODRAW
	float eye[3], center[3], mins[3], maxs[3];
	GetClientEyePosition(client, eye);
	GetEntPropVector(item, Prop_Send, "m_vecOrigin", center);
	GetEntPropVector(item, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(item, Prop_Send, "m_vecMaxs", maxs);
	center[2] += (mins[2] + maxs[2]) * 0.5;
	if (g_mode.IntValue == 1 && GetVectorDistance(eye, center) > g_range.FloatValue) return Plugin_Handled;
	Handle trace = TR_TraceRayFilterEx(eye, center, MASK_VISIBLE, RayType_EndPoint, TraceVisibility, client);
	bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == item;
	delete trace;
	return visible ? Plugin_Continue : Plugin_Handled;
}

bool TraceVisibility(int entity, int contentsMask, any client)
{
	if (entity == client) return false;
	// The visual proxies must never obstruct traces to real items.
	return entity <= MaxClients || entity >= ENTITY_LIMIT || EntRefToEntIndex(g_itemRef[entity]) <= MaxClients;
}
