#if defined _ai_diagnostics_included
    #endinput
#endif
#define _ai_diagnostics_included

#include <sourcemod>

#define AIDIAG_LIBRARY "ai_diagnostics"
#define AIDIAG_VERSION "1.0.1"

// Observation only. client/target are entity indices, never names/SteamIDs/IPs.
// category/detail/owner must contain only AI state/reasons, not player data.
// Calls enqueue bounded records; command calls are throttled by the logger per
// client AND owner, retaining raw/final buttons and velocity (including 0/-1).
// Repeated snapshots yield queue capacity before events; existing three-argument
// callers retain event priority. This does not change capture frequency.
native void AIDiag_Event(int client, const char[] category, const char[] detail, bool sampled = false);
native void AIDiag_Command(int client, int target, const char[] owner,
    int rawButtons, const float rawVel[3], int finalButtons, const float finalVel[3]);

stock bool AIDiag_IsAvailable()
{
    return GetFeatureStatus(FeatureType_Native, "AIDiag_Event") == FeatureStatus_Available
        && GetFeatureStatus(FeatureType_Native, "AIDiag_Command") == FeatureStatus_Available;
}

stock void AIDiag_TryEvent(int client, const char[] category, const char[] detail, bool sampled = false)
{
    if (GetFeatureStatus(FeatureType_Native, "AIDiag_Event") == FeatureStatus_Available)
        AIDiag_Event(client, category, detail, sampled);
}

stock void AIDiag_TryCommand(int client, int target, const char[] owner,
    int rawButtons, const float rawVel[3], int finalButtons, const float finalVel[3])
{
    if (GetFeatureStatus(FeatureType_Native, "AIDiag_Command") == FeatureStatus_Available)
        AIDiag_Command(client, target, owner, rawButtons, rawVel, finalButtons, finalVel);
}

#if !defined AIDIAG_IMPLEMENTATION
// Always optional, even when a caller defines SourceMod's REQUIRE_PLUGIN.
public SharedPlugin __pl_ai_diagnostics =
{
    name = AIDIAG_LIBRARY,
    file = "ai_diagnostics.smx",
    required = 0
};

public void __pl_ai_diagnostics_SetNTVOptional()
{
    MarkNativeAsOptional("AIDiag_Event");
    MarkNativeAsOptional("AIDiag_Command");
}
#endif
