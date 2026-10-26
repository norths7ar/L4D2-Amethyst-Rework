// Supply discovery and cabinet rules are inherited from item_glow 1.2.1.
ConVar g_mode, g_range, g_color, g_items, g_survivorsOnly;
int g_cabinetRef[ENTITY_LIMIT];
float g_cabinetItemOrigin[ENTITY_LIMIT][3];
bool g_discovered[ENTITY_LIMIT][4];
ArrayList g_tracked;
int g_traceClient, g_traceCabinet, g_rgb, g_itemTypes;
enum
{
    Glow_Pills = 1,
    Glow_Medkit = 2,
    Glow_Defib = 4,
    Glow_Ammo = 8
};

void InitSupplies()
{
    g_tracked = new ArrayList();
    g_mode = CreateConVar("item_glow_mode", "0", "0: off; 1: nearby discovered items; 2: discovered items without a distance cap.", _, true, 0.0, true, 2.0);
    g_range = CreateConVar("item_glow_range", "600", "Maximum distance in mode 1 (Source units).", _, true, 1.0);
    g_color = CreateConVar("item_glow_color", "100 200 255", "Outline color: R G B, each 0-255.");
    g_items = CreateConVar("item_glow_items", "pain_pills", "Comma-separated item names: pain_pills, first_aid_kit, defibrillator, ammo. Empty disables all items.");
    g_survivorsOnly = CreateConVar("item_glow_survivors_only", "1", "Only show outlines to living survivors; 0 allows all human players.", _, true, 0.0, true, 1.0);
    g_mode.AddChangeHook(OnSupplySettingsChanged);
    g_range.AddChangeHook(OnSupplySettingsChanged);
    g_color.AddChangeHook(OnSupplySettingsChanged);
    g_items.AddChangeHook(OnSupplySettingsChanged);
    g_survivorsOnly.AddChangeHook(OnSupplySettingsChanged);
}

void OnSupplySettingsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RebuildSupplies();
}

void ClearSupplies()
{
    for (int i = 0; i < g_tracked.Length; i++)
    {
        int item = EntRefToEntIndex(g_tracked.Get(i));
        if (item <= MaxClients) continue;
        ReleaseSource(item);
        g_cabinetRef[item] = INVALID_ENT_REFERENCE;
    }
    g_tracked.Clear();
}

