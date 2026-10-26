// Preserve actual scavenge products, not every gas can on a scavenge map.
// Broader fallback considered but intentionally not implemented: detecting a
// pour target/spawner could allow all cans for the chapter, including fuel cans.
Handle g_scavengeGetSpawner;
DynamicDetour g_scavengeSetSpawner;
ArrayList g_scavengeProducts;

void ScavengeSupplies_Init()
{
	g_scavengeProducts = new ArrayList();
	GameData data = new GameData("resource_rules");
	if (data != null && data.GetOffset("ScavengeGetSpawnerSupported") == 1)
	{
		StartPrepSDKCall(SDKCall_Entity);
		bool found = PrepSDKCall_SetFromConf(data, SDKConf_Signature, "CCarriedProp::GetSpawner");
		PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
		Handle call = EndPrepSDKCall();
		if (found) g_scavengeGetSpawner = call;
		else delete call;
		if (GetFeatureStatus(FeatureType_Native, "DynamicDetour.FromConf") == FeatureStatus_Available)
		{
			g_scavengeSetSpawner = DynamicDetour.FromConf(data, "CGasCan::SetSpawner");
			if (g_scavengeSetSpawner != null && !g_scavengeSetSpawner.Enable(Hook_Post, ScavengeSupplies_Assigned))
				delete g_scavengeSetSpawner;
		}
	}
	delete data;
	if (g_scavengeGetSpawner == null)
		LogError("Scavenge product lookup unavailable on this server; spawned task cans cannot be identified.");
	else if (g_scavengeSetSpawner == null)
		LogError("Scavenge assignment hook unavailable; lookup requires the spawner to survive until resource processing.");
}

public MRESReturn ScavengeSupplies_Assigned(int entity, DHookParam params)
{
	// Capture the real assignment before a map can destroy its spawner in the
	// same input chain. Never change engine arguments, skins or return values.
	if (entity <= MaxClients || !IsValidEntity(entity) || params.IsNull(1)) return MRES_Ignored;
	int spawner = params.Get(1);
	if (spawner <= MaxClients || !IsValidEntity(spawner)) return MRES_Ignored;
	char classname[64];
	GetEntityClassname(spawner, classname, sizeof(classname));
	if (StrEqual(classname, "weapon_scavenge_item_spawn"))
	{
		int reference = EntIndexToEntRef(entity);
		if (g_scavengeProducts.FindValue(reference) == -1) g_scavengeProducts.Push(reference);
	}
	return MRES_Ignored;
}

void ScavengeSupplies_Reset()
{
	// A first round reset may follow creation and removal of the spawner.
	// Keep live product identities; destruction and serials handle reuse.
	for (int i = g_scavengeProducts.Length - 1; i >= 0; i--)
		if (EntRefToEntIndex(g_scavengeProducts.Get(i)) == INVALID_ENT_REFERENCE) g_scavengeProducts.Erase(i);
}

bool ScavengeSupplies_IsProtected(int entity)
{
	int reference = EntIndexToEntRef(entity);
	if (g_scavengeProducts.FindValue(reference) != -1) return true;
	if (g_scavengeGetSpawner == null) return false;
	// Only weapon_gascan reaches this getter: generic weapon spawners and
	// physics props do not inherit CCarriedProp. ResourceSpawned already waits
	// a frame, because InputSpawnScavengeItem sets the backlink AFTER Spawn.
	int spawner = SDKCall(g_scavengeGetSpawner, entity);
	if (spawner <= MaxClients || !IsValidEntity(spawner)) return false;
	char classname[64];
	GetEntityClassname(spawner, classname, sizeof(classname));
	if (!StrEqual(classname, "weapon_scavenge_item_spawn")) return false;
	g_scavengeProducts.Push(reference);
	return true;
}

void ScavengeSupplies_Destroyed(int entity)
{
	if (entity <= MaxClients || g_scavengeProducts == null) return;
	for (int i = g_scavengeProducts.Length - 1; i >= 0; i--)
	{
		int current = EntRefToEntIndex(g_scavengeProducts.Get(i));
		if (current == entity || current == INVALID_ENT_REFERENCE) g_scavengeProducts.Erase(i);
	}
}
