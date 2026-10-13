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
bool FindTop(int tank, const float sample[3], float bottomZ, float top[3], float minimumNormalZ = 0.9) {
    float bottom[3]; for (int axis = 0; axis < 3; axis++) bottom[axis] = sample[axis];
    bottom[2] = bottomZ;
    Handle trace = TR_TraceRayFilterEx(sample, bottom, MASK_PLAYERSOLID, RayType_EndPoint, TraceNotSelf, tank);
    float normal[3]; TR_GetPlaneNormal(trace, normal);
    bool found = TR_DidHit(trace) && !TR_StartSolid(trace) && normal[2] >= minimumNormalZ;
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
    if (!g_obstacleJump.BoolValue || !InFront(tank, targetPos, 0.5)) return false;
    float toward[3]; MakeVectorFromPoints(position, targetPos, toward); toward[2] = 0.0;
    float targetDistance = NormalizeVector(toward, toward);
    if (targetDistance < 24.0) return false;
    float mins[3], maxs[3], ahead[3];
    GetEntPropVector(tank, Prop_Send, "m_vecMins", mins); GetEntPropVector(tank, Prop_Send, "m_vecMaxs", maxs);
    for (int axis = 0; axis < 3; axis++) ahead[axis] = position[axis] + toward[axis] * 80.0;
    ahead[2] += 2.0;
    // An actual obstacle must obstruct pursuit; do not hop onto arbitrary nearby scenery.
    if (HullClear(tank, position, ahead, mins, maxs)) return false;
    float gravityScale = GetEntPropFloat(tank, Prop_Data, "m_flGravity");
    if (gravityScale == 0.0) gravityScale = 1.0;
    float gravity = FindConVar("sv_gravity").FloatValue * gravityScale;
    if (gravity <= 0.0) return false;
    // Try forward first, then reachable side steps around seat backs. Collision and
    // support geometry, not campaign NAV quality, decide whether an arc is safe.
    float offsets[5] = {0.0, 30.0, -30.0, 60.0, -60.0};
    for (int candidate = 0; candidate < sizeof(offsets); candidate++) {
        float yaw = ArcTangent2(toward[1], toward[0]) + DegToRad(offsets[candidate]);
        float direction[3]; direction[0] = Cosine(yaw); direction[1] = Sine(yaw);
        for (int step = 0; step < 5; step++) {
            float distance = 50.0 + float(step) * 25.0;
            float sample[3], landing[3];
            for (int axis = 0; axis < 3; axis++) sample[axis] = position[axis] + direction[axis] * distance;
            sample[2] = position[2] + 82.0;
            if (!FindTop(tank, sample, position[2] + 18.0, landing)) continue;
            float rise = landing[2] - position[2];
            if (rise < 20.0 || rise > 80.0 || !HasTopSupport(tank, landing)) continue;
            landing[2] += 2.0;
            if (!HullClear(tank, landing, landing, mins, maxs)) continue;
            float remaining[3]; MakeVectorFromPoints(landing, targetPos, remaining); remaining[2] = 0.0;
            // A seat can be an intermediate step even before the raised table is reachable.
            if (GetVectorLength(remaining) >= targetDistance) continue;
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
            g_jumpUntil[tank] = GetGameTime() + time + 1.5;
            g_jumpTarget[tank] = GetClientUserId(target);
            for (int axis = 0; axis < 3; axis++) g_jumpLanding[tank][axis] = landing[axis];
            return true;
        }
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
    // A higher target needs another reachable step; a distant target should not
    // leave the Tank waiting on a table. Re-enter the normal opportunity scan.
    if (targetPos[2] > position[2] + 18.0 || GetVectorDistance(position, targetPos) > 180.0) {
        g_jumpUntil[tank] = 0.0;
        return false;
    }
    // Briefly evaluate from the top instead of instantly following a side-switch down.
    // Keep Valve's aim and attack; only permit horizontal movement onto supported top.
    MakeVectorFromPoints(position, targetPos, direction); direction[2] = 0.0;
    // Check the actual navigation command too: the NAV may request a sideways
    // detour off the seat even when the straight line toward the target is supported.
    if (FloatAbs(vel[0]) + FloatAbs(vel[1]) > 1.0) {
        float facing[3], forwardVector[3], right[3];
        GetClientEyeAngles(tank, facing); facing[0] = 0.0;
        GetAngleVectors(facing, forwardVector, right, NULL_VECTOR);
        direction[0] = forwardVector[0] * vel[0] + right[0] * vel[1];
        direction[1] = forwardVector[1] * vel[0] + right[1] * vel[1];
    }
    NormalizeVector(direction, direction);
    for (int axis = 0; axis < 3; axis++) next[axis] = position[axis] + direction[axis] * 24.0;
    GetEntPropVector(tank, Prop_Send, "m_vecMins", mins); GetEntPropVector(tank, Prop_Send, "m_vecMaxs", maxs);
    if (GetVectorDistance(position, targetPos) < 85.0
        || !HasTopSupport(tank, next) || !HullClear(tank, position, next, mins, maxs)) {
        vel[0] = vel[1] = 0.0;
        buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
        float motion[3]; GetEntPropVector(tank, Prop_Data, "m_vecVelocity", motion);
        motion[0] = motion[1] = 0.0;
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, motion);
    }
    return true;
}

