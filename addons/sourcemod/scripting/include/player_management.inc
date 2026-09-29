#if defined _player_management_included
	#endinput
#endif
#define _player_management_included

#include <sourcemod>

/** Optional mode-manager action. Returns true only after a human has moved to spectators.
 * Existing spectators, Tanks and infected controlling survivors are rejected.
 * The loaded manager's spectator restrictions still apply.
 */
native bool PlayerManagement_MoveToSpectator(int client);

public SharedPlugin __pl_player_management =
{
	name = "player_management",
	file = "",
	required = 0,
};

public void __pl_player_management_SetNTVOptional()
{
	MarkNativeAsOptional("PlayerManagement_MoveToSpectator");
}

/** Action-time guard shared by the two mode-specific native providers. */
stock bool PlayerManagement_CanMoveToSpectator(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client)
		|| IsFakeClient(client) || IsClientInKickQueue(client)) return false;

	int team = GetClientTeam(client);
	if (team != 2 && team != 3) return false;
	if (team != 3) return true;

	if (!HasEntProp(client, Prop_Send, "m_zombieClass")
		|| GetEntProp(client, Prop_Send, "m_zombieClass") == 8) return false;

	static const char victimProps[][] = {
		"m_tongueVictim", "m_pounceVictim", "m_jockeyVictim", "m_pummelVictim", "m_carryVictim"
	};
	for (int i = 0; i < sizeof(victimProps); i++)
	{
		if (!HasEntProp(client, Prop_Send, victimProps[i])) continue;
		int victim = GetEntPropEnt(client, Prop_Send, victimProps[i]);
		if (victim > 0 && victim <= MaxClients && IsClientInGame(victim)
			&& GetClientTeam(victim) == 2) return false;
	}
	return true;
}
