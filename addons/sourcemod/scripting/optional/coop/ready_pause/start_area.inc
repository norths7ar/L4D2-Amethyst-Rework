// Private ready-up placement owner. MapInfo is a search hint, never a movement boundary.

#define START_OWN_POINTS 3
#define START_SHARED_POINTS 8
#define START_NAV_POINTS 8
#define START_CANDIDATES 24
#define START_CONFIRM_TIMEOUT 1.5

enum StartReturnState
{
    StartIdle,
    StartRequested,
    StartConfirming,
    StartConfirmed,
    StartWaiting
};

enum StartFailure
{
    StartNoCandidate,
    StartConfirmationFailed,
    StartDegraded,
    StartFailureCount
};

StartReturnState g_startReturn[MAXPLAYERS + 1];
bool g_startLimited[MAXPLAYERS + 1];
bool g_startDegraded[MAXPLAYERS + 1];
bool g_startNotify[MAXPLAYERS + 1];
int g_startEpoch;
int g_startRequestId[MAXPLAYERS + 1];
int g_startTeleportTick[MAXPLAYERS + 1];
float g_startDeadline[MAXPLAYERS + 1];
float g_startTarget[MAXPLAYERS + 1][3];
float g_startOwn[MAXPLAYERS + 1][START_OWN_POINTS][3];
int g_startOwnCount[MAXPLAYERS + 1];
float g_startShared[START_SHARED_POINTS][3];
int g_startSharedCount;
int g_startGeneration;
int g_startWaitGeneration[MAXPLAYERS + 1];
float g_startWaitPosition[MAXPLAYERS + 1][3];
float g_startNextProbe[MAXPLAYERS + 1];
float g_startNextNotice[MAXPLAYERS + 1];
float g_startNextLog[MAXPLAYERS + 1][StartFailureCount];
float g_startCandidates[MAXPLAYERS + 1][START_CANDIDATES][3];
int g_startCandidateCount[MAXPLAYERS + 1];
int g_startCandidateIndex[MAXPLAYERS + 1];
ArrayList g_startTried[MAXPLAYERS + 1];
float g_startNav[START_NAV_POINTS][3];
int g_startNavCount;
bool g_startSourcesLoaded;
bool g_startHasHint;
bool g_startExplicit;
float g_startHint[3];
float g_startHintRadius;
bool g_startPlacement;

void StartArea_ResetClient(int client)
{
    delete g_startTried[client];
    g_startRequestId[client]++;
    g_startReturn[client] = StartIdle;
    g_startLimited[client] = false;
    g_startDegraded[client] = false;
    g_startNotify[client] = false;
    g_startOwnCount[client] = 0;
    g_startCandidateCount[client] = 0;
    g_startNextNotice[client] = 0.0;
    g_startNextProbe[client] = 0.0;
    for (int reason = 0; reason < view_as<int>(StartFailureCount); reason++)
        g_startNextLog[client][reason] = 0.0;
}

void StartArea_CancelRequests()
{
    g_startEpoch++;
    g_startPlacement = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        delete g_startTried[client];
        g_startRequestId[client]++;
        g_startReturn[client] = StartIdle;
        g_startCandidateCount[client] = 0;
        // An unsafe/degraded survivor remains movement-limited until a safe
        // observation or phase reset; cancellation must not open the map.
    }
}

void StartArea_ResetRound()
{
    StartArea_CancelRequests();
    g_startSharedCount = 0;
    g_startGeneration = 0;
    g_startNavCount = 0;
    g_startSourcesLoaded = false;
    g_startHasHint = false;
    g_startExplicit = false;
    for (int client = 1; client <= MaxClients; client++) StartArea_ResetClient(client);
}

bool IsReadySurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVORS && IsPlayerAlive(client);
}

void StartArea_Log(int client, StartFailure reason)
{
    if (GetEngineTime() < g_startNextLog[client][reason]) return;
    g_startNextLog[client][reason] = GetEngineTime() + 30.0;
    static const char reasons[][] = {"no physical start candidate", "landing confirmation failed", "explicit MapInfo fallback; movement restricted"};
    LogMessage("[Ready start] client=%N reason=%s", client, reasons[reason]);
}

