// Capture native creation provenance: cabinet contents have no parent/owner.
// SpawnItems creates its supplies synchronously at round_start_post_nav.
enum struct CabinetProduct
{
	int reference;
	int ordinal;
	float origin[3];
}

DynamicDetour g_cabinetSpawnItems;
ArrayList g_cabinetContexts, g_cabinetProducts;

void CabinetSupplies_Init()
{
	g_cabinetContexts = new ArrayList(2); // cabinet ref, created count
	g_cabinetProducts = new ArrayList(sizeof(CabinetProduct));
	GameData data = new GameData("resource_rules");
	if (data != null && data.GetOffset("CabinetSpawnItemsSupported") == 1
		&& GetFeatureStatus(FeatureType_Native, "DynamicDetour.FromConf") == FeatureStatus_Available)
	{
		g_cabinetSpawnItems = DynamicDetour.FromConf(data, "CPropHealthCabinet::SpawnItems");
		if (g_cabinetSpawnItems != null
			&& (!g_cabinetSpawnItems.Enable(Hook_Pre, CabinetSupplies_BeforeSpawn)
				|| !g_cabinetSpawnItems.Enable(Hook_Post, CabinetSupplies_AfterSpawn)))
			delete g_cabinetSpawnItems;
	}
	delete data;
	if (g_cabinetSpawnItems == null)
		LogError("Cabinet creation hook unavailable; cabinet count and finale supply policies cannot be applied.");
}

public MRESReturn CabinetSupplies_BeforeSpawn(int entity)
{
	int context[2];
	context[0] = EntIndexToEntRef(entity);
	g_cabinetContexts.PushArray(context);
	return MRES_Ignored;
}

public MRESReturn CabinetSupplies_AfterSpawn(int entity)
{
	g_cabinetContexts.Erase(g_cabinetContexts.Length - 1);
	return MRES_Ignored;
}

void CabinetSupplies_Created(int entity, const char[] classname)
{
	if (!g_cabinetContexts.Length) return;
	if (!StrEqual(classname, "weapon_first_aid_kit_spawn") && !StrEqual(classname, "weapon_pain_pills_spawn")) return;
	int index = g_cabinetContexts.Length - 1;
	int cabinet = EntRefToEntIndex(g_cabinetContexts.Get(index, 0));
	if (cabinet == INVALID_ENT_REFERENCE) return;
	CabinetProduct product;
	product.reference = EntIndexToEntRef(entity);
	product.ordinal = g_cabinetContexts.Get(index, 1) + 1;
	g_cabinetContexts.Set(index, product.ordinal, 1);
	GetEntPropVector(cabinet, Prop_Data, "m_vecAbsOrigin", product.origin);
	g_cabinetProducts.PushArray(product);
}

int CabinetSupplies_Find(int entity)
{
	return g_cabinetProducts.FindValue(EntIndexToEntRef(entity));
}

bool CabinetSupplies_Process(int entity)
{
	int index = CabinetSupplies_Find(entity);
	if (index == -1) return true;
	CabinetProduct product;
	g_cabinetProducts.GetArray(index, product);
	// Apply after configuration and start-area readiness, not during native
	// generation. In particular, the finale layer must precede any deletion.
	if (g_cabinetLimit >= 0 && product.ordinal > g_cabinetLimit)
	{
		RemoveEntity(entity);
		return false;
	}
	if (g_finaleActive && FinaleSupplies_OutsideStart(product.origin))
		FinaleSupplies_Protect(entity);
	return true;
}

void CabinetSupplies_Transfer(int source, int target)
{
	int index = CabinetSupplies_Find(source);
	if (index != -1) g_cabinetProducts.Set(index, EntIndexToEntRef(target));
}

void CabinetSupplies_Reset()
{
	// The initial reset may follow native creation. Keep live provenance;
	// serial-checked references distinguish new rounds and recycled edicts.
	CabinetSupplies_Destroyed(-1);
}

void CabinetSupplies_Destroyed(int entity)
{
	if (g_cabinetProducts == null) return;
	for (int i = g_cabinetProducts.Length - 1; i >= 0; i--)
	{
		int current = EntRefToEntIndex(g_cabinetProducts.Get(i));
		if (current == entity || current == INVALID_ENT_REFERENCE) g_cabinetProducts.Erase(i);
	}
}
