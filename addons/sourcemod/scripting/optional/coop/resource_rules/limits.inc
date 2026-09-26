// Limits concern loose final resources, never inventories. Each entity counts
// once, regardless of pickup count. Evaluate all rules before changing entities.
#define RR_KEEP 0
#define RR_WINDOW 1
#define RR_SPACING 2
#define RR_LIMIT 3

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
	ArrayList resources = new ArrayList();
	int maximum = GetMaxEntities();
	int[] reasons = new int[maximum];
	bool[] touched = new bool[maximum];
	for (int entity = MaxClients + 1; entity < maximum; entity++)
	{
		if (!IsValidEntity(entity)) continue;
		if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity") && GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") > 0) continue;
		char name[64];
		GetResourceName(entity, name, sizeof(name));
		if (!name[0] || IsAllowed(name)) continue; // Campaign compatibility vote takes priority.
		if (HasEntProp(entity, Prop_Data, "m_itemCount") && GetEntProp(entity, Prop_Data, "m_itemCount") <= 0) continue;
		resources.Push(EntIndexToEntRef(entity));
	}

	ResourcePolicy policy;
	// Item rules first. Categories retain first-declaration order across overlays.
	for (int i = 0; i < g_itemPolicies.Length; i++)
	{
		g_itemPolicies.GetArray(i, policy);
		ApplyResourcePolicy(resources, policy, false, reasons, touched);
	}
	for (int i = 0; i < g_categoryPolicies.Length; i++)
	{
		g_categoryPolicies.GetArray(i, policy);
		ApplyResourcePolicy(resources, policy, true, reasons, touched);
	}

	int visualize = g_visualize.IntValue;
	static int colors[][] = {{255, 255, 255}, {255, 0, 0}, {255, 165, 0}, {0, 255, 255}};
	for (int i = 0; i < resources.Length; i++)
	{
		int entity = EntRefToEntIndex(resources.Get(i));
		if (entity == INVALID_ENT_REFERENCE || !touched[entity]) continue;
		int reason = reasons[entity];
		if (reason != RR_KEEP && visualize != 1) RemoveEntity(entity);
		else if (visualize > 0 && HasEntProp(entity, Prop_Send, "m_iGlowType")
			&& HasEntProp(entity, Prop_Send, "m_glowColorOverride")
			&& HasEntProp(entity, Prop_Send, "m_nGlowRange")
			&& HasEntProp(entity, Prop_Send, "m_nGlowRangeMin")
			&& HasEntProp(entity, Prop_Send, "m_bFlashing"))
			L4D2_SetEntityGlow(entity, L4D2Glow_Constant, 0, 0, colors[reason], false);
	}
	delete resources;
}

void MarkResourceCull(int entity, int reason, const char[] rule, int[] reasons)
{
	reasons[entity] = reason;
	if (g_visualize.IntValue > 0)
		LogMessage("[ResourceRules] %s entity %d by %s (reason %d: 1 window, 2 spacing, 3 limit)",
			g_visualize.IntValue == 1 ? "WOULD REMOVE" : "REMOVED", entity, rule, reason);
}

void ApplyResourcePolicy(ArrayList resources, ResourcePolicy policy, bool category, int[] reasons, bool[] touched)
{
	bool flow = policy.flowMin > 0.0 || policy.flowMax < 1.0 || policy.spacing > 0.0;
	if (policy.limit < 0 && !flow) return;
	if (category && !policy.members[0]) return;
	ArrayList matches = new ArrayList();
	for (int i = 0; i < resources.Length; i++)
	{
		int entity = EntRefToEntIndex(resources.Get(i));
		if (entity == INVALID_ENT_REFERENCE || reasons[entity] != RR_KEEP) continue;
		char name[64];
		GetResourceName(entity, name, sizeof(name));
		if (category)
		{
			char token[68];
			FormatEx(token, sizeof(token), ",%s,", name);
			if (StrContains(policy.members, token) == -1) continue;
		}
		else if (!StrEqual(policy.name, name)) continue;
		int region = GetResourceRegion(entity);
		if (region < 0) region = 3;
		if (!(policy.regions & (1 << region))) continue;
		touched[entity] = true;
		matches.Push(EntIndexToEntRef(entity));
	}
	if (!ApplyDistribution(matches, policy, reasons) && policy.limit >= 0)
	{
		// Retain Confogl's random excess removal when flow selection is inactive.
		while (matches.Length > policy.limit)
		{
			int index = GetRandomInt(0, matches.Length - 1);
			int entity = EntRefToEntIndex(matches.Get(index));
			if (entity != INVALID_ENT_REFERENCE) MarkResourceCull(entity, RR_LIMIT, policy.name, reasons);
			matches.Erase(index);
		}
	}
	if (g_visualize.IntValue > 0)
		LogMessage("[ResourceRules] Rule %s: %d points retained", policy.name, matches.Length);
	delete matches;
}
