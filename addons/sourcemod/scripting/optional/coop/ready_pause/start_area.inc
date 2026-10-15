// Ready placement owns records and bounded requests, never the ready gate.
#define START_NAV_POINTS 8
#define START_CANDIDATES 24
#define START_CONFIRM_TIMEOUT 1.5
#define START_REQUEST_TIMEOUT 3.0

enum StartReturnState
{
    StartIdle,
    StartRequested,
    StartConfirming,
    StartDone
};

StartReturnState g_startReturn[MAXPLAYERS + 1];
bool g_startLimited[MAXPLAYERS + 1]; // Only an observed, input-free boundary loop.
bool g_startNotify[MAXPLAYERS + 1];
bool g_startBoundary[MAXPLAYERS + 1];
bool g_startCounted[MAXPLAYERS + 1];
bool g_startInput[MAXPLAYERS + 1];
float g_startLoopTimes[MAXPLAYERS + 1][3];
int g_startLoopCount[MAXPLAYERS + 1];
int g_startEpoch;
int g_startTeleportTick[MAXPLAYERS + 1];
float g_startDeadline[MAXPLAYERS + 1];
float g_startRequestDeadline[MAXPLAYERS + 1];
float g_startTarget[MAXPLAYERS + 1][3];
float g_startBirth[MAXPLAYERS + 1][3];
float g_startLanding[MAXPLAYERS + 1][3];
bool g_startHasBirth[MAXPLAYERS + 1];
bool g_startHasLanding[MAXPLAYERS + 1];
float g_startNextNotice[MAXPLAYERS + 1];
float g_startCandidates[MAXPLAYERS + 1][START_CANDIDATES][3];
int g_startCandidateCount[MAXPLAYERS + 1];
int g_startCandidateIndex[MAXPLAYERS + 1];
float g_startNav[START_NAV_POINTS][3];
int g_startNavCount;
bool g_startSourcesLoaded;
bool g_startHasHint;
bool g_startExplicit;
float g_startHint[3];
float g_startHintRadius;
bool g_startPlacement;

bool IsReadySurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVORS && IsPlayerAlive(client);
}

void StartArea_ClearRequest(int client)
{
    g_startReturn[client] = StartIdle;
    g_startCandidateCount[client] = 0;
    g_startCandidateIndex[client] = 0;
    g_startNotify[client] = false;
    g_startBoundary[client] = false;
    g_startCounted[client] = false;
}

void StartArea_ResetClient(int client)
{
    StartArea_ClearRequest(client);
    g_startLimited[client] = false;
    g_startInput[client] = false;
    g_startLoopCount[client] = 0;
    g_startHasBirth[client] = false;
    g_startHasLanding[client] = false;
    g_startNextNotice[client] = 0.0;
}

void StartArea_CancelRequests()
{
    g_startEpoch++;
    g_startPlacement = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        StartArea_ClearRequest(client);
        g_startLimited[client] = false;
        g_startLoopCount[client] = 0;
    }
}

void StartArea_ResetRound()
{
    StartArea_CancelRequests();
    g_startNavCount = 0;
    g_startSourcesLoaded = false;
    g_startHasHint = false;
    g_startExplicit = false;
    for (int client = 1; client <= MaxClients; client++) StartArea_ResetClient(client);
}

// Spawn is recorded before validation. Never infer birth from a later timer.
void StartArea_CaptureBirth(int client)
{
    if (!g_readyPhase || !IsReadySurvivor(client) || g_startHasBirth[client]) return;
    GetClientAbsOrigin(client, g_startBirth[client]);
    g_startHasBirth[client] = true;
}

public void StartArea_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    StartArea_CaptureBirth(GetClientOfUserId(event.GetInt("userid")));
}

public void StartArea_PlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_readyPhase) return;
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    if (!player || !bot) return;
    bool toPlayer = StrEqual(name, "bot_player_replace");
    int source = toPlayer ? bot : player;
    int target = toPlayer ? player : bot;
    StartArea_ClearRequest(target);
    g_startHasBirth[target] = g_startHasBirth[source];
    g_startHasLanding[target] = g_startHasLanding[source];
    g_startBirth[target] = g_startBirth[source];
    g_startLanding[target] = g_startLanding[source];
    g_startLimited[target] = g_startLimited[source];
    g_startLoopCount[target] = 0;
    // The outgoing entity no longer owns this survivor's history.
    StartArea_ResetClient(source);
}

void StartArea_ObserveInput(int client, int buttons, const float velocity[3])
{
    bool moving = (buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP | IN_DUCK | IN_LEFT | IN_RIGHT)) != 0
        || velocity[0] != 0.0 || velocity[1] != 0.0 || velocity[2] != 0.0;
    g_startInput[client] = moving;
    if (moving) g_startLoopCount[client] = 0;
}

