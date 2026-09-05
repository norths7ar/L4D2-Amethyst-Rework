#if defined _coop_player_manager_included
	#endinput
#endif
#define _coop_player_manager_included

/** Shared Coop player/seat helpers. */
native int Coop_GetHumanSurvivorCount();
native int Coop_GetHumanInfectedCount();
native int Coop_GetTotalSurvivorCount();
native bool Coop_IsHumanSurvivor(int client);
native bool Coop_IsHumanInfected(int client);
native bool Coop_IsRoundLive();
native bool Coop_ShouldKeepSurvivorBots();

public SharedPlugin __pl_coop_player_manager =
{
	name = "coop_player_manager",
	file = "optional/coop/player_manager.smx",
	required = 0,
};

#if !defined REQUIRE_PLUGIN
public void __pl_coop_player_manager_SetNTVOptional()
{
	MarkNativeAsOptional("Coop_GetHumanSurvivorCount");
	MarkNativeAsOptional("Coop_GetHumanInfectedCount");
	MarkNativeAsOptional("Coop_GetTotalSurvivorCount");
	MarkNativeAsOptional("Coop_IsHumanSurvivor");
	MarkNativeAsOptional("Coop_IsHumanInfected");
	MarkNativeAsOptional("Coop_IsRoundLive");
	MarkNativeAsOptional("Coop_ShouldKeepSurvivorBots");
}
#endif
