// Ready placement owns records and bounded requests, never the ready gate.
#define START_NAV_POINTS 8
#define START_CANDIDATES 24
#define START_CONFIRM_TIMEOUT 1.5
#define START_REQUEST_TIMEOUT 3.0
#define START_SETTLE_TIME 0.1

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
bool g_startNativeBirth[MAXPLAYERS + 1];
bool g_startAwaitLanding[MAXPLAYERS + 1];
int g_startBirthTick[MAXPLAYERS + 1];
float g_startSettleSince[MAXPLAYERS + 1];
float g_startSettlePoint[MAXPLAYERS + 1][3];
float g_startReturnOrigin[MAXPLAYERS + 1][3];
bool g_startIntroPositions;
bool g_startCaptureBirth = true;
float g_startNextNotice[MAXPLAYERS + 1];
float g_startCandidates[MAXPLAYERS + 1][START_CANDIDATES][3];
bool g_startCandidateNative[MAXPLAYERS + 1][START_CANDIDATES];
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

bool StartArea_FreeNoclip(int client)
{
    return g_readyPhase && !g_startPlacement && g_countdownTimer == null
        && IsReadySurvivor(client) && GetEntityMoveType(client) == MOVETYPE_NOCLIP;
}

void StartArea_ResetClient(int client)
{
    StartArea_ClearRequest(client);
    g_startLimited[client] = false;
    g_startInput[client] = false;
    g_startLoopCount[client] = 0;
    g_startHasBirth[client] = false;
    g_startHasLanding[client] = false;
    g_startNativeBirth[client] = false;
    g_startAwaitLanding[client] = false;
    g_startSettleSince[client] = 0.0;
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
    g_startCaptureBirth = true;
    g_startIntroPositions = false;
    g_startNavCount = 0;
    g_startSourcesLoaded = false;
    g_startHasHint = false;
    g_startExplicit = false;
    for (int client = 1; client <= MaxClients; client++) StartArea_ResetClient(client);
}

// Capture even before round_start/OnMapStart. Only a spawn event is native
// evidence; a late-load snapshot remains an ordinary fallback record.
void StartArea_CaptureBirth(int client, bool nativeSpawn = true)
{
    if (!g_startCaptureBirth || !IsReadySurvivor(client)) return;
    // A real spawn supersedes a late-load snapshot, never an existing native birth.
    if (g_startHasBirth[client] && (!nativeSpawn || g_startNativeBirth[client])) return;
    GetClientAbsOrigin(client, g_startBirth[client]);
    g_startHasBirth[client] = true;
    g_startNativeBirth[client] = nativeSpawn;
    g_startAwaitLanding[client] = nativeSpawn;
    // player_spawn can precede final placement, even with FL_ONGROUND set.
    g_startBirthTick[client] = GetGameTickCount();
    g_startSettleSince[client] = 0.0;
}

public void StartArea_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    StartArea_CaptureBirth(GetClientOfUserId(event.GetInt("userid")));
}

public void StartArea_PlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_startCaptureBirth) return;
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    if (!player || !bot) return;
    bool toPlayer = StrEqual(name, "bot_player_replace");
    int source = toPlayer ? bot : player;
    int target = toPlayer ? player : bot;
    StartArea_ClearRequest(target);
    // A replacement may already have received its own spawn event. An empty
    // outgoing slot must not erase it; otherwise history follows the body.
    if (g_startHasBirth[source])
    {
        g_startHasBirth[target] = true;
        g_startHasLanding[target] = g_startHasLanding[source];
        g_startBirth[target] = g_startBirth[source];
        g_startLanding[target] = g_startLanding[source];
        g_startNativeBirth[target] = g_startNativeBirth[source];
        g_startAwaitLanding[target] = g_startAwaitLanding[source];
        g_startBirthTick[target] = GetGameTickCount();
        g_startSettleSince[target] = 0.0;
    }
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
    if (moving)
    {
        g_startLoopCount[client] = 0;
        // Inputs during a map-controlled intro cannot move the player yet.
        // Once released, never promote a later ready-phase walk into birth evidence.
        if (!StartArea_IntroControlled(client)) g_startAwaitLanding[client] = false;
    }
}

bool StartArea_IntroControlled(int client)
{
    if (!IsStartInitialized()) return true;
    if (g_startIntroPositions || L4D_IsInIntro()) return true;
    int camera = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
    if (camera <= MaxClients || !IsValidEntity(camera)) return false;
    char classname[64];
    GetEntityClassname(camera, classname, sizeof(classname));
    return StrContains(classname, "point_viewcontrol") == 0
        || StrEqual(classname, "point_deathfall_camera");
}

public void L4D_OnForceSurvivorPositions_Pre()
{
    if (!g_startCaptureBirth) return;
    g_startIntroPositions = true;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        // Map-owned positioning supersedes an earlier pre-intro observation.
        g_startHasLanding[client] = false;
        g_startAwaitLanding[client] = g_startNativeBirth[client];
        g_startSettleSince[client] = 0.0;
    }
}

