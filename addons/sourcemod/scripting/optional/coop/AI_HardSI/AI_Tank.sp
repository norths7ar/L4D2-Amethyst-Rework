#pragma semicolon 1

#define BoostForward 60.0

ConVar hCvarTankBhop;
ConVar hCvarTankRock;
ConVar hCvarTankBhopStopDistance;
ConVar hCvarTankThrowMinDistance;
ConVar hCvarTankThrowMaxDistance;

public void Tank_OnModuleStart() {
    hCvarTankBhop = CreateConVar("ai_tank_bhop", "1", "Enable AI Tank bhopping");
    hCvarTankRock = CreateConVar("ai_tank_rock", "1", "Allow AI Tank rock throws");
    hCvarTankBhopStopDistance = CreateConVar("ai_tank_bhop_stop_distance", "190", "Stop adding hops inside this distance", FCVAR_NONE, true, 0.0);
    hCvarTankThrowMinDistance = CreateConVar("ai_tank_throw_min_distance", "0", "Minimum range for starting an AI rock throw", FCVAR_NONE, true, 0.0);
    hCvarTankThrowMaxDistance = CreateConVar("ai_tank_throw_max_distance", "800", "Maximum throw-start range; 0 means unlimited", FCVAR_NONE, true, 0.0);
}

public void Tank_OnModuleEnd() {}

// TGMaster/Chanz infinite-jump approach retained with Ast's 60-unit impulse.
// Anne ai_tank3 supplies the close-stop/range policy; no dynamic speed tiers.
public Action Tank_OnPlayerRunCmd(int tank, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon) {
    int sequence = GetEntProp(tank, Prop_Send, "m_nSequence");
    bool throwing = sequence >= 48 && sequence <= 51;
    if (!hCvarTankRock.BoolValue) buttons &= ~IN_ATTACK2;
    if (!throwing && (buttons & IN_ATTACK2)) {
        int target = Tank_GetRockTarget(tank);
        if (target < 1 || !Tank_IsRockTargetInRange(tank, target)) buttons &= ~IN_ATTACK2;
    }

    // Do not inject a punch that the existing tank_attack_control would use
    // to cancel this throw, or turn a normal throw into an artificial jump rock.
    if (throwing || (buttons & IN_ATTACK2)) {
        buttons &= ~(IN_ATTACK | IN_JUMP | IN_DUCK);
        return Plugin_Changed;
    }
    if (!hCvarTankBhop.BoolValue || GetEntityMoveType(tank) == MOVETYPE_LADDER) return Plugin_Changed;

    float position[3], velocity[3];
    GetClientAbsOrigin(tank, position);
    int distance = GetSurvivorProximity(position);
    if (distance < hCvarTankBhopStopDistance.FloatValue) {
        buttons &= ~(IN_JUMP | IN_DUCK);
        return Plugin_Changed; // Valve keeps ownership of the actual melee swing.
    }
    GetEntPropVector(tank, Prop_Data, "m_vecVelocity", velocity);
    float speed = SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
    if (!GetEntProp(tank, Prop_Send, "m_hasVisibleThreats") || speed <= 210.0) return Plugin_Changed;
    if (GetEntityFlags(tank) & FL_ONGROUND) {
        float heading[3];
        GetClientEyeAngles(tank, heading);
        if (buttons & IN_BACK) heading[1] += 180.0;
        if (buttons & IN_MOVELEFT) heading[1] += 90.0;
        if (buttons & IN_MOVERIGHT) heading[1] -= 90.0;
        buttons |= IN_DUCK | IN_JUMP;
        Client_Push(tank, heading, BoostForward);
    }
    return Plugin_Changed;
}

int Tank_GetRockTarget(int tank) {
    float position[3], other[3];
    GetClientAbsOrigin(tank, position);
    int closest = -1;
    float limit = 999999.0;
    for (int target = 1; target <= MaxClients; target++) {
        if (!IsSurvivor(target) || !IsPlayerAlive(target) || IsIncapacitated(target)
            || IsPinned(target) || !isVisibleTo(tank, target)) continue;
        GetClientAbsOrigin(target, other);
        float distance = GetVectorDistance(position, other);
        if (distance < limit) { closest = target; limit = distance; }
    }
    return closest;
}

bool Tank_IsRockTargetInRange(int tank, int target) {
    float position[3], other[3];
    GetClientAbsOrigin(tank, position);
    GetClientAbsOrigin(target, other);
    float distance = GetVectorDistance(position, other);
    float maximum = hCvarTankThrowMaxDistance.FloatValue;
    return distance >= hCvarTankThrowMinDistance.FloatValue && (maximum == 0.0 || distance <= maximum);
}

// Reduced from Anne ai_tank3's L4D_TankRock_OnRelease/calculateThrowAngle:
// low ballistic arc plus target-velocity lead, using the actual release origin.
// Preserve the engine's outgoing speed and rock gravity, with no homing after release.
public Action L4D_TankRock_OnRelease(int tank, int rock, float position[3], float angles[3], float velocity[3], float rotation[3]) {
    if (!g_bHardSIActive || !IsBotInfected(tank) || !hCvarTankRock.BoolValue) return Plugin_Continue;
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
    if (!g_bHardSIActive || !IsBotInfected(client)) return Plugin_Continue;
    if (sequence == 50) {
        sequence = GetRandomInt(0, 1) ? 49 : 51;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}