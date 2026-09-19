// Rider detection and upward SweepFist follow Anne ai_tank3's overhead/combat.
// Keep the engine's damage, range and attack cadence; never add direct damage.
Handle g_sweepFist;
int g_swingRider[MAXPLAYERS + 1];
bool g_riderHit[MAXPLAYERS + 1];
float g_nextTargetChange[MAXPLAYERS + 1];

void SetupTankCombat() {
    GameData data = new GameData("l4d_fix_punch_block");
    if (data == null) SetFailState("Missing l4d_fix_punch_block gamedata");
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(data, SDKConf_Signature, "CTankClaw::SweepFist");
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
    g_sweepFist = EndPrepSDKCall();
    delete data;
    if (g_sweepFist == null) SetFailState("Cannot resolve CTankClaw::SweepFist");
}

bool Tank_RiderPoint(int tank, int survivor, float point[3]) {
    if (!IsFreeSurvivor(survivor)) return false;
    float origin[3], mins[3], maxs[3], otherMins[3], otherMaxs[3], eye[3];
    GetClientAbsOrigin(tank, origin);
    GetClientAbsOrigin(survivor, point);
    GetClientMins(tank, mins); GetClientMaxs(tank, maxs);
    GetClientMins(survivor, otherMins); GetClientMaxs(survivor, otherMaxs);
    if (GetEntPropEnt(survivor, Prop_Send, "m_hGroundEntity") != tank) {
        if (!(GetEntityFlags(survivor) & FL_ONGROUND)
            || point[2] < origin[2] + maxs[2] - 18.0
            || point[2] > origin[2] + maxs[2] + 18.0) return false;
        for (int axis = 0; axis < 2; axis++)
            if (point[axis] + otherMaxs[axis] < origin[axis] + mins[axis]
                || point[axis] + otherMins[axis] > origin[axis] + maxs[axis]) return false;
    }
    point[2] += 24.0;
    GetClientEyePosition(tank, eye);
    return GetVectorDistance(eye, point) <= FindConVar("tank_swing_range").FloatValue
        && VisiblePoint(tank, survivor, point);
}

int Tank_FindRider(int tank) {
    float point[3];
    for (int survivor = 1; survivor <= MaxClients; survivor++)
        if (Tank_RiderPoint(tank, survivor, point)) return survivor;
    return 0;
}

bool Tank_CloseTarget(int tank, int survivor, float &distance) {
    if (!IsFreeSurvivor(survivor)) return false;
    float position[3], other[3], chest[3];
    GetClientAbsOrigin(tank, position); GetClientAbsOrigin(survivor, other);
    distance = GetVectorDistance(position, other);
    // Nearby opportunities only. Let Valve navigate floors, ladders and distant targets.
    if (distance > 300.0 || FloatAbs(other[2] - position[2]) > 48.0) return false;
    chest = other; chest[2] += 45.0;
    if (!VisiblePoint(tank, survivor, chest)) return false;
    if (distance > FindConVar("tank_swing_range").FloatValue * 1.5 && !InFront(tank, other, 0.0)) return false;
    float mins[3], maxs[3]; GetClientMins(tank, mins); GetClientMaxs(tank, maxs);
    position[2] += 2.0; other[2] += 2.0;
    Handle trace = TR_TraceHullFilterEx(position, other, mins, maxs, MASK_PLAYERSOLID, TraceNotSelf, tank);
    bool clear = !TR_StartSolid(trace) && (!TR_DidHit(trace) || TR_GetEntityIndex(trace) == survivor);
    delete trace;
    return clear;
}

int Tank_ChooseNearbyTarget(int tank, int engineTarget) {
    int rider = Tank_FindRider(tank);
    if (rider > 0) return rider;
    int previous = GetClientOfUserId(g_targetUserId[tank]);
    float distance;
    // A short hold and a meaningful distance advantage avoid alternate-frame switches.
    if (GetGameTime() < g_nextTargetChange[tank] && Tank_CloseTarget(tank, previous, distance)) return previous;
    float currentDistance = 999999.0;
    if (IsFreeSurvivor(engineTarget)) {
        float origin[3], targetPos[3];
        GetClientAbsOrigin(tank, origin); GetClientAbsOrigin(engineTarget, targetPos);
        currentDistance = GetVectorDistance(origin, targetPos);
    }
    int chosen = engineTarget;
    float best = currentDistance - 64.0;
    for (int survivor = 1; survivor <= MaxClients; survivor++) {
        if (survivor == engineTarget || !Tank_CloseTarget(tank, survivor, distance)) continue;
        if (distance < best) { chosen = survivor; best = distance; }
    }
    if (chosen != previous) g_nextTargetChange[tank] = GetGameTime() + 0.5;
    return chosen;
}

bool Tank_AimAtRider(int tank, int &buttons, float angles[3]) {
    int rider = Tank_FindRider(tank);
    if (rider < 1) return false;
    float eye[3], point[3], direction[3];
    if (!Tank_RiderPoint(tank, rider, point)) return false;
    GetClientEyePosition(tank, eye);
    MakeVectorFromPoints(eye, point, direction);
    GetVectorAngles(direction, angles);
    TeleportEntity(tank, NULL_VECTOR, angles, NULL_VECTOR);
    buttons &= ~(IN_ATTACK2 | IN_JUMP | IN_DUCK);
    int claw = GetEntPropEnt(tank, Prop_Send, "m_hActiveWeapon");
    if (claw > MaxClients && IsValidEntity(claw)
        && GetEntPropFloat(claw, Prop_Send, "m_flNextPrimaryAttack") <= GetGameTime()) buttons |= IN_ATTACK;
    return true;
}

public void L4D_TankClaw_DoSwing_Pre(int tank, int claw) {
    if (!IsAITank(tank)) return;
    int rider = g_enable.BoolValue ? Tank_FindRider(tank) : 0;
    g_swingRider[tank] = rider > 0 ? GetClientUserId(rider) : 0;
    g_riderHit[tank] = false;
}

public void OnTankClawDamage(int victim, int attacker, int inflictor, float damage, int damageType) {
    if (damage > 0.0 && IsAITank(attacker) && g_swingRider[attacker] == GetClientUserId(victim))
        g_riderHit[attacker] = true;
}

public void L4D_TankClaw_DoSwing_Post(int tank, int claw) {
    if (!IsAITank(tank)) return;
    int rider = GetClientOfUserId(g_swingRider[tank]);
    g_swingRider[tank] = 0;
    float eye[3], point[3];
    if (!g_enable.BoolValue || g_riderHit[tank] || claw <= MaxClients || !IsValidEntity(claw)
        || !Tank_RiderPoint(tank, rider, point)) return;
    GetClientEyePosition(tank, eye);
    SDKCall(g_sweepFist, claw, eye, point);
}
