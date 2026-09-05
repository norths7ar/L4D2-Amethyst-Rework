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
/** Whether current-map reservations have been restored or expired. */
native bool Coop_IsRosterStable();

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
}
#endif
