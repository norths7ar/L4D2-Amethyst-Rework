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
    version = "1.0.0"
};

ConVar g_enable, hCvarTankBhop, hCvarTankRock, hCvarTankBhopStopDistance;
ConVar hCvarTankThrowMinDistance, hCvarTankThrowMaxDistance;
ConVar g_climbEnable, g_lowRate, g_highRate, g_obstacleJump, g_hittables;
int g_targetUserId[MAXPLAYERS + 1];
bool g_boosted[MAXPLAYERS + 1];
float g_previousRate[MAXPLAYERS + 1], g_appliedRate[MAXPLAYERS + 1];
float g_nextOpportunity[MAXPLAYERS + 1], g_nextPunch[MAXPLAYERS + 1];
float g_jumpUntil[MAXPLAYERS + 1], g_jumpLanding[MAXPLAYERS + 1][3];
int g_jumpTarget[MAXPLAYERS + 1];

#include "ai_tank/movement.sp"

public void OnPluginStart() {
    g_enable = CreateConVar("ai_tank_enable", "1", "Enable AI Tank behavior", _, true, 0.0, true, 1.0);
    hCvarTankBhop = CreateConVar("ai_tank_bhop", "1", "Enable AI Tank bhopping");
    hCvarTankRock = CreateConVar("ai_tank_rock", "1", "Allow AI Tank rock throws");
    hCvarTankBhopStopDistance = CreateConVar("ai_tank_bhop_stop_distance", "135", "Stop adding hops inside target distance", _, true, 0.0);
    hCvarTankThrowMinDistance = CreateConVar("ai_tank_throw_min_distance", "300", "Minimum range for starting a rock throw", _, true, 0.0);
    hCvarTankThrowMaxDistance = CreateConVar("ai_tank_throw_max_distance", "800", "Maximum throw-start range; 0 means unlimited", _, true, 0.0);
    g_climbEnable = CreateConVar("tank_climb_enable", "1", "Accelerate native AI Tank obstacle traversal", _, true, 0.0, true, 1.0);
    g_lowRate = CreateConVar("tank_climb_low_rate", "2.5", "Low obstacle animation rate", _, true, 1.0, true, 10.0);
    g_highRate = CreateConVar("tank_climb_high_rate", "3.5", "High obstacle animation rate", _, true, 1.0, true, 10.0);
    g_obstacleJump = CreateConVar("ai_tank_obstacle_jump", "1", "Jump onto reachable low obstacles in the forward pursuit path", _, true, 0.0, true, 1.0);
    g_hittables = CreateConVar("ai_tank_hittables", "1", "Punch aligned, in-reach hittables without seeking or snap aiming", _, true, 0.0, true, 1.0);
    HookEvent("player_spawn", OnSpawn, EventHookMode_Pre);
    HookEvent("round_start", OnRoundStart);
    g_enable.AddChangeHook(OnEnableChanged);
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
}

public void OnClientPutInServer(int client) {
    ResetTank(client);
    SDKHook(client, SDKHook_PostThinkPost, OnPostThink);
}
public void OnClientDisconnect(int client) { ResetTank(client); }
public void OnMapStart() {
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
    g_targetUserId[client] = 0;
    g_boosted[client] = false;
    g_jumpUntil[client] = 0.0;
    g_nextOpportunity[client] = 0.0;
    g_nextPunch[client] = 0.0;
}
public void OnEnableChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
    if (!cvar.BoolValue) {
        for (int client = 1; client <= MaxClients; client++) {
            if (IsClientInGame(client)) RestoreRate(client);
            g_jumpUntil[client] = 0.0;
        }
    }
}
public void OnPluginEnd() {
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) RestoreRate(client);
}

// Observe Valve's selected victim; never force a victim or turn toward a rear attacker.
public Action L4D2_OnChooseVictim(int tank, int &target) {
    if (IsAITank(tank)) g_targetUserId[tank] = IsSurvivor(target) ? GetClientUserId(target) : 0;
    return Plugin_Continue;
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
    if (!g_enable.BoolValue || !IsAITank(tank)) return Plugin_Continue;
    int sequence = GetEntProp(tank, Prop_Send, "m_nSequence");
    bool throwing = sequence >= 48 && sequence <= 51;
    if (!hCvarTankRock.BoolValue) buttons &= ~IN_ATTACK2;
    if (!throwing && (buttons & IN_ATTACK2)) {
        int rockTarget = Tank_GetRockTarget(tank);
        if (rockTarget < 1 || !Tank_IsRockTargetInRange(tank, rockTarget)) buttons &= ~IN_ATTACK2;
    }
    // Preserve existing rock/punch arbitration, never inject jump rocks.
    if (throwing || (buttons & IN_ATTACK2)) {
        g_jumpUntil[tank] = 0.0;
        buttons &= ~(IN_ATTACK | IN_JUMP | IN_DUCK);
        return Plugin_Changed;
    }
    if (GetEntityMoveType(tank) != MOVETYPE_WALK || GetEntProp(tank, Prop_Data, "m_nWaterLevel") > 1
        || (sequence >= 16 && sequence <= 23) || L4D_IsPlayerStaggering(tank)) {
        g_jumpUntil[tank] = 0.0;
        return Plugin_Changed;
    }
    int target = GetClientOfUserId(g_targetUserId[tank]);
    if (!IsFreeSurvivor(target)) { g_jumpUntil[tank] = 0.0; return Plugin_Changed; }
    float position[3], targetPos[3], velocity[3];
    GetClientAbsOrigin(tank, position); GetClientAbsOrigin(target, targetPos);
    float distance = GetVectorDistance(position, targetPos);
    if (ContinueObstacleJump(tank, target, buttons, vel)) return Plugin_Changed;
    // A nearby actual victim keeps the engine's melee behavior, without changing its aim.
    if (distance < hCvarTankBhopStopDistance.FloatValue && VisiblePoint(tank, target, targetPos)) {
        buttons &= ~(IN_JUMP | IN_DUCK);
        return Plugin_Changed;
    }
    if (GetEntityFlags(tank) & FL_ONGROUND) {
        float now = GetGameTime();
        if (now >= g_nextOpportunity[tank] && !(buttons & IN_ATTACK)) {
            g_nextOpportunity[tank] = now + 0.2;
            if (TryHittable(tank, target, targetPos, buttons)) return Plugin_Changed;
            if (TryObstacleJump(tank, target, position, targetPos, buttons, vel)) return Plugin_Changed;
        }
        if (buttons & IN_ATTACK) return Plugin_Changed;
    }
    if (!hCvarTankBhop.BoolValue) return Plugin_Changed;
    GetEntPropVector(tank, Prop_Data, "m_vecVelocity", velocity);
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (!GetEntProp(tank, Prop_Send, "m_hasVisibleThreats") || speed <= 210.0) return Plugin_Changed;
    if (GetEntityFlags(tank) & FL_ONGROUND) {
        // TGMaster/Chanz jump approach, retaining Ast's 60-unit impulse.
        float heading[3], forwardVector[3]; GetClientEyeAngles(tank, heading);
        if (buttons & IN_BACK) heading[1] += 180.0;
        if (buttons & IN_MOVELEFT) heading[1] += 90.0;
        if (buttons & IN_MOVERIGHT) heading[1] -= 90.0;
        GetAngleVectors(heading, forwardVector, NULL_VECTOR, NULL_VECTOR);
        for (int axis = 0; axis < 3; axis++) velocity[axis] += forwardVector[axis] * 60.0;
        buttons |= IN_DUCK | IN_JUMP;
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, velocity);
    }
    return Plugin_Changed;
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
