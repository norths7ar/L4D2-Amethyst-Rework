#if defined _si_unstuck_included
    #endinput
#endif
#define _si_unstuck_included

#include <sourcemod>

// Observation only; never changes the watchdog's movement or recovery policy.
// True from the existing 2-second Tank warning until progress, an engine-owned
// action, successful relocation, disable, death or lifecycle reset. Failed
// relocation/retry and temporary loss of pursuit do NOT start another episode.
// episode and startedAt stay fixed while active (including watchdog pauses).
// startedAt is GetGameTime() at first entry; consumers use it to avoid replaying
// a full notification on late load/reload. IDs are local to this provider/map.
// Invalid/inactive clients return false and zero both outputs.
native bool SIUnstuck_GetTankStall(int client, int &episode, float &startedAt);

forward void SIUnstuck_OnTankStallChanged(int client, bool stalled, int episode, float startedAt);

#if !defined SI_UNSTUCK_IMPLEMENTATION
public SharedPlugin __pl_si_unstuck =
{
    name = "si_unstuck",
    file = "si_unstuck.smx",
    required = 0
};

public void __pl_si_unstuck_SetNTVOptional()
{
    MarkNativeAsOptional("SIUnstuck_GetTankStall");
}
#endif