// Short local recovery owns only usercmd movement, never persistent CommandABot
// MOVE. Every exit immediately returns navigation to Valve (Anne command lifecycle).
float g_stallSince[MAXPLAYERS + 1], g_stallOrigin[MAXPLAYERS + 1][3];
float g_retreatUntil[MAXPLAYERS + 1];
float g_retreatGoal[MAXPLAYERS + 1][3], g_recoveryAfter[MAXPLAYERS + 1];
float g_retreatCheck[MAXPLAYERS + 1];
float g_groundZ[MAXPLAYERS + 1], g_noHopUntil[MAXPLAYERS + 1];
bool g_haveGround[MAXPLAYERS + 1];
int g_recoveryAttempts[MAXPLAYERS + 1];
float g_recoveryOrigin[MAXPLAYERS + 1][3];
float g_hopUntil[MAXPLAYERS + 1], g_airThink[MAXPLAYERS + 1];
float g_recoveryFlightUntil[MAXPLAYERS + 1];
int g_lastRecoveryCandidate[MAXPLAYERS + 1];
bool g_hopPaused[MAXPLAYERS + 1];

void ResetTankHop(int tank) {
    g_hopUntil[tank] = 0.0;
}
float TankRunSpeed(int tank) {
    float speed = GetEntPropFloat(tank, Prop_Send, "m_flMaxspeed");
    return speed > 0.0 ? speed : 210.0;
}
float TankGravity(int tank) {
    float scale = GetEntPropFloat(tank, Prop_Data, "m_flGravity");
    if (scale <= 0.0) scale = 1.0;
    float gravity = FindConVar("sv_gravity").FloatValue * scale;
    return gravity > 0.0 ? gravity : 800.0;
}