void StartArea_Notice(int client, bool loop)
{
    if (GetEngineTime() < g_startNextNotice[client]) return;
    g_startNextNotice[client] = GetEngineTime() + 30.0;
    LogMessage("[Ready start] client=%N reason=%s", client, loop ? "input-free boundary loop" : "return fallback");
    if (!IsFakeClient(client))
        PrintToChat(client, "%t", loop ? "ReadyStartLoop" : "ReadyStartAreaUnavailable");
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

// Generated locations have no observation evidence. Sweep the full hull onto
// support rather than planting it at a center ray's height on a slope.
bool StartArea_PhysicalPoint(const float seed[3], float point[3])
{
    float top[3], bottom[3];
    top = seed;
    bottom = seed;
    top[2] += 18.0;
    bottom[2] -= 128.0;
    float mins[3] = {-16.0, -16.0, 0.0}, maxs[3] = {16.0, 16.0, 72.0};
    Handle trace = TR_TraceHullFilterEx(top, bottom, mins, maxs, MASK_PLAYERSOLID, StartArea_TraceFilter);
    bool valid = TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
    if (valid) TR_GetEndPosition(point, trace);
    delete trace;
    if (!valid) return false;
    point[2] += 0.5;
    top = point;
    top[2] += 36.0;
    return !(TR_GetPointContents(top) & MASK_WATER);
}

bool StartArea_Classify(const float point[3])
{
    float position[3];
    position = point;
    if (L4D_IsPositionInFirstCheckpoint(position)) return true;
    if (!g_startExplicit || FloatAbs(point[2] - g_startHint[2]) > 160.0) return false;
    float dx = point[0] - g_startHint[0], dy = point[1] - g_startHint[1];
    // Explicit MapInfo remains a fallback hint, not the Director boundary.
    return dx * dx + dy * dy <= g_startHintRadius * g_startHintRadius;
}

bool StartArea_ActualSafe(int client, bool returning = false)
{
    if (!(GetEntityFlags(client) & FL_ONGROUND)
        || GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2
        || GetEntProp(client, Prop_Send, "m_isIncapacitated")
        || GetEntProp(client, Prop_Send, "m_isHangingFromLedge")) return false;
    float actual[3];
    GetClientAbsOrigin(client, actual);
    return returning ? StartArea_Classify(actual) : L4D_IsPositionInFirstCheckpoint(actual);
}

bool StartArea_RecordSuitable(const float point[3])
{
    float waist[3];
    waist = point;
    waist[2] += 36.0;
    return StartArea_Classify(point) && !(TR_GetPointContents(waist) & MASK_WATER);
}

void StartArea_SaveLanding(int client, const float point[3])
{
    if (g_startHasLanding[client] || !g_startHasBirth[client]) return;
    if (GetVectorDistance(point, g_startBirth[client], true) < 256.0) return;
    g_startLanding[client] = point;
    g_startHasLanding[client] = true;
}

void StartArea_AddCandidate(int client, const float seed[3], bool generated = false)
{
    if (g_startCandidateCount[client] >= START_CANDIDATES) return;
    float point[3];
    point = seed;
    if (generated && !StartArea_PhysicalPoint(seed, point)) return;
    if (!StartArea_RecordSuitable(point)) return;
    for (int i = 0; i < g_startCandidateCount[client]; i++)
        if (GetVectorDistance(point, g_startCandidates[client][i], true) < 256.0) return;
    g_startCandidates[client][g_startCandidateCount[client]++] = point;
}

void StartArea_AddNearby(int client, const float center[3], int limit)
{
    int stop = g_startCandidateCount[client] + limit;
    StartArea_AddCandidate(client, center, true);
    for (int ring = 1; ring <= 2 && g_startCandidateCount[client] < stop; ring++)
        for (int direction = 0; direction < 8 && g_startCandidateCount[client] < stop; direction++)
        {
            float seed[3];
            seed = center;
            float angle = float(direction) * FLOAT_PI / 4.0;
            seed[0] += Cosine(angle) * float(ring) * 64.0;
            seed[1] += Sine(angle) * float(ring) * 64.0;
            StartArea_AddCandidate(client, seed, true);
        }
}

void StartArea_BuildCandidates(int client)
{
    g_startCandidateCount[client] = 0;
    g_startCandidateIndex[client] = 0;
    if (g_startHasBirth[client]) StartArea_AddCandidate(client, g_startBirth[client]);
    if (g_startHasLanding[client]) StartArea_AddCandidate(client, g_startLanding[client]);
    for (int other = 1; other <= MaxClients; other++)
        if (other != client && IsReadySurvivor(other) && g_startHasLanding[other])
            StartArea_AddCandidate(client, g_startLanding[other]);
    if (g_startHasHint) StartArea_AddNearby(client, g_startHint, 5);
    for (int i = 0; i < g_startNavCount; i++) StartArea_AddCandidate(client, g_startNav[i], true);
    for (int i = 0; i < g_startCandidateCount[client] && !g_startHasLanding[client]; i++)
        StartArea_SaveLanding(client, g_startCandidates[client][i]);
}

void StartArea_RequestReturn(int client, bool notify = false, bool boundary = false)
{
    if (!IsReadySurvivor(client)) return;
    if (boundary && (g_startLimited[client] || g_startPlacement || g_countdownTimer != null)) return;
    if (g_startReturn[client] == StartRequested || g_startReturn[client] == StartConfirming) return;
    StartArea_ClearRequest(client);
    g_startReturn[client] = StartRequested;
    g_startNotify[client] = notify;
    g_startBoundary[client] = boundary;
    g_startRequestDeadline[client] = GetEngineTime() + START_REQUEST_TIMEOUT;
    StartArea_BuildCandidates(client);
}

void StartArea_CountBoundaryTeleport(int client)
{
    if (!g_startBoundary[client] || g_startCounted[client]) return;
    g_startCounted[client] = true;
    if (g_startInput[client]) { g_startLoopCount[client] = 0; return; }
    float now = GetEngineTime();
    int count;
    for (int i = 0; i < g_startLoopCount[client]; i++)
        if (now - g_startLoopTimes[client][i] <= 5.0)
            g_startLoopTimes[client][count++] = g_startLoopTimes[client][i];
    if (count < 3) g_startLoopTimes[client][count++] = now;
    g_startLoopCount[client] = count;
    if (count >= 3)
    {
        g_startLimited[client] = true;
        StartArea_Notice(client, true);
    }
}

void StartArea_Teleport(int client, const float point[3])
{
    float velocity[3];
    SetReadyFrozen(client, false);
    TeleportEntity(client, point, NULL_VECTOR, velocity);
    SetEntPropFloat(client, Prop_Send, "m_flFallVelocity", 0.0);
    StartArea_CountBoundaryTeleport(client);
}

void StartArea_Finish(int client)
{
    g_startReturn[client] = StartDone;
    if (g_startNotify[client]) EmitSoundToClient(client, "ui/beep_error01.wav");
    g_startNotify[client] = false;
}

void StartArea_Fallback(int client)
{
    int source = g_startHasBirth[client] ? client : 0;
    if (!source)
        for (int other = 1; other <= MaxClients; other++)
            if (IsReadySurvivor(other) && g_startHasBirth[other]) { source = other; break; }
    if (source) StartArea_Teleport(client, g_startBirth[source]);
    StartArea_Notice(client, false);
    StartArea_Finish(client);
}

void StartArea_TryCandidate(int client)
{
    if (g_startCandidateIndex[client] >= g_startCandidateCount[client])
    {
        StartArea_Fallback(client);
        return;
    }
    int candidate = g_startCandidateIndex[client]++;
    g_startTarget[client] = g_startCandidates[client][candidate];
    g_startReturn[client] = StartConfirming;
    g_startTeleportTick[client] = GetGameTickCount();
    g_startDeadline[client] = GetEngineTime() + START_CONFIRM_TIMEOUT;
    StartArea_Teleport(client, g_startTarget[client]);
}

bool StartArea_AllFinished()
{
    int survivors;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        survivors++;
        if (g_startReturn[client] != StartDone) return false;
    }
    return survivors > 0;
}

