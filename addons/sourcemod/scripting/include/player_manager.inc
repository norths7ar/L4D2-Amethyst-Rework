#if defined _player_manager_included
	#endinput
#endif
#define _player_manager_included

/** Player manager queries for survivor counts, round state and reservations. */
native int PlayerManager_GetHumanSurvivorCount();
native int PlayerManager_GetSurvivorCount();
native bool PlayerManager_IsHumanSurvivor(int client);
native bool PlayerManager_IsRoundLive();
native bool PlayerManager_ShouldKeepSurvivorBots();
/** Whether survivor reservations have been restored, released or expired. Spectators never hold readiness. */
native bool PlayerManager_AreReservationsSettled();
/** Read a pending survivor by zero-based ordinal for the loading panel. */
native bool PlayerManager_GetWaitingSurvivor(int index, char[] name, int maxlen, int &seconds);

public SharedPlugin __pl_player_manager =
{
	name = "player_manager",
	file = "optional/coop/player_manager.smx",
	required = 0,
};

#if !defined REQUIRE_PLUGIN
public void __pl_player_manager_SetNTVOptional()
{
	MarkNativeAsOptional("PlayerManager_GetHumanSurvivorCount");
	MarkNativeAsOptional("PlayerManager_GetSurvivorCount");
	MarkNativeAsOptional("PlayerManager_IsHumanSurvivor");
	MarkNativeAsOptional("PlayerManager_IsRoundLive");
	MarkNativeAsOptional("PlayerManager_ShouldKeepSurvivorBots");
	MarkNativeAsOptional("PlayerManager_AreReservationsSettled");
	MarkNativeAsOptional("PlayerManager_GetWaitingSurvivor");
}
#endif