// Anne-style route validation: collision sweeps plus a supported destination.
// No path snapshot dependency: use Valve's current movement direction, not a
// straight line to a victim behind a wall. Only modest floor-height changes.
bool TankHopRouteClear(int tank, const float position[3], const float velocity[3], float time) {
    float mins[3], maxs[3], previous[3], point[3], top[3], sample[3];
    GetClientMins(tank, mins); GetClientMaxs(tank, maxs);
    float gravity = TankGravity(tank);
    for (int axis = 0; axis < 2; axis++) sample[axis] = position[axis] + velocity[axis] * time;
    sample[2] = position[2] + velocity[2] * time - 0.5 * gravity * time * time + 18.0;
    if (!FindTop(tank, sample, sample[2] - 54.0, top, 0.7)) return false;
    // Solve the arrival time at that floor, then verify the actual landing there.
    float disc = velocity[2] * velocity[2] + 2.0 * gravity * (position[2] - top[2]);
    if (disc < 0.0) return false;
    time = (velocity[2] + SquareRoot(disc)) / gravity;
    if (time <= 0.0 || time > 1.0) return false;
    for (int axis = 0; axis < 2; axis++) sample[axis] = position[axis] + velocity[axis] * time;
    sample[2] = top[2] + 18.0;
    float landing[3];
    if (!FindTop(tank, sample, top[2] - 18.0, landing, 0.7) || FloatAbs(landing[2] - top[2]) > 2.0) return false;
    for (int corner = 0; corner < 4; corner++) {
        sample = landing;
        sample[0] += (corner & 1) ? maxs[0] : mins[0];
        sample[1] += (corner & 2) ? maxs[1] : mins[1];
        sample[2] += 18.0;
        if (!FindTop(tank, sample, landing[2] - 18.0, top, 0.7)) return false;
    }
    previous = position; previous[2] += 2.0;
    for (int segment = 1; segment <= 12; segment++) {
        float t = time * float(segment) / 12.0;
        point[0] = position[0] + velocity[0] * t;
        point[1] = position[1] + velocity[1] * t;
        point[2] = position[2] + velocity[2] * t - 0.5 * gravity * t * t + 2.0;
        if (!HullClear(tank, previous, point, mins, maxs)) return false;
        previous = point;
    }
    return true;
}

void TankAirControl(int tank, const float position[3], float velocity[3], const float wish[3], bool moving) {
    float now = GetGameTime();
    if (g_hopUntil[tank] <= now) return;
    float uncapped = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (uncapped > g_bhopMaxSpeed.FloatValue) {
        LimitHorizontalSpeed(velocity, g_bhopMaxSpeed.FloatValue);
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, velocity);
    }
    if (!moving || now < g_airThink[tank]) return;
    g_airThink[tank] = now + 0.05;
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (speed < 1.0) return;
    float dot = (velocity[0] * wish[0] + velocity[1] * wish[1]) / speed;
    float corrected[3]; corrected = velocity;
    // Like Anne: an angle beyond the air-turn range is braked toward run speed,
    // not instantaneously reversed. The ground-hop branch handles the reversal.
    if (dot < 0.017452) {
        float reduced = speed - 1500.0 * 0.05;
        float run = TankRunSpeed(tank);
        if (reduced < run) reduced = run;
        if (reduced >= speed) return;
        corrected[0] *= reduced / speed; corrected[1] *= reduced / speed;
    } else {
        if (dot > 0.996195) return;
        float direction[3];
        // Anne's 0.3s response, sampled at 0.05s; do not apply the full blend
        // every sample (which would turn six times more aggressively).
        float blend = 1.0 - Pow(0.7, 0.05 / 0.3);
        direction[0] = velocity[0] / speed * (1.0 - blend) + wish[0] * blend;
        direction[1] = velocity[1] / speed * (1.0 - blend) + wish[1] * blend;
        NormalizeVector(direction, direction);
        float turnDot = (direction[0] * velocity[0] + direction[1] * velocity[1]) / speed;
        if (turnDot > 1.0) turnDot = 1.0;
        float adjusted = speed * (1.0 - 0.12 * RadToDeg(ArcCosine(turnDot)) / 90.0);
        corrected[0] = direction[0] * adjusted; corrected[1] = direction[1] * adjusted;
    }
    LimitHorizontalSpeed(corrected, g_bhopMaxSpeed.FloatValue);
    float sample[3], ground[3]; sample = position; sample[2] += 2.0;
    if (!FindTop(tank, sample, position[2] - 128.0, ground, 0.7)) return;
    float gravity = TankGravity(tank);
    float disc = velocity[2] * velocity[2] + 2.0 * gravity * (position[2] - ground[2]);
    if (disc < 0.0) return;
    float remaining = (velocity[2] + SquareRoot(disc)) / gravity;
    if (TankHopRouteClear(tank, position, corrected, remaining))
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, corrected);
}