void StartArea_FreezeLanded()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        bool grounded = (GetEntityFlags(client) & FL_ONGROUND) != 0
            && GetEntProp(client, Prop_Send, "m_nWaterLevel") < 2;
        if (g_startReturn[client] == StartDone && grounded) SetReadyFrozen(client, true);
        else if (GetEntityMoveType(client) == MOVETYPE_NONE) SetReadyFrozen(client, false);
    }
}

void StartArea_Tick()
{
    StartArea_LoadSources();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        bool active = g_startReturn[client] == StartRequested || g_startReturn[client] == StartConfirming;
        if (!active && StartArea_ActualSafe(client))
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            StartArea_SaveLanding(client, actual);
            g_startLimited[client] = false;
        }
        if ((g_startPlacement || g_countdownTimer != null) && g_startReturn[client] == StartIdle)
            StartArea_RequestReturn(client);
        if (g_startReturn[client] != StartRequested && g_startReturn[client] != StartConfirming) continue;
        if (GetEngineTime() >= g_startRequestDeadline[client])
        {
            StartArea_Fallback(client);
            continue;
        }
        if (g_startReturn[client] == StartConfirming)
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            if (GetGameTickCount() > g_startTeleportTick[client]
                && GetVectorDistance(actual, g_startTarget[client], true) <= 576.0
                && StartArea_ActualSafe(client, true))
            {
                if (StartArea_ActualSafe(client))
                {
                    StartArea_SaveLanding(client, actual);
                    g_startLimited[client] = false;
                }
                StartArea_Finish(client);
            }
            else if (GetEngineTime() >= g_startDeadline[client])
                g_startReturn[client] = StartRequested;
        }
        if (g_startReturn[client] == StartRequested) StartArea_TryCandidate(client);
    }
    if (g_countdownTimer != null) StartArea_FreezeLanded();
}