#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

// Tank behavior extracted from Breezy's AI_HardSI. Rock lead follows Anne ai_tank3.
public Plugin myinfo = {
    name = "AI Tank", author = "Breezy, norths7ar",
    description = "AI Tank movement, throws and opportunistic obstacle interaction",
    version = "1.5.0"
};

ConVar g_enable, hCvarTankBhop, hCvarTankRock, hCvarTankBhopStopDistance;
ConVar g_bhopMaxSpeed, g_bhopResumeDistance;
ConVar hCvarTankThrowMinDistance, hCvarTankThrowMaxDistance;
ConVar g_climbEnable, g_lowRate, g_highRate, g_obstacleJump, g_hittables, g_doors;
int g_targetUserId[MAXPLAYERS + 1];
bool g_boosted[MAXPLAYERS + 1];
float g_previousRate[MAXPLAYERS + 1], g_appliedRate[MAXPLAYERS + 1];
float g_nextOpportunity[MAXPLAYERS + 1], g_nextPunch[MAXPLAYERS + 1];
float g_jumpUntil[MAXPLAYERS + 1], g_jumpLanding[MAXPLAYERS + 1][3];
int g_jumpTarget[MAXPLAYERS + 1];

#include "ai_tank/diagnostics.sp"
#include "ai_tank/path.sp"
#include "ai_tank/movement.sp"
#include "ai_tank/combat.sp"

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax) {
    RegPluginLibrary("ai_tank");
    CreateNative("AI_Tank_IsMovementOwned", NativeMovementOwned);
    MarkNativeAsOptional("AnneNextBot_IsActive");
    MarkNativeAsOptional("AnneNextBot_SetPathConsumer");
    MarkNativeAsOptional("AnneNextBot_GetPathSnapshotInfo");
    MarkNativeAsOptional("AnneNextBot_GetPathSegment");
    MarkNativeAsOptional("AIDiag_Event");
    MarkNativeAsOptional("AIDiag_Command");
    return APLRes_Success;
}
public any NativeMovementOwned(Handle plugin, int params) {
    int tank = GetNativeCell(1);
    return IsAITank(tank) && g_enable.BoolValue
        && (g_jumpUntil[tank] > GetGameTime() || g_retreatUntil[tank] > GetGameTime()
            || g_recoveryFlightUntil[tank] > GetGameTime() || TankDoorPending(tank));
}

public void OnPluginStart() {
    SetupTankCombat();
    g_enable = CreateConVar("ai_tank_enable", "1", "Enable AI Tank behavior", _, true, 0.0, true, 1.0);
    hCvarTankBhop = CreateConVar("ai_tank_bhop", "1", "Enable AI Tank bhopping");
    hCvarTankRock = CreateConVar("ai_tank_rock", "1", "Allow AI Tank rock throws");
    hCvarTankBhopStopDistance = CreateConVar("ai_tank_bhop_stop_distance", "65", "Pause added bhops inside target distance", _, true, 0.0);
    g_bhopResumeDistance = CreateConVar("ai_tank_bhop_resume_distance", "100", "Resume added bhops beyond target distance", _, true, 0.0);
    g_bhopMaxSpeed = CreateConVar("ai_tank_bhop_max_speed", "360", "Maximum horizontal bhop speed", _, true, 210.0);
    hCvarTankThrowMinDistance = CreateConVar("ai_tank_throw_min_distance", "500", "Minimum range for starting a rock throw", _, true, 0.0);
    hCvarTankThrowMaxDistance = CreateConVar("ai_tank_throw_max_distance", "800", "Maximum throw-start range; 0 means unlimited", _, true, 0.0);
    g_climbEnable = CreateConVar("tank_climb_enable", "1", "Accelerate native AI Tank obstacle traversal", _, true, 0.0, true, 1.0);
    g_lowRate = CreateConVar("tank_climb_low_rate", "2.5", "Low obstacle animation rate", _, true, 1.0, true, 10.0);
    g_highRate = CreateConVar("tank_climb_high_rate", "3.5", "High obstacle animation rate", _, true, 1.0, true, 10.0);
    g_obstacleJump = CreateConVar("ai_tank_obstacle_jump", "1", "Jump onto reachable low obstacles in the forward pursuit path", _, true, 0.0, true, 1.0);
    g_hittables = CreateConVar("ai_tank_hittables", "1", "Punch aligned, in-reach hittables without seeking or snap aiming", _, true, 0.0, true, 1.0);
    g_doors = CreateConVar("ai_tank_doors", "1", "Normally punch in-reach breakable ordinary doors blocking movement", _, true, 0.0, true, 1.0);
    g_pathEnable = CreateConVar("ai_tank_path_enable", "1", "Read Anne Tank paths to guard added movement; never change scheduling", _, true, 0.0, true, 1.0);
    g_pathEnable.AddChangeHook(OnPathEnableChanged);
    HookEvent("player_spawn", OnSpawn, EventHookMode_Pre);
    HookEvent("round_start", OnRoundStart);
    g_enable.AddChangeHook(OnEnableChanged);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
}