void StartArea_LoadSources()
{
    if (g_startSourcesLoaded || !IsStartInitialized()) return;
    g_startSourcesLoaded = true;
    if (GetFeatureStatus(FeatureType_Native, "LGO_GetMapAreas") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "LGO_IsMapDataAvailable") == FeatureStatus_Available)
    {
        float end[3], dist, extra, endDist;
        LGO_GetMapAreas(g_startHint, end, dist, extra, endDist);
        g_startHasHint = dist > 0.0;
        g_startHintRadius = FloatMax(128.0, FloatMin(384.0, FloatMax(dist, extra)));
        if (g_startHasHint && LGO_IsMapDataAvailable()
            && GetFeatureStatus(FeatureType_Native, "LGO_GetMapValueVector") == FeatureStatus_Available
            && GetFeatureStatus(FeatureType_Native, "LGO_GetMapValueFloat") == FeatureStatus_Available)
        {
            float missing[3] = {9999999.0, 9999999.0, 9999999.0}, raw[3];
            LGO_GetMapValueVector("start_point", raw, missing);
            float rawDist = LGO_GetMapValueFloat("start_dist", -1.0);
            g_startExplicit = rawDist > 0.0 && raw[0] != missing[0] && raw[1] != missing[1] && raw[2] != missing[2]
                && GetVectorDistance(raw, g_startHint, true) < 1.0;
        }
    }
    // Called by the existing boundary timer after configuration, not OnMapStart.
    // Keep only a small set of first-checkpoint NAV centers, never end checkpoints.
    ArrayList areas = new ArrayList();
    L4D_GetAllNavAreas(areas);
    float distances[START_NAV_POINTS];
    for (int i = 0; i < areas.Length; i++)
    {
        Address area = view_as<Address>(areas.Get(i));
        if (!(L4D_GetNavArea_SpawnAttributes(area) & (NAV_SPAWN_PLAYER_START | NAV_SPAWN_CHECKPOINT))) continue;
        float point[3];
        L4D_GetNavAreaCenter(area, point);
        point[2] += 2.0;
        if (!L4D_IsPositionInFirstCheckpoint(point)) continue;
        float distance = g_startHasHint ? GetVectorDistance(point, g_startHint, true) : L4D2Direct_GetTerrorNavAreaFlow(area);
        int slot = g_startNavCount;
        if (slot == START_NAV_POINTS)
        {
            slot = 0;
            for (int j = 1; j < START_NAV_POINTS; j++) if (distances[j] > distances[slot]) slot = j;
            if (distance >= distances[slot]) continue;
        }
        else g_startNavCount++;
        g_startNav[slot] = point;
        distances[slot] = distance;
    }
    delete areas;
}

float FloatMin(float a, float b) { return a < b ? a : b; }
float FloatMax(float a, float b) { return a > b ? a : b; }

public bool StartArea_TraceFilter(int entity, int contentsMask)
{
    return entity < 1 || entity > MaxClients;
}

// Always use the standing survivor hull, never the current crouched hull.
// Project onto actual support, then check the full hull without a head-height lift.
bool StartArea_PhysicalPoint(const float seed[3], float point[3])
{
    float top[3], bottom[3], normal[3];
    top = seed;
    bottom = seed;
    top[2] += 18.0;
    bottom[2] -= 128.0;
    Handle trace = TR_TraceRayFilterEx(top, bottom, MASK_PLAYERSOLID, RayType_EndPoint, StartArea_TraceFilter);
    bool floor = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
    if (floor)
    {
        TR_GetEndPosition(point, trace);
        TR_GetPlaneNormal(trace, normal);
        floor = normal[2] >= 0.7;
    }
    delete trace;
    if (!floor) return false;
    point[2] += 0.5;
    float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0};
    trace = TR_TraceHullFilterEx(point, point, mins, maxs, MASK_PLAYERSOLID, StartArea_TraceFilter);
    bool clear = !TR_StartSolid(trace) && !TR_AllSolid(trace) && !TR_DidHit(trace);
    delete trace;
    if (!clear) return false;
    // Waist-deep water is swimming, not a standing return location.
    top = point;
    top[2] += 36.0;
    if (TR_GetPointContents(top) & MASK_WATER) return false;
    // A center ray alone accepts ledges and tiny props. Require support around
    // the feet, with walkable normals and no drop larger than a normal step.
    for (int corner = 0; corner < 4; corner++)
    {
        top = point;
        top[0] += (corner & 1) ? 12.0 : -12.0;
        top[1] += (corner & 2) ? 12.0 : -12.0;
        top[2] += 18.0;
        bottom = top;
        bottom[2] -= 36.0;
        trace = TR_TraceRayFilterEx(top, bottom, MASK_PLAYERSOLID, RayType_EndPoint, StartArea_TraceFilter);
        bool support = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
        if (support)
        {
            TR_GetPlaneNormal(trace, normal);
            support = normal[2] >= 0.7;
        }
        delete trace;
        if (!support) return false;
    }
    return true;
}

