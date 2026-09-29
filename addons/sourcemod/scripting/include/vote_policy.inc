#if defined _vote_policy_included
	#endinput
#endif
#define _vote_policy_included

#include <sourcemod>

/** Optional loading/participation guard supplied by blocktrolls. */
native bool BlockTrolls_CanVote(int client);

public SharedPlugin __pl_vote_policy =
{
	name = "blocktrolls",
	file = "blocktrolls.smx",
	required = 0,
};

public void __pl_vote_policy_SetNTVOptional()
{
	MarkNativeAsOptional("BlockTrolls_CanVote");
}

/** Electorate membership, independent of the map loading guard. */
stock bool VotePolicy_IsPlayingHuman(int client)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client))
		return false;

	int team = GetClientTeam(client);
	return team == 2 || team == 3;
}

/** Call at vote submission, not merely when opening a menu. */
stock bool VotePolicy_CheckCaller(int client)
{
	if (!VotePolicy_IsPlayingHuman(client))
	{
		ReplyToCommand(client, "[投票] 只有正在游戏中的玩家可以发起投票。");
		return false;
	}
	if (GetFeatureStatus(FeatureType_Native, "BlockTrolls_CanVote") == FeatureStatus_Available
		&& !BlockTrolls_CanVote(client))
	{
		PrintToChat(client, "[投票] 玩家仍在载入，请稍后再发起投票。");
		return false;
	}
	return true;
}