public void OnClientPutInServer(int client) {
    ResetTank(client);
    SDKHook(client, SDKHook_PostThinkPost, OnPostThink);
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTankClawDamage);
}
public void OnClientDisconnect(int client) { ResetTank(client); }
public void OnMapStart() {
    TankPathConsumer(g_enable.BoolValue && g_pathEnable.BoolValue);
    for (int client = 1; client <= MaxClients; client++) ResetTank(client);
}
public void OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) RestoreRate(client);
        ResetTank(client);
    }
}
public void OnSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0) { RestoreRate(client); ResetTank(client); }
}
void ResetTank(int client) {
    ResetTankMovement(client);
    ResetTankPath(client);
    g_lastOwner[client][0] = '\0';
    g_targetUserId[client] = 0;
    g_nextTargetChange[client] = 0.0;
    g_swingRider[client] = 0;
    g_riderHit[client] = false;
    g_boosted[client] = false;
    g_jumpUntil[client] = 0.0;
    g_nextOpportunity[client] = 0.0;
    g_nextPunch[client] = 0.0;
}
public void OnEnableChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
    TankPathConsumer(cvar.BoolValue && g_pathEnable.BoolValue);
    if (!cvar.BoolValue) {
        for (int client = 1; client <= MaxClients; client++) {
            if (IsClientInGame(client)) RestoreRate(client);
            ResetTankMovement(client);
            g_jumpUntil[client] = 0.0;
        }
    }
}
public void OnPluginEnd() {
    TankPathConsumer(false);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) RestoreRate(client);
}

// Keep Valve's long-range navigation; prefer a clear, substantially closer
// opportunity (or a rider) instead of remaining committed to a distant victim.
public Action L4D2_OnChooseVictim(int tank, int &target) {
    if (!IsAITank(tank) || !g_enable.BoolValue) return Plugin_Continue;
    int chosen = target;
    int sequence = GetEntProp(tank, Prop_Send, "m_nSequence");
    if (GetEntityMoveType(tank) == MOVETYPE_WALK && !(sequence >= 16 && sequence <= 23)
        && !(sequence >= 48 && sequence <= 51)) chosen = Tank_ChooseNearbyTarget(tank, target);
    int userId = IsSurvivor(chosen) ? GetClientUserId(chosen) : 0;
    if (userId != g_targetUserId[tank]) {
        CancelTankRecovery(tank); ResetTankHop(tank); ResetTankPath(tank);
        EndObstacleJump(tank, "victim changed", false);
    }
    g_targetUserId[tank] = userId;
    if (chosen == target) return Plugin_Continue;
    target = chosen;
    return Plugin_Changed;
}
bool IsAITank(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && IsFakeClient(client) && IsPlayerAlive(client) && GetClientTeam(client) == 3
        && GetEntProp(client, Prop_Send, "m_zombieClass") == 8;
}
bool IsSurvivor(int client) {
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && IsPlayerAlive(client) && GetClientTeam(client) == 2;
}
bool IsFreeSurvivor(int client) {
    return IsSurvivor(client) && !GetEntProp(client, Prop_Send, "m_isIncapacitated")
        && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge")
        && GetEntPropEnt(client, Prop_Send, "m_tongueOwner") <= 0
        && GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") <= 0
        && GetEntPropEnt(client, Prop_Send, "m_carryAttacker") <= 0
        && GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") <= 0
        && GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") <= 0;
}
public bool TraceNotSelf(int entity, int contentsMask, any client) { return entity != client; }
bool VisiblePoint(int tank, int target, const float point[3]) {
    float eye[3]; GetClientEyePosition(tank, eye);
    Handle trace = TR_TraceRayFilterEx(eye, point, MASK_SHOT, RayType_EndPoint, TraceNotSelf, tank);
    bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == target;
    delete trace;
    return visible;
}
bool InFront(int tank, const float point[3], float minimumDot = 0.5) {
    float origin[3], facing[3], forwardVector[3], direction[3];
    GetClientAbsOrigin(tank, origin); GetClientEyeAngles(tank, facing);
    facing[0] = 0.0; GetAngleVectors(facing, forwardVector, NULL_VECTOR, NULL_VECTOR);
    MakeVectorFromPoints(origin, point, direction); direction[2] = 0.0;
    NormalizeVector(direction, direction);
    return GetVectorDotProduct(forwardVector, direction) >= minimumDot;
}

