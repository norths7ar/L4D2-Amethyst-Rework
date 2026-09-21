// Limits concern loose map supplies after replacement, never player inventory.
// ItemTracking's random excess removal is retained; safe rooms are exempt.
void QueueLimitPass()
{
	if (g_limitPassPending) return;
	g_limitPassPending = true;
	RequestFrame(ApplyLimits);
}

public void ApplyLimits(any unused)
{
	g_limitPassPending = false;
	if (!g_configsReady || !g_roundReady) return;
	ArrayList supplies[SUPPLY_COUNT];
	for (int i = 0; i < SUPPLY_COUNT; i++) supplies[i] = new ArrayList();
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
	{
		if (!IsValidEntity(entity)) continue;
		if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") > 0) continue;
		char name[64];
		GetResourceName(entity, name, sizeof(name));
		int kind = -1;
		for (int i = 0; i < SUPPLY_COUNT; i++) if (StrEqual(name, g_supplyNames[i])) { kind = i; break; }
		if (kind < 0) continue;
		// Legacy ItemLimits exempt confirmed saferooms, not all points with
		// incomplete map data. Otherwise chapters with limits but no boxes
		// would silently lose their limits. Unknown remains distinct for rules.
		int region = GetResourceRegion(entity);
		if (region == 0 || region == 1) continue;
		if (HasEntProp(entity, Prop_Data, "m_itemCount") && GetEntProp(entity, Prop_Data, "m_itemCount") <= 0) continue;
		supplies[kind].Push(EntIndexToEntRef(entity));
	}
	bool pillFlowHandled = ApplyPillFlowFilter(supplies[0], g_limits[0]);
	for (int kind = 0; kind < SUPPLY_COUNT; kind++)
	{
		if (!(kind == 0 && pillFlowHandled) && g_limits[kind] >= 0)
		{
			while (supplies[kind].Length > g_limits[kind])
			{
				int index = GetRandomInt(0, supplies[kind].Length - 1);
				int entity = EntRefToEntIndex(supplies[kind].Get(index));
				if (entity != INVALID_ENT_REFERENCE) RemoveEntity(entity);
				supplies[kind].Erase(index);
			}
		}
		delete supplies[kind];
	}
}