bool StartArea_Classify(float point[3], bool &degraded)
{
    degraded = false;
    if (L4D_IsPositionInFirstCheckpoint(point)) return true;
    if (!g_startExplicit || FloatAbs(point[2] - g_startHint[2]) > 160.0) return false;
    float dx = point[0] - g_startHint[0], dy = point[1] - g_startHint[1];
    if (dx * dx + dy * dy > g_startHintRadius * g_startHintRadius) return false;
    // This envelope authorizes only a physically validated landing with active
    // movement suppressed. It never declares a sphere to be the safe-area boundary.
    degraded = true;
    return true;
}

bool StartArea_ActualSafe(int client, bool &degraded)
{
    if (!(GetEntityFlags(client) & FL_ONGROUND) || GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2) return false;
    float actual[3], floor[3];
    GetClientAbsOrigin(client, actual);
    if (!StartArea_PhysicalPoint(actual, floor) || FloatAbs(actual[2] - floor[2]) > 2.0) return false;
    return StartArea_Classify(floor, degraded);
}

void StartArea_Remember(int client, const float point[3])
{
    // Most-recent first; don't churn the shared generation while standing still.
    bool newOwn = g_startOwnCount[client] == 0 || GetVectorDistance(point, g_startOwn[client][0], true) > 256.0;
    if (newOwn)
    {
        for (int i = START_OWN_POINTS - 1; i > 0; i--) g_startOwn[client][i] = g_startOwn[client][i - 1];
        g_startOwn[client][0] = point;
        if (g_startOwnCount[client] < START_OWN_POINTS) g_startOwnCount[client]++;
    }
    for (int i = 0; i < g_startSharedCount; i++)
        if (GetVectorDistance(point, g_startShared[i], true) < 256.0) return;
    for (int i = START_SHARED_POINTS - 1; i > 0; i--) g_startShared[i] = g_startShared[i - 1];
    g_startShared[0] = point;
    if (g_startSharedCount < START_SHARED_POINTS) g_startSharedCount++;
    g_startGeneration++;
}

void StartArea_AddCandidate(int client, const float seed[3])
{
    if (g_startCandidateCount[client] == START_CANDIDATES) return;
    float point[3];
    bool degraded;
    if (!StartArea_PhysicalPoint(seed, point) || !StartArea_Classify(point, degraded)) return;
    if (StartArea_WasTried(client, point)) return;
    for (int i = 0; i < g_startCandidateCount[client]; i++)
        if (GetVectorDistance(point, g_startCandidates[client][i], true) < 64.0) return;
    g_startCandidates[client][g_startCandidateCount[client]++] = point;
}

void StartArea_AddNearby(int client, const float center[3], int limit)
{
    int stop = g_startCandidateCount[client] + limit;
    StartArea_AddCandidate(client, center);
    for (int ring = 1; ring <= 2 && g_startCandidateCount[client] < stop; ring++)
        for (int direction = 0; direction < 8 && g_startCandidateCount[client] < stop; direction++)
        {
            float seed[3];
            seed = center;
            float angle = float(direction) * FLOAT_PI / 4.0;
            seed[0] += Cosine(angle) * float(ring) * 64.0;
            seed[1] += Sine(angle) * float(ring) * 64.0;
            StartArea_AddCandidate(client, seed);
        }
}

void StartArea_BuildCandidates(int client)
{
    g_startCandidateCount[client] = 0;
    g_startCandidateIndex[client] = 0;
    for (int i = 0; i < g_startOwnCount[client]; i++) StartArea_AddCandidate(client, g_startOwn[client][i]);
    for (int i = 0; i < g_startSharedCount && i < 5; i++) StartArea_AddCandidate(client, g_startShared[i]);
    float position[3];
    GetClientAbsOrigin(client, position);
    StartArea_AddNearby(client, position, 5);
    if (g_startHasHint) StartArea_AddNearby(client, g_startHint, 5);
    for (int i = 0; i < g_startNavCount; i++) StartArea_AddCandidate(client, g_startNav[i]);
}