void StartArea_IntroReleased()
{
    if (!g_startCaptureBirth) return;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_startAwaitLanding[client]) continue;
        g_startBirthTick[client] = GetGameTickCount();
        g_startSettleSince[client] = 0.0;
    }
}

public void L4D_OnReleaseSurvivorPositions()
{
    g_startIntroPositions = false;
    StartArea_IntroReleased();
}

public void L4D_OnFinishIntro()
{
    // Finish can precede Release. Do not clear the forced-position state here.
    StartArea_IntroReleased();
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
        float flow = L4D2Direct_GetTerrorNavAreaFlow(area);
        if (flow < 0.0) continue;
        float point[3];
        L4D_GetNavAreaCenter(area, point);
        point[2] += 2.0;
        if (!StartArea_InFirstCheckpoint(point)) continue;
        float distance = g_startExplicit ? GetVectorDistance(point, g_startHint, true) : flow;
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

bool StartArea_InFirstCheckpoint(const float point[3])
{
    // Match Left4DHooks' lookup, but reject negative flow (including -9999).
    Address area = view_as<Address>(L4D_GetNearestNavArea(point, 1000.0, true, true, false));
    if (area == Address_Null || L4D2Direct_GetTerrorNavAreaFlow(area) < 0.0) return false;
    float position[3];
    position = point;
    return L4D_IsPositionInFirstCheckpoint(position);
}

bool StartArea_Classify(const float point[3])
{
    if (StartArea_InFirstCheckpoint(point)) return true;
    if (!g_startExplicit || FloatAbs(point[2] - g_startHint[2]) > 160.0) return false;
    float dx = point[0] - g_startHint[0], dy = point[1] - g_startHint[1];
    // Explicit MapInfo remains a fallback hint, not the Director boundary.
    return dx * dx + dy * dy <= g_startHintRadius * g_startHintRadius;
}

bool StartArea_PhysicallySafe(int client)
{
    return (GetEntityFlags(client) & FL_ONGROUND) != 0
        && GetEntProp(client, Prop_Send, "m_nWaterLevel") < 2
        && !GetEntProp(client, Prop_Send, "m_isIncapacitated")
        && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}

bool StartArea_ClearBody(int client)
{
    // Use the actual (possibly crouched) hull. Ignore only the bottom two
    // units touching the support surface, avoiding C2M1's slope false positive.
    // Deep embedding and side/ceiling obstruction still fail this check.
    float point[3], mins[3], maxs[3];
    GetClientAbsOrigin(client, point);
    GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
    mins[2] += 2.0;
    Handle trace = TR_TraceHullFilterEx(point, point, mins, maxs, MASK_PLAYERSOLID, StartArea_TraceFilter);
    bool clear = !TR_StartSolid(trace) && !TR_AllSolid(trace);
    delete trace;
    return clear;
}

bool StartArea_ActualSafe(int client, bool returning = false, bool nativePoint = false)
{
    if (!StartArea_PhysicallySafe(client) || !StartArea_ClearBody(client)) return false;
    if (nativePoint) return true;
    float actual[3];
    GetClientAbsOrigin(client, actual);
    return returning ? StartArea_Classify(actual) : StartArea_InFirstCheckpoint(actual);
}

bool StartArea_RecordSuitable(const float point[3], bool nativePoint)
{
    float waist[3];
    waist = point;
    waist[2] += 36.0;
    return (nativePoint || StartArea_Classify(point)) && !(TR_GetPointContents(waist) & MASK_WATER);
}

void StartArea_ObserveLanding(int client)
{
    if (!g_startAwaitLanding[client] || !IsReadySurvivor(client)) return;
    if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
    {
        g_startAwaitLanding[client] = false;
        return;
    }
    if (GetGameTickCount() <= g_startBirthTick[client] || StartArea_IntroControlled(client)
        || GetEntityMoveType(client) != MOVETYPE_WALK
        || !StartArea_PhysicallySafe(client) || !StartArea_ClearBody(client))
    {
        g_startSettleSince[client] = 0.0;
        return;
    }
    float actual[3];
    GetClientAbsOrigin(client, actual);
    if (g_startSettleSince[client] == 0.0 || GetVectorDistance(actual, g_startSettlePoint[client], true) > 1.0)
    {
        g_startSettlePoint[client] = actual;
        g_startSettleSince[client] = GetEngineTime();
        return;
    }
    if (GetEngineTime() - g_startSettleSince[client] < START_SETTLE_TIME) return;
    g_startAwaitLanding[client] = false;
    g_startLanding[client] = actual;
    g_startHasLanding[client] = true;
}

void StartArea_AddCandidate(int client, const float seed[3], bool generated = false, bool nativePoint = false)
{
    if (g_startCandidateCount[client] >= START_CANDIDATES) return;
    float point[3];
    point = seed;
    if (generated && !StartArea_PhysicalPoint(seed, point)) return;
    if (!StartArea_RecordSuitable(point, nativePoint)) return;
    // A late-load snapshot must not deduplicate a later native record.
    for (int i = 0; i < g_startCandidateCount[client]; i++)
        if (GetVectorDistance(point, g_startCandidates[client][i], true) < 256.0
            && (!nativePoint || g_startCandidateNative[client][i])) return;
    int slot = g_startCandidateCount[client]++;
    g_startCandidates[client][slot] = point;
    g_startCandidateNative[client][slot] = nativePoint;
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
    if (g_startHasLanding[client]) StartArea_AddCandidate(client, g_startLanding[client], false, true);
    for (int other = 1; other <= MaxClients; other++)
    {
        if (other == client || !IsReadySurvivor(other)) continue;
        if (g_startHasLanding[other]) StartArea_AddCandidate(client, g_startLanding[other], false, true);
    }
    if (g_startHasHint) StartArea_AddNearby(client, g_startHint, 5);
    for (int i = 0; i < g_startNavCount; i++) StartArea_AddCandidate(client, g_startNav[i], true);
    // Raw spawn snapshots are not observed landings. Validate their geometry
    // like a generated point; a native origin still does not need NAV's approval.
    if (g_startHasBirth[client]) StartArea_AddCandidate(client, g_startBirth[client], true, g_startNativeBirth[client]);
    for (int other = 1; other <= MaxClients; other++)
        if (other != client && IsReadySurvivor(other) && g_startHasBirth[other])
            StartArea_AddCandidate(client, g_startBirth[other], true, g_startNativeBirth[other]);
}

void StartArea_RequestReturn(int client, bool notify = false, bool boundary = false)
{
    if (!IsReadySurvivor(client)) return;
    if (boundary && StartArea_FreeNoclip(client)) return;
    if (boundary && (g_startLimited[client] || g_startPlacement || g_countdownTimer != null)) return;
    if (g_startReturn[client] == StartRequested || g_startReturn[client] == StartConfirming) return;
    StartArea_ClearRequest(client);
    g_startReturn[client] = StartRequested;
    g_startNotify[client] = notify;
    g_startBoundary[client] = boundary;
    g_startRequestDeadline[client] = GetEngineTime() + START_REQUEST_TIMEOUT;
    GetClientAbsOrigin(client, g_startReturnOrigin[client]);
    g_startAwaitLanding[client] = false;
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
    // Undo this request rather than reusing a raw/failed spawn candidate.
    if (g_startCandidateIndex[client] > 0) StartArea_Teleport(client, g_startReturnOrigin[client]);
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
    g_startSettleSince[client] = 0.0;
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
        bool grounded = !StartArea_IntroControlled(client)
            && StartArea_PhysicallySafe(client) && StartArea_ClearBody(client);
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
        if (StartArea_FreeNoclip(client))
        {
            // Noclip may be enabled after the boundary request was queued.
            // Explicit !return still works; countdown placement never exempts noclip.
            if (g_startBoundary[client])
            {
                StartArea_ClearRequest(client);
                active = false;
            }
            g_startLimited[client] = false;
            g_startLoopCount[client] = 0;
            if (!active) continue;
        }
        if (!active && StartArea_ActualSafe(client))
        {
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
        // Natural intros and skip-intro both release through the Director.
        // Do not fight map positioning; the existing request deadline still ends waiting.
        if (StartArea_IntroControlled(client))
        {
            g_startSettleSince[client] = 0.0;
            continue;
        }
        if (g_startReturn[client] == StartConfirming)
        {
            float actual[3];
            GetClientAbsOrigin(client, actual);
            bool safe = GetGameTickCount() > g_startTeleportTick[client]
                && GetVectorDistance(actual, g_startTarget[client], true) <= 576.0
                && !StartArea_IntroControlled(client)
                && StartArea_ActualSafe(client, true, g_startCandidateNative[client][g_startCandidateIndex[client] - 1]);
            if (!safe) g_startSettleSince[client] = 0.0;
            else if (g_startSettleSince[client] == 0.0 || GetVectorDistance(actual, g_startSettlePoint[client], true) > 1.0)
            {
                g_startSettleSince[client] = GetEngineTime();
                g_startSettlePoint[client] = actual;
            }
            else if (GetEngineTime() - g_startSettleSince[client] >= START_SETTLE_TIME)
            {
                if (StartArea_ActualSafe(client))
                {
                    g_startLimited[client] = false;
                }
                StartArea_Finish(client);
            }
            if (g_startReturn[client] == StartConfirming && GetEngineTime() >= g_startDeadline[client])
                g_startReturn[client] = StartRequested;
        }
        if (g_startReturn[client] == StartRequested) StartArea_TryCandidate(client);
    }
    if (g_countdownTimer != null) StartArea_FreezeLanded();
}