void CancelTankRecovery(int tank) {
    g_stallSince[tank] = 0.0;
    g_retreatUntil[tank] = 0.0;
    g_recoveryFlightUntil[tank] = 0.0;
}
void ResetTankMovement(int tank) {
    CancelTankRecovery(tank);
    ResetTankHop(tank);
    g_hopPaused[tank] = false;
    g_recoveryAfter[tank] = 0.0;
    g_noHopUntil[tank] = 0.0;
    g_haveGround[tank] = false;
    g_recoveryAttempts[tank] = 0;
    g_lastRecoveryCandidate[tank] = -1;
}
bool TankAttackBusy(int tank) {
    int sequence = GetEntProp(tank, Prop_Send, "m_nSequence");
    // Match the existing hulk action exclusions, including rage/flinch/frozen.
    if ((sequence >= 2 && sequence <= 4) || (sequence >= 24 && sequence <= 31)
        || (sequence >= 33 && sequence <= 64) || (GetEntityFlags(tank) & FL_FROZEN)) return true;
    // A requested attack or cooldown is not evidence of an executing action.
    return false;
}
bool TankWishDirection(int buttons, const float vel[3], const float angles[3], float wish[3]) {
    float forwardMove = vel[0], sideMove = vel[1];
    // Both forms are used by existing AI consumers (including si_unstuck).
    // Preserve button-only commands; normalize diagonals instead of adding yaws.
    if (FloatAbs(forwardMove) + FloatAbs(sideMove) <= 1.0) {
        forwardMove = float(((buttons & IN_FORWARD) != 0) - ((buttons & IN_BACK) != 0)) * 450.0;
        sideMove = float(((buttons & IN_MOVERIGHT) != 0) - ((buttons & IN_MOVELEFT) != 0)) * 450.0;
    }
    float yaw[3], forwardVector[3], right[3]; yaw[1] = angles[1];
    GetAngleVectors(yaw, forwardVector, right, NULL_VECTOR);
    wish[0] = forwardVector[0] * forwardMove + right[0] * sideMove;
    wish[1] = forwardVector[1] * forwardMove + right[1] * sideMove;
    wish[2] = 0.0;
    return NormalizeVector(wish, wish) > 1.0;
}
bool TankDescending(int tank, const float position[3], bool moving, const float wish[3]) {
    float now = GetGameTime();
    if (GetEntityFlags(tank) & FL_ONGROUND) {
        if (g_haveGround[tank] && position[2] < g_groundZ[tank] - 4.0) {
            g_noHopUntil[tank] = now + 0.45;
            g_groundZ[tank] = position[2];
        }
        // Accumulate small per-command drops on continuous ramps. Update the
        // anchor on ascent too, rather than comparing only adjacent commands.
        if (!g_haveGround[tank] || position[2] > g_groundZ[tank]) g_groundZ[tank] = position[2];
        g_haveGround[tank] = true;
        if (moving) {
            float sample[3], top[3];
            for (int axis = 0; axis < 3; axis++) sample[axis] = position[axis] + wish[axis] * 48.0;
            sample[2] += 18.0;
            // Require an observed descent: a missing floor alone may be a
            // same-height gap, not a route down to the lower storey.
            // Walkable slopes need not be flat enough for an obstacle landing.
            if (FindTop(tank, sample, position[2] - 96.0, top, 0.7) && top[2] < position[2] - 8.0)
                g_noHopUntil[tank] = now + 0.45;
        }
    }
    return now < g_noHopUntil[tank];
}