void StartArea_ProbeCandidates(int client)
{
    // The separate attempt history filters unchanged failed landings without
    // consuming slots needed for newly usable candidates in this bounded batch.
    StartArea_BuildCandidates(client);
    if (g_startCandidateCount[client] > 0) g_startReturn[client] = StartRequested;
}

bool StartArea_WasTried(int client, const float point[3])
{
    if (g_startTried[client] == null) return false;
    float previous[3];
    for (int i = 0; i < g_startTried[client].Length; i++)
    {
        g_startTried[client].GetArray(i, previous);
        if (GetVectorDistance(point, previous, true) < 64.0) return true;
    }
    return false;
}

void StartArea_RequestReturn(int client, bool notify = false)
{
    if (!IsReadySurvivor(client)) return;
    if (g_startReturn[client] == StartRequested || g_startReturn[client] == StartConfirming || g_startReturn[client] == StartWaiting) return;
    if (g_startReturn[client] == StartConfirmed && g_startDegraded[client])
    {
        float actual[3];
        bool degraded;
        GetClientAbsOrigin(client, actual);
        // Broken NAV keeps raising the Director boundary even at the accepted
        // landing. Merge that notification instead of teleporting in a loop.
        if (GetVectorDistance(actual, g_startTarget[client], true) <= 576.0
            && StartArea_ActualSafe(client, degraded)) return;
    }
    g_startRequestId[client]++;
    delete g_startTried[client];
    g_startReturn[client] = StartRequested;
    g_startLimited[client] = true;
    g_startNotify[client] = notify;
    g_startCandidateCount[client] = 0;
    g_startCandidateIndex[client] = 0;
}

void StartArea_Wait(int client)
{
    if (g_countdownTimer != null && GetEntityMoveType(client) == MOVETYPE_NONE)
        SetReadyFrozen(client, false);
    g_startReturn[client] = StartWaiting;
    g_startLimited[client] = true;
    g_startWaitGeneration[client] = g_startGeneration;
    GetClientAbsOrigin(client, g_startWaitPosition[client]);
    g_startNextProbe[client] = GetEngineTime() + 2.0;
    StartArea_Log(client, StartNoCandidate);
}

void StartArea_TryCandidate(int client)
{
    if (g_startCandidateIndex[client] >= g_startCandidateCount[client])
    {
        StartArea_Wait(client);
        return;
    }
    float point[3], velocity[3];
    bool degraded;
    int candidate = g_startCandidateIndex[client]++;
    if (!StartArea_PhysicalPoint(g_startCandidates[client][candidate], point) || !StartArea_Classify(point, degraded)) return;
    if (g_startTried[client] == null) g_startTried[client] = new ArrayList(3);
    g_startTried[client].PushArray(point);
    g_startTarget[client] = point;
    g_startDegraded[client] = degraded;
    g_startReturn[client] = StartConfirming;
    g_startTeleportTick[client] = GetGameTickCount();
    g_startDeadline[client] = GetEngineTime() + START_CONFIRM_TIMEOUT;
    // Keep gravity until actual landing is confirmed. Clearing velocity is part
    // of the teleport, not a recurring buoyancy override or an airborne freeze.
    SetReadyFrozen(client, false);
    TeleportEntity(client, point, NULL_VECTOR, velocity);
    SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", 0.0);
    DataPack request = new DataPack();
    request.WriteCell(GetClientSerial(client));
    request.WriteCell(g_startEpoch);
    request.WriteCell(g_startRequestId[client]);
    RequestFrame(StartArea_FrameConfirm, request);
}

public void StartArea_FrameConfirm(any data)
{
    DataPack request = view_as<DataPack>(data);
    request.Reset();
    int client = GetClientFromSerial(request.ReadCell());
    int epoch = request.ReadCell(), id = request.ReadCell();
    delete request;
    if (!client || epoch != g_startEpoch || id != g_startRequestId[client] || !g_readyPhase || !IsReadySurvivor(client)) return;
    StartArea_Confirm(client);
}

