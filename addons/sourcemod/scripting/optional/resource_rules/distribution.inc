// Route flow determines the budget and spread; world coordinates determine
// spacing. Existing selections are anchors, never candidates for a new roll.
float ResourceFlowFraction(int entity, float maxFlow)
{
    float origin[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
    Address nav = L4D_GetNearestNavArea(origin, 120.0, true, false, false, 2);
    if (nav == Address_Null) nav = L4D2Direct_GetTerrorNavArea(origin);
    float flow = nav != Address_Null ? L4D2Direct_GetTerrorNavAreaFlow(nav) : -1.0;
    if (!(flow >= 0.0 && flow <= maxFlow)) return -1.0;
    return flow / maxFlow;
}

bool ResourceHasRoom(int reference, ArrayList selected, float minimum)
{
    if (minimum <= 0.0) return true;
    float origin[3], other[3];
    GetEntPropVector(EntRefToEntIndex(reference), Prop_Data, "m_vecAbsOrigin", origin);
    for (int i = 0; i < selected.Length; i++)
    {
        int entity = EntRefToEntIndex(selected.Get(i));
        if (entity == INVALID_ENT_REFERENCE) continue;
        GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", other);
        if (GetVectorDistance(origin, other) < minimum) return false;
    }
    return true;
}

void ApplyDistribution(ArrayList matches, ArrayList saved, ResourcePolicy policy, bool category, int[] reasons)
{
    int count = matches.Length;
    if (count == 0) return;
    // One random tie order for new candidates. Decisions are retained until the
    // round resets, including virtual removals in preview mode.
    for (int i = count - 1; i > 0; i--)
    {
        int other = GetRandomInt(0, i);
        int value = matches.Get(i);
        matches.Set(i, matches.Get(other));
        matches.Set(other, value);
    }
    float[] flow = new float[count];
    bool route = policy.finale || !L4D_IsMissionFinalMap();
    float maxFlow = route ? L4D2Direct_GetMapMaxFlowDistance() : 0.0;
    bool validLength = maxFlow > 0.0 && maxFlow < 3.402823466e38;
    int known;
    for (int i = 0; i < count; i++)
    {
        flow[i] = validLength ? ResourceFlowFraction(EntRefToEntIndex(matches.Get(i)), maxFlow) : -1.0;
        if (flow[i] >= 0.0) known++;
    }
    float[] savedFlow = new float[saved.Length];
    for (int i = 0; i < saved.Length; i++)
    {
        savedFlow[i] = validLength ? ResourceFlowFraction(EntRefToEntIndex(saved.Get(i)), maxFlow) : -1.0;
        if (savedFlow[i] >= 0.0) known++;
    }
    bool useFlow = route && validLength && known > 0;
    if (route && !useFlow && (policy.density > 0.0 || policy.flowMin > 0.0 || policy.flowMax < 1.0))
    {
        int warned;
        char warningKey[80];
        FormatEx(warningKey, sizeof(warningKey), "%s:%s", category ? "category" : "item", policy.name);
        if (!g_distributionWarnings.GetValue(warningKey, warned))
        {
            LogMessage("[ResourceRules] %s: no usable route data; density/window skipped, limit and min_distance still apply", policy.name);
            g_distributionWarnings.SetValue(warningKey, 1);
        }
    }

    int budget = count + saved.Length;
    if (policy.limit >= 0 && policy.limit < budget) budget = policy.limit;
    if (useFlow && policy.density > 0.0)
    {
        float quota = maxFlow / 1000.0 * (policy.flowMax - policy.flowMin) * policy.density;
        // Bound before integer conversion, including very large valid density.
        if (quota < float(budget)) budget = RoundToFloor(quota);
    }
    int slots = budget - saved.Length;
    if (slots < 0) slots = 0;
    int[] status = new int[count];
    bool[] chosen = new bool[count];
    ArrayList selected = saved.Clone();
    for (int i = 0; i < count; i++)
    {
        if (useFlow && flow[i] >= 0.0 && (flow[i] < policy.flowMin || flow[i] > policy.flowMax))
            status[i] = RR_WINDOW;
    }

    bool bounded = policy.limit >= 0 || (useFlow && policy.density > 0.0);
    if (bounded && useFlow && budget > 0)
    {
        bool[] occupied = new bool[budget];
        // Give anchors their nearest remaining target, so new items fill gaps
        // rather than concentrating around targets that already have supplies.
        for (int i = 0; i < saved.Length; i++)
        {
            int best = -1;
            float distance;
            for (int target = 0; target < budget; target++)
            {
                if (occupied[target]) continue;
                float wanted = policy.flowMin + (policy.flowMax - policy.flowMin) * (float(target) + 0.5) / float(budget);
                float delta = savedFlow[i] >= 0.0 ? FloatAbs(savedFlow[i] - wanted) : 0.0;
                if (best < 0 || delta < distance) { best = target; distance = delta; }
            }
            if (best >= 0) occupied[best] = true;
        }
        int left = (budget - 1) / 2, right = left + 1;
        for (int turn = 0; turn < budget && slots > 0; turn++)
        {
            int target = turn % 2 == 0 ? left-- : right++;
            if (occupied[target]) continue;
            float wanted = policy.flowMin + (policy.flowMax - policy.flowMin) * (float(target) + 0.5) / float(budget);
            int best = -1;
            float distance;
            for (int i = 0; i < count; i++)
            {
                if (chosen[i] || status[i] != RR_KEEP || flow[i] < 0.0) continue;
                if (!ResourceHasRoom(matches.Get(i), selected, policy.minDistance)) continue;
                float delta = FloatAbs(flow[i] - wanted);
                if (best < 0 || delta < distance) { best = i; distance = delta; }
            }
            if (best >= 0)
            {
                chosen[best] = true;
                selected.Push(matches.Get(best));
                slots--;
            }
        }
    }
    // Unknown-flow candidates fill only vacancies. Without a count constraint,
    // keep all spatially compatible candidates, preferring usable route data.
    for (int pass = 0; pass < 2 && slots > 0; pass++)
    {
        for (int i = 0; i < count && slots > 0; i++)
        {
            if (chosen[i] || status[i] != RR_KEEP) continue;
            bool hasFlow = useFlow && flow[i] >= 0.0;
            if ((pass == 0) != hasFlow) continue;
            if (!ResourceHasRoom(matches.Get(i), selected, policy.minDistance)) continue;
            chosen[i] = true;
            selected.Push(matches.Get(i));
            slots--;
        }
    }
    for (int i = count - 1; i >= 0; i--)
    {
        if (chosen[i]) continue;
        int reason = status[i];
        if (reason == RR_KEEP)
            reason = ResourceHasRoom(matches.Get(i), selected, policy.minDistance) ? RR_LIMIT : RR_SPACING;
        MarkResourceCull(EntRefToEntIndex(matches.Get(i)), reason, policy.name, reasons);
        matches.Erase(i);
    }
    if (g_visualize.IntValue > 0)
        LogMessage("[ResourceRules] %s: route=%d length=%.1f budget=%d anchors=%d new=%d", policy.name, useFlow, maxFlow, budget, saved.Length, matches.Length);
    delete selected;
}
