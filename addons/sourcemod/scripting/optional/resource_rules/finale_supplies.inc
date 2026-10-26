// Automatic finale supplies supplement explicit end regions; they do not
// redefine start/end areas for other consumers of saferoom detection.
ConVar g_finaleClusters;
bool g_finaleLatched, g_finaleEnabled, g_finaleActive, g_finaleStartCaptured;
ArrayList g_finaleProtected, g_finalePending, g_finaleStarts, g_finaleReplayRefs;
Handle g_finaleBatch;

void FinaleSupplies_Init()
{
	g_finaleClusters = CreateConVar("resource_finale_supply_clusters", "0",
		"Convert compact groups of four or more non-start finale medkit points to uncapped pills; takes effect next map.", _, true, 0.0, true, 1.0);
	g_finaleProtected = new ArrayList();
	g_finalePending = new ArrayList();
	g_finaleStarts = new ArrayList(3);
	g_finaleReplayRefs = new ArrayList();
}

void FinaleSupplies_NewMap()
{
	g_finaleLatched = false;
	g_finaleReplayRefs.Clear();
}

void FinaleSupplies_Latch()
{
	if (g_finaleLatched) return;
	g_finaleEnabled = g_finaleClusters.BoolValue;
	g_finaleLatched = true;
}

void FinaleSupplies_Reset()
{
	delete g_finaleBatch;
	g_finaleProtected.Clear();
	g_finalePending.Clear();
	g_finaleStarts.Clear();
	g_finaleActive = false;
	g_finaleStartCaptured = false;
}

void FinaleSupplies_MapEnd()
{
	// NO_MAPCHANGE has already closed map timers when OnMapEnd runs.
	g_finaleBatch = null;
}

void FinaleSupplies_Begin()
{
	g_finaleActive = g_policyFile && g_finaleEnabled && L4D_IsMissionFinalMap();
	if (!g_replayingSupplies) g_finaleReplayRefs.Clear();
	if (!g_finaleActive || g_finaleStartCaptured) return;
	g_finaleStartCaptured = true;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client)) continue;
		float origin[3];
		GetClientAbsOrigin(client, origin);
		g_finaleStarts.PushArray(origin);
	}
}

bool FinaleSupplies_OutsideStart(const float point[3])
{
	SafeDetectResult result = SAFEDETECT_QueryPoint(point, SafeDetect_Start, SafeDetect_MapInfoFirst);
	if (result != SafeDetect_Unavailable) return result == SafeDetect_Outside;
	float ground[3];
	ground = point;
	if (L4D_IsPositionInFirstCheckpoint(ground)) return false;
	// A false checkpoint query can mean missing NAV flags, not "outside".
	// Require independent opening positions before relying on that result.
	if (!g_finaleStarts.Length) return false;
	for (int i = 0; i < g_finaleStarts.Length; i++)
	{
		float start[3];
		g_finaleStarts.GetArray(i, start);
		if (GetVectorDistance(start, point) <= 256.0) return false;
	}
	return true;
}

bool FinaleSupplies_IsProtected(int entity)
{
	return g_finaleProtected.FindValue(EntIndexToEntRef(entity)) != -1;
}

bool FinaleSupplies_IsPending(int entity)
{
	return g_finalePending.FindValue(EntIndexToEntRef(entity)) != -1;
}

