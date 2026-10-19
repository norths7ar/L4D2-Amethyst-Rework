// Read-only Anne path broker consumer. Never configure the AI scheduler, change
// a path goal or invalidate a path. This plugin alone owns the Tank consumer bit.
#include <anne_nextbot>

ConVar g_pathEnable;
bool g_pathConsumer;
bool g_pathFresh[MAXPLAYERS + 1], g_pathBlocked[MAXPLAYERS + 1], g_pathLadder[MAXPLAYERS + 1];
float g_pathCheck[MAXPLAYERS + 1], g_pathReadAt[MAXPLAYERS + 1];
float g_pathDirection[MAXPLAYERS + 1][3];
bool g_pathHasDirection[MAXPLAYERS + 1];

bool TankPathReady() {
    return GetFeatureStatus(FeatureType_Native, "AnneNextBot_IsActive") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "AnneNextBot_SetPathConsumer") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "AnneNextBot_GetPathSnapshotInfo") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "AnneNextBot_GetPathSegment") == FeatureStatus_Available
        && AnneNextBot_IsActive();
}
void TankPathConsumer(bool enable) {
    if (!TankPathReady()) { g_pathConsumer = false; return; }
    if (enable == g_pathConsumer) return;
    bool active = AnneNextBot_SetPathConsumer(AnneNextBotPathConsumer_Tank, enable);
    g_pathConsumer = enable && active;
}
public void OnAllPluginsLoaded() { TankPathConsumer(g_enable.BoolValue && g_pathEnable.BoolValue); }
public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, ANNE_NEXTBOT_LIBRARY)) TankPathConsumer(g_enable.BoolValue && g_pathEnable.BoolValue);
}
public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, ANNE_NEXTBOT_LIBRARY)) {
        g_pathConsumer = false;
        for (int tank = 1; tank <= MaxClients; tank++) ResetTankPath(tank);
    }
}
public void OnPathEnableChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
    TankPathConsumer(g_enable.BoolValue && g_pathEnable.BoolValue);
    for (int tank = 1; tank <= MaxClients; tank++) ResetTankPath(tank);
}
void ResetTankPath(int tank) {
    g_pathFresh[tank] = g_pathBlocked[tank] = g_pathLadder[tank] = g_pathHasDirection[tank] = false;
    g_pathCheck[tank] = 0.0;
}
float TankDistance2D(const float a[3], const float b[3]) {
    float x = a[0] - b[0], y = a[1] - b[1];
    return SquareRoot(x * x + y * y);
}

// Physical ladder fallback uses distance to the box, not its mid-air origin.
bool TankNearLadder(const float position[3]) {
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, "func_simpleladder")) != -1) {
        float origin[3], mins[3], maxs[3], gap[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
        GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
        for (int axis = 0; axis < 3; axis++) {
            float low = origin[axis] + mins[axis], high = origin[axis] + maxs[axis];
            gap[axis] = position[axis] < low ? low - position[axis] : (position[axis] > high ? position[axis] - high : 0.0);
        }
        if (gap[2] <= 72.0 && SquareRoot(gap[0] * gap[0] + gap[1] * gap[1]) <= 180.0) return true;
    }
    return false;
}
void TankPathUpdate(int tank, const float position[3]) {
    float now = GetGameTime();
    if (now < g_pathCheck[tank]) return;
    g_pathCheck[tank] = now + 0.1;
    bool wasFresh = g_pathFresh[tank], wasBlocked = g_pathBlocked[tank];
    g_pathFresh[tank] = g_pathBlocked[tank] = g_pathLadder[tank] = g_pathHasDirection[tank] = false;
    // The module switch also disables its physical fallback. Missing extension
    // with the switch ON is different: ordinary collision/ladder guards remain.
    if (!g_pathEnable.BoolValue) return;
    int count, current;
    bool complete;
    float age;
    if (g_pathConsumer && TankPathReady()
        && AnneNextBot_GetPathSnapshotInfo(tank, count, current, complete, age)
        && count > 0 && current >= 0 && current < count && age >= 0.0 && age <= 0.35) {
        g_pathFresh[tank] = true;
        g_pathReadAt[tank] = now - age;
        float previous[3]; previous = position;
        float reach;
        int end = current + 10;
        if (end > count) end = count;
        for (int index = current; index < end; index++) {
            Address area;
            int traverse, type;
            float goal[3], pathForward[3], length, fromStart;
            if (!AnneNextBot_GetPathSegment(tank, index, area, traverse, goal, type, pathForward, length, fromStart)) {
                g_pathFresh[tank] = false; break;
            }
            float start = reach;
            reach += TankDistance2D(previous, goal);
            bool ladder = type == view_as<int>(AnneNextBotPathSegment_LadderUp) || type == view_as<int>(AnneNextBotPathSegment_LadderDown);
            bool special = type != view_as<int>(AnneNextBotPathSegment_OnGround);
            // Ladder goal is the entrance; other transitions start at the previous goal.
            if (ladder && reach <= 180.0) g_pathLadder[tank] = true;
            if ((ladder && reach <= 180.0) || (special && !ladder && start <= 160.0)
                || (FloatAbs(goal[2] - previous[2]) > 56.0 && start <= 160.0)) g_pathBlocked[tank] = true;
            if (special) break;
            // Look ahead along the native route, but do not cut a corner. Keep
            // the first meaningful goal rather than aiming through later walls.
            if (!g_pathHasDirection[tank] && TankDistance2D(position, goal) >= 32.0) {
                MakeVectorFromPoints(position, goal, g_pathDirection[tank]);
                g_pathDirection[tank][2] = 0.0;
                NormalizeVector(g_pathDirection[tank], g_pathDirection[tank]);
                g_pathHasDirection[tank] = true;
            }
            previous = goal;
            if (reach > 320.0) break;
        }
    }
    if (!g_pathFresh[tank]) {
        g_pathHasDirection[tank] = false;
        g_pathLadder[tank] = TankNearLadder(position);
        g_pathBlocked[tank] = g_pathLadder[tank];
    }
    if (wasFresh != g_pathFresh[tank]) TankEvent(tank, "path", g_pathFresh[tank] ? "snapshot fresh" : "snapshot unavailable/stale; physical fallback");
    if (wasBlocked != g_pathBlocked[tank]) TankEvent(tank, "path", g_pathBlocked[tank] ? "traversal ahead: yield added movement" : "ordinary route: release traversal guard");
}
bool TankPathAllowsAddedMove(int tank, const float wish[3], bool moving) {
    if (g_pathBlocked[tank]) return false;
    if (!g_pathFresh[tank] || GetGameTime() - g_pathReadAt[tank] > 0.45) return true;
    return !moving || !g_pathHasDirection[tank] || GetVectorDotProduct(wish, g_pathDirection[tank]) >= 0.7;
}
void TankLadderBrake(int tank) {
    float motion[3]; GetEntPropVector(tank, Prop_Data, "m_vecVelocity", motion);
    float speed = SquareRoot(motion[0] * motion[0] + motion[1] * motion[1]);
    float run = TankRunSpeed(tank);
    if (speed > run * 1.1) {
        LimitHorizontalSpeed(motion, run);
        TeleportEntity(tank, NULL_VECTOR, NULL_VECTOR, motion);
        strcopy(g_commandOwner[tank], sizeof(g_commandOwner[]), "hop");
    }
}
