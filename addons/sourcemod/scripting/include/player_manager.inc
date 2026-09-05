#if defined _player_manager_included
	#endinput
#endif
#define _player_manager_included

/** Shared Coop player/seat helpers. */
native int Coop_GetHumanSurvivorCount();
native int Coop_GetTotalSurvivorCount();
native bool Coop_IsHumanSurvivor(int client);
native bool Coop_IsRoundLive();
native bool Coop_ShouldKeepSurvivorBots();
/** Whether survivor reservations have been restored, released or expired. Spectators never hold readiness. */
native bool Coop_IsRosterStable();
/** Read a pending survivor by zero-based ordinal for the loading panel. */
native bool Coop_GetWaitingSurvivor(int index, char[] name, int maxlen, int &seconds);

public SharedPlugin __pl_player_manager =
{
	name = "player_manager",
	file = "optional/coop/player_manager.smx",
	required = 0,
};

#if !defined REQUIRE_PLUGIN
public void __pl_player_manager_SetNTVOptional()
{
	MarkNativeAsOptional("Coop_GetHumanSurvivorCount");
	MarkNativeAsOptional("Coop_GetTotalSurvivorCount");
	MarkNativeAsOptional("Coop_IsHumanSurvivor");
	MarkNativeAsOptional("Coop_IsRoundLive");
	MarkNativeAsOptional("Coop_ShouldKeepSurvivorBots");
	MarkNativeAsOptional("Coop_IsRosterStable");
	MarkNativeAsOptional("Coop_GetWaitingSurvivor");
}
#endif