bool TankRetreatClear(int tank, const float position[3], const float goal[3]) {
    float mins[3], maxs[3], from[3], to[3];
    GetClientMins(tank, mins); GetClientMaxs(tank, maxs);
    // Allow ordinary 18-unit step traversal, but require body room at the goal
    // and throughout the raised sweep; never accept a low ceiling or solid exit.
    from = position; to = goal; from[2] += 18.0; to[2] += 18.0;
    if (!HullClear(tank, from, to, mins, maxs)) return false;
    to = goal; to[2] += 2.0;
    if (!HullClear(tank, to, to, mins, maxs)) return false;
    // Full body clearance plus centre, edges and corners of the actual footprint
    // along the short route. Permit step-height variation, not unsupported ledges.
    for (int step = 1; step <= 3; step++) {
        for (int x = -1; x <= 1; x++) {
            for (int y = -1; y <= 1; y++) {
                float sample[3], top[3];
                for (int axis = 0; axis < 3; axis++)
                    sample[axis] = position[axis] + (goal[axis] - position[axis]) * float(step) / 3.0;
                sample[0] += x < 0 ? mins[0] : (x > 0 ? maxs[0] : 0.0);
                sample[1] += y < 0 ? mins[1] : (y > 0 ? maxs[1] : 0.0);
                float floorZ = sample[2]; sample[2] += 18.0;
                if (!FindTop(tank, sample, floorZ - 18.0, top, 0.7)
                    || FloatAbs(top[2] - floorZ) > 18.0) return false;
            }
        }
    }
    return true;
}
bool TankRecover(int tank, int target, const float position[3], const float targetPos[3], bool moving,
    const float wish[3], int &buttons, float vel[3], const float angles[3]) {
    float now = GetGameTime();
    // Retreat/return oscillation is not route progress. After two local tries,
    // leave the blocked bot still long enough for si_unstuck's watchdog. Only
    // leaving this pocket (not a new victim or elapsed time) renews the budget.
    if (g_retreatUntil[tank] == 0.0 && g_recoveryAttempts[tank] > 0 && GetVectorDistance(position, g_recoveryOrigin[tank]) > 128.0) {
        g_recoveryAttempts[tank] = 0;
        g_lastRecoveryCandidate[tank] = -1;
    }
    if (!(GetEntityFlags(tank) & FL_ONGROUND) || g_jumpUntil[tank] > now
        || (GetVectorDistance(position, targetPos) < 85.0 && VisiblePoint(tank, target, targetPos))) {
        CancelTankRecovery(tank); return false;
    }
    if (g_retreatUntil[tank] > 0.0) {
        float direction[3]; MakeVectorFromPoints(position, g_retreatGoal[tank], direction); direction[2] = 0.0;
        if (now >= g_retreatUntil[tank] || NormalizeVector(direction, direction) < 6.0) {
            CancelTankRecovery(tank); return false;
        }
        // Revalidate the remaining route at 10 Hz, not 27 support rays per cmd.
        if (now >= g_retreatCheck[tank]) {
            g_retreatCheck[tank] = now + 0.1;
            if (!TankRetreatClear(tank, position, g_retreatGoal[tank])) {
                CancelTankRecovery(tank); return false;
            }
        }
        float yaw[3], forwardVector[3], right[3]; yaw[1] = angles[1];
        GetAngleVectors(yaw, forwardVector, right, NULL_VECTOR);
        vel[0] = GetVectorDotProduct(direction, forwardVector) * 160.0;
        vel[1] = GetVectorDotProduct(direction, right) * 160.0;
        buttons &= ~(IN_JUMP | IN_DUCK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
        // si_unstuck already saw Valve's original input earlier in this cmd.
        // No synthetic positions, clock resets or persistent bot commands.
        buttons |= vel[0] >= 0.0 ? IN_FORWARD : IN_BACK;
        buttons |= vel[1] >= 0.0 ? IN_MOVERIGHT : IN_MOVELEFT;
        return true;
    }
    if (now < g_recoveryAfter[tank] || g_recoveryAttempts[tank] >= 2) {
        g_stallSince[tank] = 0.0; return false;
    }
    if (g_stallSince[tank] == 0.0 || GetVectorDistance(position, g_stallOrigin[tank]) > 12.0) {
        g_stallSince[tank] = now; g_stallOrigin[tank] = position;
        return false;
    }
    if (now - g_stallSince[tank] < (moving ? 0.6 : 1.0)) return false;
    g_stallSince[tank] = 0.0;
    g_recoveryAfter[tank] = now + 1.25;
    float direction[3]; direction = wish;
    if (!moving) {
        // No invented route through walls/floors: only a visible, same-level
        // victim supplies a direct direction when NextBot has stopped issuing input.
        if (FloatAbs(position[2] - targetPos[2]) > 64.0 || !VisiblePoint(tank, target, targetPos)) return false;
        MakeVectorFromPoints(position, targetPos, direction); direction[2] = 0.0;
        if (NormalizeVector(direction, direction) < 1.0) return false;
    }
    if (g_recoveryAttempts[tank] == 0) g_recoveryOrigin[tank] = position;
    // Also bound failed geometry searches, not just successful retreat launches.
    g_recoveryAttempts[tank]++;
    float toward[3]; MakeVectorFromPoints(position, targetPos, toward); toward[2] = 0.0;
    NormalizeVector(toward, toward);
    if (GetVectorDotProduct(direction, toward) > 0.8 && !TankDescending(tank, position, true, direction)
        && g_lastRecoveryCandidate[tank] != 6
        && TryObstacleJump(tank, target, position, targetPos, buttons, vel)) {
        g_lastRecoveryCandidate[tank] = 6;
        ResetTankHop(tank);
        return true;
    }
    // A raised-platform jump cannot get out of a shallow vehicle bed. Try a
    // normal-height arc only when the walk route is blocked; do not blindly hop.
    float forwardGoal[3]; forwardGoal = position;
    for (int axis = 0; axis < 2; axis++) forwardGoal[axis] += direction[axis] * 48.0;
    if (g_lastRecoveryCandidate[tank] != 7 && !TankRetreatClear(tank, position, forwardGoal)) {
        float launch[3];
        launch[0] = direction[0] * 120.0; launch[1] = direction[1] * 120.0;
        launch[2] = SquareRoot(2.0 * TankGravity(tank) * 56.0);
        float flight = 2.0 * launch[2] / TankGravity(tank);
        if (TankHopRouteClear(tank, position, launch, flight)) {
            ResetTankHop(tank);
            SetEntPropEnt(tank, Prop_Send, "m_hGroundEntity", -1);
            SetEntityFlags(tank, GetEntityFlags(tank) & ~FL_ONGROUND);
            TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, launch);
            buttons &= ~(IN_JUMP | IN_DUCK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
            vel[0] = vel[1] = 0.0;
            g_recoveryFlightUntil[tank] = now + 1.0;
            g_lastRecoveryCandidate[tank] = 7;
            return true;
        }
    }
    float offsets[6] = {0.0, 90.0, -90.0, 180.0, 135.0, -135.0};
    for (int candidate = 0; candidate < sizeof(offsets); candidate++) {
        if (candidate == g_lastRecoveryCandidate[tank]) continue;
        float offset = offsets[candidate];
        float yaw = ArcTangent2(direction[1], direction[0]) + DegToRad(offset);
        float goal[3]; goal = position;
        goal[0] += Cosine(yaw) * 48.0; goal[1] += Sine(yaw) * 48.0;
        float sample[3], top[3]; sample = goal; sample[2] += 18.0;
        if (!FindTop(tank, sample, goal[2] - 18.0, top, 0.7)) continue;
        goal[2] = top[2];
        if (!TankRetreatClear(tank, position, goal)) continue;
        ResetTankHop(tank);
        g_lastRecoveryCandidate[tank] = candidate;
        g_retreatGoal[tank] = goal;
        g_retreatCheck[tank] = now + 0.1;
        g_retreatUntil[tank] = now + 0.35;
        return TankRecover(tank, target, position, targetPos, moving, wish, buttons, vel, angles);
    }
    return false;
}