public Action OnPlayerRunCmd(int tank, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
    if (!IsAITank(tank)) { ResetTankMovement(tank); return Plugin_Continue; }
    int rawButtons = buttons;
    float rawVel[3]; rawVel = vel;
    strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "native");
    Action result = TankRunCommand(tank, buttons, vel, angles);
    TankCommandLog(tank, rawButtons, rawVel, buttons, vel);
    return result;
}
Action TankRunCommand(int tank, int &buttons, float vel[3], float angles[3]) {
    if (!g_enable.BoolValue || !IsAITank(tank)) { ResetTankMovement(tank); return Plugin_Continue; }
    int sequence = GetEntProp(tank, Prop_Send, "m_nSequence");
    bool throwing = sequence >= 48 && sequence <= 51;
    if (!throwing && !(sequence >= 16 && sequence <= 23)
        && GetEntityMoveType(tank) == MOVETYPE_WALK && !L4D_IsPlayerStaggering(tank)
        && Tank_AimAtRider(tank, buttons, angles)) {
        CancelTankRecovery(tank);
        ResetTankHop(tank);
        EndObstacleJump(tank, "rider combat", false);
        return Plugin_Changed;
    }
    if (!hCvarTankRock.BoolValue) buttons &= ~IN_ATTACK2;
    if (!throwing && (buttons & IN_ATTACK2)) {
        int rockTarget = Tank_GetRockTarget(tank);
        if (rockTarget < 1 || !Tank_IsRockTargetInRange(tank, rockTarget)) buttons &= ~IN_ATTACK2;
    }
    // Preserve existing rock/punch arbitration, never inject jump rocks.
    if (throwing || (buttons & IN_ATTACK2)) {
        CancelTankRecovery(tank);
        ResetTankHop(tank);
        EndObstacleJump(tank, "rock action", false);
        buttons &= ~(IN_ATTACK | IN_JUMP | IN_DUCK);
        return Plugin_Changed;
    }
    if (GetEntityMoveType(tank) != MOVETYPE_WALK || GetEntProp(tank, Prop_Data, "m_nWaterLevel") > 1
        || (sequence >= 16 && sequence <= 23) || L4D_IsPlayerStaggering(tank)) {
        CancelTankRecovery(tank);
        ResetTankHop(tank);
        EndObstacleJump(tank, "native traversal/water/stagger", false);
        return Plugin_Changed;
    }
    int target = GetClientOfUserId(g_targetUserId[tank]);
    if (!IsFreeSurvivor(target)) { CancelTankRecovery(tank); ResetTankHop(tank); EndObstacleJump(tank, "no free victim", false); return Plugin_Changed; }
    float position[3], targetPos[3], velocity[3];
    GetClientAbsOrigin(tank, position); GetClientAbsOrigin(target, targetPos);
    float wish[3];
    bool moving = TankWishDirection(buttons, vel, angles, wish);
    TankPathUpdate(tank, position);
    // One forward interaction decision before obstacle/recovery ownership. The
    // target may be hidden by the very door that needs a normal claw attack.
    if (!TankAttackBusy(tank) && (GetEntityFlags(tank) & FL_ONGROUND)
        && GetGameTime() >= g_nextOpportunity[tank]) {
        g_nextOpportunity[tank] = GetGameTime() + 0.2;
        if (TryForwardInteraction(tank, target, targetPos, moving, wish, buttons)) {
            CancelTankRecovery(tank); ResetTankHop(tank);
            EndObstacleJump(tank, "forward interaction", false);
            return Plugin_Changed;
        }
    }
    if (!TankAttackBusy(tank) && TankDoorPending(tank)) {
        CancelTankRecovery(tank); ResetTankHop(tank);
        EndObstacleJump(tank, "blocking door has priority", false);
        strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "door");
        return Plugin_Changed;
    }
    // Keep an already validated local route until its exit. Native steering may
    // legitimately turn away while airborne; only a traversal hazard cancels it.
    bool localOwned = g_jumpUntil[tank] > 0.0 || g_retreatUntil[tank] > 0.0 || g_recoveryFlightUntil[tank] > 0.0;
    bool pathAllows = !g_pathBlocked[tank] && (localOwned || TankPathAllowsAddedMove(tank, wish, moving));
    if (!pathAllows) {
        CancelTankRecovery(tank);
        EndObstacleJump(tank, "yield native path transition/turn", false);
        if (g_pathLadder[tank] || g_hopUntil[tank] > GetGameTime()) TankLadderBrake(tank);
        ResetTankHop(tank);
        return Plugin_Changed;
    }
    float distance = GetVectorDistance(position, targetPos);
    float resume = g_bhopResumeDistance.FloatValue;
    if (resume < hCvarTankBhopStopDistance.FloatValue) resume = hCvarTankBhopStopDistance.FloatValue;
    if (distance <= hCvarTankBhopStopDistance.FloatValue) g_hopPaused[tank] = true;
    else if (distance >= resume) g_hopPaused[tank] = false;
    if (TankAttackBusy(tank)) {
        CancelTankRecovery(tank); ResetTankHop(tank);
        EndObstacleJump(tank, "native attack/action: return navigation", false);
        return Plugin_Changed;
    }
    // Intentional flight/local exit owns movement; never count it as a stall.
    if (ContinueObstacleJump(tank, target, buttons, vel, angles)) { CancelTankRecovery(tank); strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "obstacle"); return Plugin_Changed; }
    if (g_recoveryFlightUntil[tank] > GetGameTime() && !(GetEntityFlags(tank) & FL_ONGROUND)) {
        // Tested local escape arc, not an accelerated chase hop.
        buttons &= ~(IN_JUMP | IN_DUCK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
        vel[0] = vel[1] = 0.0;
        strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "recovery");
        return Plugin_Changed;
    }
    if (g_recoveryFlightUntil[tank] > 0.0) {
        TankEvent(tank, "recovery", "escape arc landed/expired: return native navigation");
        g_recoveryFlightUntil[tank] = 0.0;
    }
    if (TankRecover(tank, target, position, targetPos, moving, wish, buttons, vel, angles)) {
        strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), g_jumpUntil[tank] > GetGameTime() ? "obstacle" : "recovery");
        return Plugin_Changed;
    }
    bool descending = TankDescending(tank, position, moving, wish);
    // Do not seize a progressing native route. Raised obstacle candidates are
    // considered only after TankRecover has confirmed a local stall.
    if (!hCvarTankBhop.BoolValue) { ResetTankHop(tank); return Plugin_Changed; }
    GetEntPropVector(tank, Prop_Data, "m_vecVelocity", velocity);
    bool grounded = (GetEntityFlags(tank) & FL_ONGROUND) != 0;
    if (!grounded) {
        if (g_hopUntil[tank] > GetGameTime()) strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "hop");
        TankAirControl(tank, position, velocity, wish, moving);
        return Plugin_Changed;
    }
    bool landingHop = g_hopUntil[tank] > GetGameTime();
    g_hopUntil[tank] = 0.0;
    // Landing braking must survive a rejected next-hop route. Only bleed the
    // momentum of our own hop; native jumps remain outside this controller.
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (landingHop && (g_hopPaused[tank] || (moving && speed > 1.0
        && (velocity[0] * wish[0] + velocity[1] * wish[1]) / speed < 0.55))) {
        float cap = TankRunSpeed(tank);
        if (cap > g_bhopMaxSpeed.FloatValue) cap = g_bhopMaxSpeed.FloatValue;
        LimitHorizontalSpeed(velocity, cap);
        if (speed > cap) {
            strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "hop");
            TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, velocity);
        }
    }
    // These restrictions own added bhops only; preserve native traversal input.
    if (g_hopPaused[tank] || descending || !moving || (buttons & (IN_ATTACK | IN_JUMP))) return Plugin_Changed;
    speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (!GetEntProp(tank, Prop_Send, "m_hasVisibleThreats") || speed <= 210.0) return Plugin_Changed;
    // Anne reverse-hop principle: lose stored speed before reversing, rather
    // than repeatedly adding impulse against the old momentum. Follow native wish.
    float alignment = (velocity[0] * wish[0] + velocity[1] * wish[1]) / speed;
    if (alignment < 0.55) {
        float runSpeed = TankRunSpeed(tank);
        velocity[0] = wish[0] * runSpeed; velocity[1] = wish[1] * runSpeed;
    } else {
        for (int axis = 0; axis < 2; axis++) velocity[axis] += wish[axis] * 60.0;
    }
    LimitHorizontalSpeed(velocity, g_bhopMaxSpeed.FloatValue);
    float flight = 2.0 * SquareRoot(2.0 * TankGravity(tank) * 56.0) / TankGravity(tank);
    float launch[3]; launch = velocity; launch[2] = SquareRoot(2.0 * TankGravity(tank) * 56.0);
    if (!TankHopRouteClear(tank, position, launch, flight)) return Plugin_Changed;
    strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "hop");
    buttons |= IN_DUCK | IN_JUMP;
    TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, velocity);
    g_hopUntil[tank] = GetGameTime() + flight + 0.2;
    g_airThink[tank] = GetGameTime();
    return Plugin_Changed;
}

