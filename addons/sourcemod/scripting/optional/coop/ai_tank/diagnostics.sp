// Optional observer: logging must never be a load-time or gameplay dependency.
#include <ai_diagnostics>

char g_commandOwner[MAXPLAYERS + 1][16], g_lastOwner[MAXPLAYERS + 1][16];

void TankEvent(int tank, const char[] category, const char[] detail) {
    if (GetFeatureStatus(FeatureType_Native, "AIDiag_Event") == FeatureStatus_Available)
        AIDiag_Event(tank, category, detail);
}

void TankCommandLog(int tank, int rawButtons, const float rawVel[3], int buttons, const float vel[3]) {
    if (!StrEqual(g_lastOwner[tank], g_commandOwner[tank])) {
        char detail[64];
        Format(detail, sizeof(detail), "%s -> %s", g_lastOwner[tank][0] ? g_lastOwner[tank] : "native", g_commandOwner[tank]);
        TankEvent(tank, "owner", detail);
        strcopy(g_lastOwner[tank], sizeof(g_lastOwner[]), g_commandOwner[tank]);
    }
    if (GetFeatureStatus(FeatureType_Native, "AIDiag_Command") == FeatureStatus_Available)
        AIDiag_Command(tank, GetClientOfUserId(g_targetUserId[tank]), g_commandOwner[tank], rawButtons, rawVel, buttons, vel);
}