void StartArea_Confirm(int client)
{
    if (g_startReturn[client] != StartConfirming || GetGameTickCount() <= g_startTeleportTick[client]) return;
    float actual[3];
    bool degraded;
    GetClientAbsOrigin(client, actual);
    if (GetVectorDistance(actual, g_startTarget[client], true) <= 576.0
        && GetEntityMoveType(client) == MOVETYPE_WALK && StartArea_ActualSafe(client, degraded))
    {
        bool placing = g_startPlacement || g_countdownTimer != null;
        g_startReturn[client] = placing || degraded ? StartConfirmed : StartIdle;
        g_startDegraded[client] = degraded;
        g_startLimited[client] = degraded || placing;
        StartArea_Remember(client, actual);
        if (degraded) StartArea_Log(client, StartDegraded);
        if (g_startNotify[client]) EmitSoundToClient(client, "ui/beep_error01.wav");
        g_startNotify[client] = false;
        return;
    }
    if (GetEngineTime() < g_startDeadline[client]) return;
    StartArea_Log(client, StartConfirmationFailed);
    g_startReturn[client] = StartRequested;
    // Do not rebuild: failed candidates are consumed once per bounded batch.
}

bool StartArea_AllConfirmed()
{
    int survivors;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        survivors++;
        bool degraded;
        if (g_startReturn[client] != StartConfirmed || !StartArea_ActualSafe(client, degraded)) return false;
        if (degraded)
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            if (GetVectorDistance(actual, g_startTarget[client], true) > 576.0) return false;
        }
    }
    return survivors > 0;
}

void StartArea_Tick()
{
    StartArea_LoadSources();
    // Observe every player before resolving requests, so one player's newly
    // safe map placement can rescue another. No single failure locks the team.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        bool degraded;
        if (g_startReturn[client] == StartConfirming) continue;
        if (StartArea_ActualSafe(client, degraded))
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            if (!degraded || (g_startDegraded[client] && GetVectorDistance(actual, g_startTarget[client], true) <= 576.0))
            {
                StartArea_Remember(client, actual);
                if (!g_startPlacement && g_countdownTimer == null && g_startReturn[client] != StartRequested) g_startLimited[client] = degraded;
                if (g_startReturn[client] == StartWaiting && !degraded)
                {
                    // Map placement is new evidence. Still use next-frame
                    // teleport confirmation before admitting this player to start.
                    g_startReturn[client] = StartIdle;
                    StartArea_RequestReturn(client);
                }
            }
        }
    }
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        if (g_startReturn[client] == StartConfirmed)
        {
            bool degraded;
            float actual[3];
            GetClientAbsOrigin(client, actual);
            if (!StartArea_ActualSafe(client, degraded)
                || (degraded && GetVectorDistance(actual, g_startTarget[client], true) > 576.0))
            {
                // A map push after confirmation invalidates this candidate,
                // not the whole team. Continue the same bounded batch.
                if (GetEntityMoveType(client) == MOVETYPE_NONE) SetReadyFrozen(client, false);
                g_startReturn[client] = StartRequested;
                g_startLimited[client] = true;
            }
        }
        if ((g_startPlacement || g_countdownTimer != null) && g_startReturn[client] == StartIdle) StartArea_RequestReturn(client);
        if (g_startReturn[client] == StartConfirming) StartArea_Confirm(client);
        else if (g_startReturn[client] == StartWaiting)
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            if (g_startGeneration != g_startWaitGeneration[client]
                || GetVectorDistance(actual, g_startWaitPosition[client], true) > 256.0)
            {
                g_startReturn[client] = StartIdle;
                StartArea_RequestReturn(client);
            }
            else if (GetEngineTime() >= g_startNextProbe[client])
            {
                // Doors/props can change without moving a survivor. Search the
                // same sources, but only retry newly usable candidate positions.
                g_startNextProbe[client] = GetEngineTime() + 2.0;
                StartArea_ProbeCandidates(client);
            }
        }
        if (g_startReturn[client] == StartRequested)
        {
            if (g_startCandidateCount[client] == 0) StartArea_BuildCandidates(client);
            StartArea_TryCandidate(client);
        }
        if (g_startReturn[client] == StartWaiting && GetEngineTime() >= g_startNextNotice[client])
        {
            if (!IsFakeClient(client)) PrintToChat(client, "%t", "ReadyStartAreaUnavailable");
            g_startNextNotice[client] = GetEngineTime() + 30.0;
        }
    }
}