void RebuildSupplies()
{
	ClearSupplies();
	char buffer[128], parts[16][32];
	g_items.GetString(buffer, sizeof(buffer));
	int count = ExplodeString(buffer, ",", parts, sizeof(parts), sizeof(parts[]));
	g_itemTypes = 0;
	for (int i = 0; i < count; i++)
	{
		TrimString(parts[i]);
		if (StrEqual(parts[i], "pain_pills", false)) g_itemTypes |= Glow_Pills;
		else if (StrEqual(parts[i], "first_aid_kit", false)) g_itemTypes |= Glow_Medkit;
		else if (StrEqual(parts[i], "defibrillator", false)) g_itemTypes |= Glow_Defib;
		else if (StrEqual(parts[i], "ammo", false)) g_itemTypes |= Glow_Ammo;
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
	if (!g_mode.IntValue || !g_itemTypes) return;
	// One scan on configuration changes; later spawns are handled by SpawnPost.
	for (int entity = MaxClients + 1; entity < GetMaxEntities() && entity < ENTITY_LIMIT; entity++)
	{
		if (IsValidEntity(entity)) AddSupply(entity);
	}
}

void AddSupply(int entity)
{
	if (!g_mode.IntValue || entity >= ENTITY_LIMIT || !(g_itemTypes & GetGlowItemType(entity))) return;
	if (g_sourceRef[entity] == EntIndexToEntRef(entity)) return;
	TrackSource(entity, Glow_Supply);
	g_tracked.Push(g_sourceRef[entity]);
	g_cabinetRef[entity] = FindItemCabinet(entity);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", g_cabinetItemOrigin[entity]);
}

int GetGlowItemType(int entity)
{
	// Standard ammo entities only: do not infer functionality from model names.
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (StrEqual(classname, "weapon_ammo_spawn")) return Glow_Ammo;
	switch (IdentifyWeapon(entity))
	{
		case WEPID_PAIN_PILLS: return Glow_Pills;
		case WEPID_FIRST_AID_KIT: return Glow_Medkit;
		case WEPID_DEFIBRILLATOR: return Glow_Defib;
	}
	return 0;
}

bool CanView(int client)
{
	return IsClientInGame(client) && !IsFakeClient(client)
		&& (!g_survivorsOnly.BoolValue || (GetClientTeam(client) == 2 && IsPlayerAlive(client)));
}

void UpdateSupplies()
{
	if (!g_mode.IntValue) return;
	for (int i = g_tracked.Length - 1; i >= 0; i--)
	{
		int item = EntRefToEntIndex(g_tracked.Get(i));
		if (item <= MaxClients) { g_tracked.Erase(i); continue; }
		bool available = !(GetEntProp(item, Prop_Send, "m_fEffects") & 32)
			&& (g_itemTypes & GetGlowItemType(item)) != 0;
		// A depleted spawn point can remain alive after its last pickup.
		if (HasEntProp(item, Prop_Data, "m_itemCount") && GetEntProp(item, Prop_Data, "m_itemCount") <= 0)
			available = false;
		if (HasEntProp(item, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(item, Prop_Send, "m_hOwnerEntity") != -1)
		{
			available = false;
			g_cabinetRef[item] = INVALID_ENT_REFERENCE;
		}
		float center[3], mins[3], maxs[3];
		GetEntPropVector(item, Prop_Data, "m_vecAbsOrigin", center);
		// Association belongs to a cabinet's contents, not to an item carried or
		// moved away from that spawn position by another plugin or map script.
		if (GetVectorDistance(center, g_cabinetItemOrigin[item]) > 4.0)
			g_cabinetRef[item] = INVALID_ENT_REFERENCE;
		int cabinet = EntRefToEntIndex(g_cabinetRef[item]);
		if (cabinet > MaxClients && !IsCabinetOpen(cabinet)) available = false;
		GetEntPropVector(item, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(item, Prop_Send, "m_vecMaxs", maxs);
		center[2] += (mins[2] + maxs[2]) * 0.5;
		bool nearby[MAXPLAYERS + 1];
		// Discover first, render second: sharing must not depend on client order.
		for (int client = 1; client <= MaxClients; client++)
		{
			if (!available || !CanView(client)) continue;
			float eye[3];
			GetClientEyePosition(client, eye);
			if (g_mode.IntValue == 1 && GetVectorDistance(eye, center) > g_range.FloatValue) continue;
			nearby[client] = true;
			int team = GetClientTeam(client);
			if (!g_discovered[item][team] && CanSeeItem(client, item, cabinet, eye, center))
				g_discovered[item][team] = true;
		}
		for (int client = 1; client <= MaxClients; client++)
		{
			if (nearby[client] && g_discovered[item][GetClientTeam(client)])
			{
				int glow = EntRefToEntIndex(g_supplyOutlineRef[item][client]);
				if (glow <= MaxClients) CreateOutline(item, g_rgb, client);
				else SyncOutlineAppearance(item, glow);
			}
			else RemoveSupplyOutline(item, client);
		}
		// A subsequently dropped item must be discovered again.
		if (!available)
			for (int team = 0; team < 4; team++) g_discovered[item][team] = false;
	}
	return;
}

bool CanSeeItem(int client, int item, int cabinet, const float eye[3], const float center[3])
{
	// Retain the original unobstructed-line-of-sight discovery criterion.
	g_traceClient = client;
	g_traceCabinet = cabinet;
	Handle trace = TR_TraceRayFilterEx(eye, center, MASK_VISIBLE, RayType_EndPoint, TraceVisibility);
	bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == item;
	delete trace;
	return visible;
}

int FindItemCabinet(int item)
{
	// Native cabinet contents have neither parent nor owner. Match their spawn
	// positions to the model's item attachments, not an arbitrary nearby box.
	float eye[3], center[3], mins[3];
	GetEntPropVector(item, Prop_Data, "m_vecAbsOrigin", center);
	int cabinet = -1;
	while ((cabinet = FindEntityByClassname(cabinet, "prop_health_cabinet")) != -1)
	{
		char model[PLATFORM_MAX_PATH];
		GetEntPropString(cabinet, Prop_Data, "m_ModelName", model, sizeof(model));
		// Only this verified native model has idle=0 and Open=1. Unknown custom
		// models keep ordinary LOS rather than guessing their animation state.
		if (!StrEqual(model, "models/props_interiors/medicalcabinet02.mdl", false)) continue;
		for (int slot = 1; slot <= 4; slot++)
		{
			char name[8];
			Format(name, sizeof(name), "item%d", slot);
			int attachment = LookupEntityAttachment(cabinet, name);
			if (attachment && GetEntityAttachment(cabinet, attachment, eye, mins)
				&& GetVectorDistance(center, eye) <= 4.0) return EntIndexToEntRef(cabinet);
		}
	}
	return INVALID_ENT_REFERENCE;
}

bool IsCabinetOpen(int cabinet)
{
	return GetEntProp(cabinet, Prop_Send, "m_nSequence") == 1
		&& GetEntPropFloat(cabinet, Prop_Send, "m_flCycle") >= 0.99;
}

bool TraceVisibility(int entity, int contentsMask)
{
	if (entity == g_traceClient || (entity > MaxClients && entity == g_traceCabinet)) return false;
	// The visual proxies must never obstruct traces to real items.
	return entity <= MaxClients || entity >= ENTITY_LIMIT || g_proxySourceRef[entity] == INVALID_ENT_REFERENCE;
}