bool FinaleSupplies_Candidate(int entity)
{
	if (!IsValidEntity(entity) || IsPlayerEquipment(entity)) return false;
	char name[64];
	GetResourceName(entity, name, sizeof(name));
	if (!StrEqual(name, "first_aid_kit")) return false;
	if (HasEntProp(entity, Prop_Data, "m_itemCount") && GetEntProp(entity, Prop_Data, "m_itemCount") <= 0) return false;
	float point[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", point);
	return FinaleSupplies_OutsideStart(point);
}

void FinaleSupplies_Scan()
{
	if (!g_finaleActive) return;
	ArrayList candidates = new ArrayList();
	for (int entity = MaxClients + 1; entity < GetMaxEntities(); entity++)
		if (FinaleSupplies_Candidate(entity)) candidates.Push(EntIndexToEntRef(entity));
	FinaleSupplies_Classify(candidates);
	delete candidates;
}

void FinaleSupplies_Classify(ArrayList candidates)
{
	// Seed every candidate; pairwise distances bound each group, so nearby
	// chains cannot turn scattered route supplies into one giant cluster.
	ArrayList group = new ArrayList();
	for (int seed = 0; seed < candidates.Length; seed++)
	{
		int first = EntRefToEntIndex(candidates.Get(seed));
		if (first == INVALID_ENT_REFERENCE || !FinaleSupplies_Candidate(first)) continue;
		group.Clear();
		group.Push(candidates.Get(seed));
		for (int i = 0; i < candidates.Length; i++)
		{
			if (i == seed) continue;
			int entity = EntRefToEntIndex(candidates.Get(i));
			if (entity == INVALID_ENT_REFERENCE || !FinaleSupplies_Candidate(entity)) continue;
			float point[3];
			GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", point);
			bool fits = true;
			for (int j = 0; j < group.Length; j++)
			{
				float other[3];
				GetEntPropVector(EntRefToEntIndex(group.Get(j)), Prop_Data, "m_vecAbsOrigin", other);
				float distance = GetVectorDistance(point, other);
				// Coincident entities are one refresh point, not multiple supplies.
				if (distance < 1.0 || distance > 128.0) { fits = false; break; }
			}
			if (fits) group.Push(candidates.Get(i));
		}
		if (group.Length < 4) continue;
		for (int i = 0; i < group.Length; i++)
			if (g_finaleProtected.FindValue(group.Get(i)) == -1) g_finaleProtected.Push(group.Get(i));
	}
	delete group;
}

bool FinaleSupplies_Queue(int entity, const char[] name)
{
	if (!g_finaleActive || !StrEqual(name, "first_aid_kit")) return false;
	int reference = EntIndexToEntRef(entity);
	if (g_finalePending.FindValue(reference) == -1) g_finalePending.Push(reference);
	if (g_finaleBatch == null)
		g_finaleBatch = CreateTimer(0.2, FinaleSupplies_ProcessBatch, _, TIMER_FLAG_NO_MAPCHANGE);
	return true;
}

public Action FinaleSupplies_ProcessBatch(Handle timer)
{
	g_finaleBatch = null;
	ArrayList batch = g_finalePending;
	g_finalePending = new ArrayList();
	FinaleSupplies_Classify(batch);
	for (int i = 0; i < batch.Length; i++)
	{
		int entity = EntRefToEntIndex(batch.Get(i));
		if (entity != INVALID_ENT_REFERENCE) ProcessResource(entity);
	}
	delete batch;
	QueueLimitPass();
	return Plugin_Stop;
}

void FinaleSupplies_Transfer(int source, int target)
{
	if (!FinaleSupplies_IsProtected(source)) return;
	int reference = EntIndexToEntRef(target);
	g_finaleProtected.Push(reference);
	// Preserve snapshot identity, not location: co-located ordinary pills must
	// never inherit this exception when ItemTracking restores a later round.
	if (g_initializationPending && !g_replayingSupplies)
		g_finaleReplayRefs.Push(reference);
}

void FinaleSupplies_Replayed(int entity, int previousRef)
{
	if (!g_finaleActive || !g_replayingSupplies) return;
	int index = g_finaleReplayRefs.FindValue(previousRef);
	if (index == -1) return;
	int reference = EntIndexToEntRef(entity);
	g_finaleProtected.Push(reference);
	g_finaleReplayRefs.Set(index, reference);
}

void FinaleSupplies_Destroyed(int entity)
{
	if (entity <= MaxClients || g_finaleProtected == null) return;
	// Destroy callbacks can run after reference invalidation; discard stale
	// entries too. This is event driven and never walks the server entity list.
	for (int i = g_finaleProtected.Length - 1; i >= 0; i--)
	{
		int current = EntRefToEntIndex(g_finaleProtected.Get(i));
		if (current == entity || current == INVALID_ENT_REFERENCE) g_finaleProtected.Erase(i);
	}
}
