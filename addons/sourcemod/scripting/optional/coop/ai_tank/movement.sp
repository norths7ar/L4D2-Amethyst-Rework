// Geometry-based opportunities. No path search, victim override or aim snapping.
// Climb playback rates retain the existing tank_climb / Anne ladder-boost behavior.
public void OnPostThink(int client) {
    if (!g_enable.BoolValue || !g_climbEnable.BoolValue || !IsAITank(client)
        || GetEntityMoveType(client) == MOVETYPE_LADDER) { RestoreRate(client); return; }
    int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
    float rate = 1.0;
    // Built-in hulk model sequence numbers, not activity enum values.
    if (sequence >= 16 && sequence <= 19) rate = g_lowRate.FloatValue;
    else if (sequence >= 20 && sequence <= 23) rate = g_highRate.FloatValue;
    if (rate <= 1.0) { RestoreRate(client); return; }
    if (!g_boosted[client]) g_previousRate[client] = GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate");
    g_boosted[client] = true;
    g_appliedRate[client] = rate;
    SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", rate);
}
void RestoreRate(int client) {
    if (!g_boosted[client]) return;
    if (FloatAbs(GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate") - g_appliedRate[client]) < 0.001)
        SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", g_previousRate[client]);
    g_boosted[client] = false;
}

bool TryHittable(int tank, int target, const float targetPos[3], int &buttons) {
    if (!g_hittables.BoolValue || GetGameTime() < g_nextPunch[tank] || !InFront(tank, targetPos, 0.85)) return false;
    float eye[3], facing[3], forwardVector[3], end[3], origin[3], chest[3];
    GetClientAbsOrigin(tank, origin);
    for (int axis = 0; axis < 3; axis++) chest[axis] = targetPos[axis];
    chest[2] += 45.0;
    float targetDistance = GetVectorDistance(origin, targetPos);
    if (targetDistance <= FindConVar("tank_swing_range").FloatValue || targetDistance > 650.0
        || FloatAbs(targetPos[2] - origin[2]) > 100.0 || !VisiblePoint(tank, target, chest)) return false;
    GetClientEyePosition(tank, eye); GetClientEyeAngles(tank, facing);
    GetAngleVectors(facing, forwardVector, NULL_VECTOR, NULL_VECTOR);
    float reach = FindConVar("tank_swing_range").FloatValue;
    for (int axis = 0; axis < 3; axis++) end[axis] = eye[axis] + forwardVector[axis] * reach;
    float mins[3] = {-16.0, -16.0, -32.0}, maxs[3] = {16.0, 16.0, 16.0};
    Handle trace = TR_TraceHullFilterEx(eye, end, mins, maxs, MASK_SHOT, TraceNotSelf, tank);
    int prop = TR_GetEntityIndex(trace);
    float hit[3]; TR_GetEndPosition(hit, trace);
    bool hitProp = TR_DidHit(trace) && !TR_StartSolid(trace);
    delete trace;
    // Rework's hittable detection uses the engine's Tank-glow flag, not a model list.
    if (!hitProp || prop <= MaxClients || !IsValidEntity(prop)
        || !HasEntProp(prop, Prop_Send, "m_hasTankGlow") || !GetEntProp(prop, Prop_Send, "m_hasTankGlow")) return false;
    float toward[3]; MakeVectorFromPoints(hit, targetPos, toward); toward[2] = 0.0;
    forwardVector[2] = 0.0; NormalizeVector(forwardVector, forwardVector); NormalizeVector(toward, toward);
    if (GetVectorDotProduct(forwardVector, toward) < 0.94) return false;
    // Do not add an attack during the claw cooldown or hammer the same prop every frame.
    int claw = GetEntPropEnt(tank, Prop_Send, "m_hActiveWeapon");
    if (claw <= MaxClients || !IsValidEntity(claw)
        || GetEntPropFloat(claw, Prop_Send, "m_flNextPrimaryAttack") > GetGameTime()) return false;
    buttons &= ~(IN_JUMP | IN_DUCK);
    buttons |= IN_ATTACK;
    g_nextPunch[tank] = GetGameTime() + 1.5;
    return true;
}

bool HullClear(int tank, const float from[3], const float to[3], const float mins[3], const float maxs[3]) {
    Handle trace = TR_TraceHullFilterEx(from, to, mins, maxs, MASK_PLAYERSOLID, TraceNotSelf, tank);
    bool clear = !TR_DidHit(trace) && !TR_StartSolid(trace) && !TR_AllSolid(trace);
    delete trace;
    return clear;
}
bool FindTop(int tank, const float sample[3], float bottomZ, float top[3]) {
    float bottom[3]; for (int axis = 0; axis < 3; axis++) bottom[axis] = sample[axis];
    bottom[2] = bottomZ;
    Handle trace = TR_TraceRayFilterEx(sample, bottom, MASK_PLAYERSOLID, RayType_EndPoint, TraceNotSelf, tank);
    float normal[3]; TR_GetPlaneNormal(trace, normal);
    bool found = TR_DidHit(trace) && !TR_StartSolid(trace) && normal[2] >= 0.9;
    int entity = TR_GetEntityIndex(trace);
    TR_GetEndPosition(top, trace); delete trace;
    // Never jump onto players or moving physics; default navigation still handles them.
    if (!found || (entity > 0 && entity <= MaxClients)) return false;
    if (entity > MaxClients && GetEntityMoveType(entity) != MOVETYPE_NONE && GetEntityMoveType(entity) != MOVETYPE_PUSH) return false;
    if (entity > MaxClients && HasEntProp(entity, Prop_Data, "m_vecVelocity")) {
        float motion[3]; GetEntPropVector(entity, Prop_Data, "m_vecVelocity", motion);
        if (GetVectorLength(motion) > 1.0) return false;
    }
    return true;
}
bool HasTopSupport(int tank, const float point[3]) {
    int supported;
    for (int probe = 0; probe < 5; probe++) {
        float start[3], top[3]; for (int axis = 0; axis < 3; axis++) start[axis] = point[axis];
        if (probe == 1) start[0] += 8.0;
        if (probe == 2) start[0] -= 8.0;
        if (probe == 3) start[1] += 8.0;
        if (probe == 4) start[1] -= 8.0;
        start[2] += 8.0;
        bool found = FindTop(tank, start, point[2] - 8.0, top);
        if (probe == 0 && !found) return false;
        if (found && FloatAbs(top[2] - point[2]) <= 5.0) supported++;
    }
    return supported >= 3;
}

bool TryObstacleJump(int tank, int target, const float position[3], const float targetPos[3], int &buttons, float vel[3]) {
    if (!g_obstacleJump.BoolValue || !InFront(tank, targetPos, 0.85)) return false;
    float direction[3]; MakeVectorFromPoints(position, targetPos, direction); direction[2] = 0.0;
    if (NormalizeVector(direction, direction) < 60.0) return false;
    float mins[3], maxs[3], ahead[3];
    GetEntPropVector(tank, Prop_Send, "m_vecMins", mins); GetEntPropVector(tank, Prop_Send, "m_vecMaxs", maxs);
    for (int axis = 0; axis < 3; axis++) ahead[axis] = position[axis] + direction[axis] * 80.0;
    ahead[2] += 2.0;
    // An actual obstacle must obstruct pursuit; do not hop onto arbitrary nearby scenery.
    if (HullClear(tank, position, ahead, mins, maxs)) return false;
    float gravityScale = GetEntPropFloat(tank, Prop_Data, "m_flGravity");
    if (gravityScale == 0.0) gravityScale = 1.0;
    float gravity = FindConVar("sv_gravity").FloatValue * gravityScale;
    if (gravity <= 0.0) return false;
    for (int step = 0; step < 4; step++) {
        float distance = 50.0 + float(step) * 25.0;
        float sample[3], landing[3];
        for (int axis = 0; axis < 3; axis++) sample[axis] = position[axis] + direction[axis] * distance;
        sample[2] = position[2] + 82.0;
        if (!FindTop(tank, sample, position[2] + 18.0, landing)) continue;
        float rise = landing[2] - position[2];
        if (rise < 20.0 || rise > 80.0 || !HasTopSupport(tank, landing)) continue;
        landing[2] += 2.0;
        if (!HullClear(tank, landing, landing, mins, maxs)) continue;
        if (GetVectorDistance(landing, targetPos) >= GetVectorDistance(position, targetPos)) continue;
        // Ballistic jump ending on the descending side, 24 units above the top at apex.
        float vertical = SquareRoot(2.0 * gravity * (rise + 26.0));
        float time = (vertical + SquareRoot(vertical * vertical - 2.0 * gravity * (rise + 2.0))) / gravity;
        float speed = distance / time;
        if (speed > 300.0) continue;
        float previous[3], point[3], launch[3];
        for (int axis = 0; axis < 3; axis++) previous[axis] = position[axis];
        previous[2] += 2.0;
        bool clear = true;
        for (int segment = 1; segment <= 12; segment++) {
            float t = time * float(segment) / 12.0;
            point[0] = position[0] + direction[0] * speed * t;
            point[1] = position[1] + direction[1] * speed * t;
            point[2] = position[2] + vertical * t - 0.5 * gravity * t * t;
            if (!HullClear(tank, previous, point, mins, maxs)) { clear = false; break; }
            for (int axis = 0; axis < 3; axis++) previous[axis] = point[axis];
        }
        if (!clear) continue;
        launch[0] = direction[0] * speed; launch[1] = direction[1] * speed; launch[2] = vertical;
        // Physical launch, not a position teleport or a mid-animation cancellation.
        SetEntPropEnt(tank, Prop_Send, "m_hGroundEntity", -1);
        SetEntityFlags(tank, GetEntityFlags(tank) & ~FL_ONGROUND);
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, launch);
        buttons &= ~(IN_JUMP | IN_DUCK);
        vel[0] = vel[1] = 0.0;
        g_jumpUntil[tank] = GetGameTime() + time + 0.8;
        g_jumpTarget[tank] = GetClientUserId(target);
        for (int axis = 0; axis < 3; axis++) g_jumpLanding[tank][axis] = landing[axis];
        return true;
    }
    return false;
}

bool ContinueObstacleJump(int tank, int target, int &buttons, float vel[3]) {
    if (g_jumpUntil[tank] <= GetGameTime() || !g_obstacleJump.BoolValue
        || g_jumpTarget[tank] != GetClientUserId(target)) { g_jumpUntil[tank] = 0.0; return false; }
    buttons &= ~(IN_JUMP | IN_DUCK);
    if (!(GetEntityFlags(tank) & FL_ONGROUND)) {
        // Do not add bhop impulse or air steering on top of the tested launch arc.
        vel[0] = vel[1] = 0.0;
        buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
        return true;
    }
    float position[3], targetPos[3], next[3], direction[3], mins[3], maxs[3];
    GetClientAbsOrigin(tank, position); GetClientAbsOrigin(target, targetPos);
    if (FloatAbs(position[2] - g_jumpLanding[tank][2]) > 10.0 || !HasTopSupport(tank, position)) {
        g_jumpUntil[tank] = 0.0; return false;
    }
    // Briefly evaluate from the top instead of instantly following a side-switch down.
    // Keep Valve's aim and attack; only permit horizontal movement onto supported top.
    MakeVectorFromPoints(position, targetPos, direction); direction[2] = 0.0;
    NormalizeVector(direction, direction);
    for (int axis = 0; axis < 3; axis++) next[axis] = position[axis] + direction[axis] * 24.0;
    GetEntPropVector(tank, Prop_Send, "m_vecMins", mins); GetEntPropVector(tank, Prop_Send, "m_vecMaxs", maxs);
    if (GetVectorDistance(position, targetPos) < hCvarTankBhopStopDistance.FloatValue
        || !HasTopSupport(tank, next) || !HullClear(tank, position, next, mins, maxs)) {
        vel[0] = vel[1] = 0.0;
        buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
        float motion[3]; GetEntPropVector(tank, Prop_Data, "m_vecVelocity", motion);
        motion[0] = motion[1] = 0.0;
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, motion);
    }
    return true;
}