void LimitHorizontalSpeed(float velocity[3], float maximum) {
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (speed <= maximum || speed <= 0.0) return;
    velocity[0] *= maximum / speed;
    velocity[1] *= maximum / speed;
}

int Tank_GetRockTarget(int tank) {
    float position[3], point[3], other[3]; GetClientAbsOrigin(tank, position);
    int closest = -1; float limit = 999999.0;
    for (int target = 1; target <= MaxClients; target++) {
        if (!IsFreeSurvivor(target)) continue;
        GetClientEyePosition(target, point);
        if (!VisiblePoint(tank, target, point)) continue;
        GetClientAbsOrigin(target, other);
        float distance = GetVectorDistance(position, other);
        if (distance < limit) { closest = target; limit = distance; }
    }
    return closest;
}
bool Tank_IsRockTargetInRange(int tank, int target) {
    float position[3], other[3]; GetClientAbsOrigin(tank, position); GetClientAbsOrigin(target, other);
    float distance = GetVectorDistance(position, other);
    float maximum = hCvarTankThrowMaxDistance.FloatValue;
    return distance >= hCvarTankThrowMinDistance.FloatValue && (maximum == 0.0 || distance <= maximum);
}

// Reduced from Anne ai_tank3's L4D_TankRock_OnRelease/calculateThrowAngle:
// low ballistic arc plus target-velocity lead, using the actual release origin.
// Preserve the engine's outgoing speed and rock gravity, with no homing after release.
public Action L4D_TankRock_OnRelease(int tank, int rock, float position[3], float angles[3], float velocity[3], float rotation[3]) {
    if (!g_enable.BoolValue || !IsAITank(tank) || !hCvarTankRock.BoolValue) return Plugin_Continue;
    int target = Tank_GetRockTarget(tank);
    if (target < 1 || !HasEntProp(rock, Prop_Data, "m_flGravity")) return Plugin_Continue;
    float speed = GetVectorLength(velocity);
    float gravityScale = GetEntPropFloat(rock, Prop_Data, "m_flGravity");
    if (gravityScale == 0.0) gravityScale = 1.0;
    float gravity = FindConVar("sv_gravity").FloatValue * gravityScale;
    if (speed < 1.0 || gravity <= 0.0) return Plugin_Continue;

    float point[3], motion[3], delta[3];
    GetClientAbsOrigin(target, point);
    point[2] += 45.0;
    GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", motion);
    MakeVectorFromPoints(position, point, delta);
    float horizontal = SquareRoot(delta[0] * delta[0] + delta[1] * delta[1]);
    if (horizontal < 1.0) return Plugin_Continue;
    float speed2 = speed * speed;
    float discriminant = speed2 * speed2 - gravity * (gravity * horizontal * horizontal + 2.0 * delta[2] * speed2);
    if (discriminant < 0.0) return Plugin_Continue;
    float pitch = ArcTangent((speed2 - SquareRoot(discriminant)) / (gravity * horizontal));
    float flightTime = horizontal / (speed * Cosine(pitch));
    point[0] += motion[0] * flightTime;
    point[1] += motion[1] * flightTime;
    float yaw = ArcTangent2(point[1] - position[1], point[0] - position[0]);
    velocity[0] = speed * Cosine(pitch) * Cosine(yaw);
    velocity[1] = speed * Cosine(pitch) * Sine(yaw);
    velocity[2] = speed * Sine(pitch);
    return Plugin_Changed;
}

public Action L4D2_OnSelectTankAttack(int client, int& sequence) {
    if (!g_enable.BoolValue || !IsAITank(client)) return Plugin_Continue;
    if (sequence == 50) {
        sequence = GetRandomInt(0, 1) ? 49 : 51;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}
