Handle
	g_forwardUpdateBosses;

ConVar
	g_hCvarBossVoting;

bool
	bv_bTank,
	bv_bWitch;

int
	bv_iTank,
	bv_iWitch;

void BV_OnPluginStart()
{
	g_forwardUpdateBosses = CreateGlobalForward("OnUpdateBosses", ET_Ignore, Param_Cell, Param_Cell);

	g_hCvarBossVoting = CreateConVar("l4d_boss_vote", "1", "Enable boss voting", FCVAR_NOTIFY, true, 0.0, true, 1.0); // Sets if boss voting is enabled or disabled

	RegConsoleCmd("sm_voteboss", VoteBossCmd); // Allows players to vote for custom boss spawns
	RegConsoleCmd("sm_bossvote", VoteBossCmd); // Allows players to vote for custom boss spawns

	RegAdminCmd("sm_forcetank", ForceTankCommand, ADMFLAG_BAN);
	RegAdminCmd("sm_forcewitch", ForceWitchCommand, ADMFLAG_BAN);
}

bool RunVoteChecks(int client)
{
	if (g_bIsRemix)
	{
		CPrintToChat(client, "%t %t", "BV_Tag", "BV_NotAvailable");
		return false;
	}
	if (!g_ReadyUpAvailable || !IsInReady())
	{
		CPrintToChat(client, "%t %t", "BV_Tag", "BV_Available");
		return false;
	}
	if (InSecondHalfOfRound())
	{
		CPrintToChat(client, "%t %t", "BV_Tag", "BV_FirstRound");
		return false;
	}
	if (GetClientTeam(client) == 1)
	{
		CPrintToChat(client, "%t %t", "BV_Tag", "BV_NotAvailableForSpec");
		return false;
	}
	if (!IsNewBuiltinVoteAllowed())
	{
		CPrintToChat(client, "%t %t", "BV_Tag", "BV_CannotBeCalled");
		return false;
	}
	return true;
}

Action VoteBossCmd(int client, int args)
{
	if (!client || !IsClientInGame(client))
	{
		ReplyToCommand(client, "[Boss Vote] This command can only be used by an in-game player.");
		return Plugin_Handled;
	}

	if (!GetConVarBool(g_hCvarBossVoting)) {
		return Plugin_Handled;
	}

	if (!RunVoteChecks(client)) {
		return Plugin_Handled;
	}

	if (args != 2)
	{
		CReplyToCommand(client, "%t", "BV_Usage");
		CReplyToCommand(client, "%t", "BV_Usage2");
		return Plugin_Handled;
	}

	// Get all non-spectating players
	if (!VotePolicy_CheckCaller(client)) return Plugin_Handled;

	int iNumPlayers;
	int[] iPlayers = new int[MaxClients];
	for (int i=1; i<=MaxClients; i++)
	{
		if (!VotePolicy_IsPlayingHuman(i))
		{
			continue;
		}
		iPlayers[iNumPlayers++] = i;
	}

	// Get Requested Boss Percents
	char bv_sTank[32];
	char bv_sWitch[32];
	GetCmdArg(1, bv_sTank, sizeof(bv_sTank));
	GetCmdArg(2, bv_sWitch, sizeof(bv_sWitch));

	int tankPercent = -1;
	int witchPercent = -1;
	bool changeTank, changeWitch;

	// Make sure the args are actual numbers
	if (!IsInteger(bv_sTank) || !IsInteger(bv_sWitch))
	{
		CReplyToCommand(client, "%t %t", "BV_Tag", "BV_Invalid");
		return Plugin_Handled;
	}

	// Check to make sure static bosses don't get changed
	if (!IsStaticTankMap())
	{
		changeTank = (tankPercent = StringToInt(bv_sTank)) > 0;
	}
	else
	{
		changeTank = false;
		CReplyToCommand(client, "%t %t", "BV_Tag", "BV_TankStatic");
	}

	if (!IsStaticWitchMap())
	{
		changeWitch = (witchPercent = StringToInt(bv_sWitch)) > 0;
	}
	else
	{
		changeWitch = false;
		CReplyToCommand(client, "%t %t", "BV_Tag", "BV_WitchStatic");
	}

	// Check if percent is within limits
	if (changeTank && !IsTankPercentValid(tankPercent))
	{
		changeTank = false;
		tankPercent = -1;
		CReplyToCommand(client, "%t %t", "BV_Tag", "BV_TankBanned");
	}

	if (changeWitch && !IsWitchPercentValid(witchPercent, true))
	{
		changeWitch = false;
		witchPercent = -1;
		CReplyToCommand(client, "%t %t", "BV_Tag", "BV_WitchBanned");
	}

	char bv_voteTitle[64];

	// Set vote title
	if (changeTank && changeWitch)	// Both Tank and Witch can be changed
	{
		FormatEx(bv_voteTitle, 64, "%T", "BV_SetBosses", LANG_SERVER, bv_sTank, bv_sWitch);
	}
	else if (changeTank)	// Only Tank can be changed
	{
		if (witchPercent == 0)
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetTank", LANG_SERVER, bv_sTank);
		}
		else
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetOnlyTank", LANG_SERVER, bv_sTank);
		}
	}
	else if (changeWitch) // Only Witch can be changed
	{
		if (tankPercent == 0)
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetWitch", LANG_SERVER, bv_sWitch);
		}
		else
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetOnlyWitch", LANG_SERVER, bv_sWitch);
		}
	}
	else // Neither can be changed... ok...
	{
		if (tankPercent == 0 && witchPercent == 0)
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetBossesDisabled", LANG_SERVER);
		}
		else if (tankPercent == 0)
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetTankDisabled", LANG_SERVER);
		}
		else if (witchPercent == 0)
		{
			FormatEx(bv_voteTitle, 64, "%T", "BV_SetWitchDisabled", LANG_SERVER);
		}
		else // Probably not.
		{
			return Plugin_Handled;
		}
	}

	// Start the vote!
	Handle bv_hVote = CreateBuiltinVote(BossVoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
	if (bv_hVote == null) return Plugin_Handled;
	SetBuiltinVoteArgument(bv_hVote, bv_voteTitle);
	SetBuiltinVoteInitiator(bv_hVote, client);
	SetBuiltinVoteResultCallback(bv_hVote, BossVoteResultHandler);
	if (!DisplayBuiltinVote(bv_hVote, iPlayers, iNumPlayers, 20))
	{
		// A start veto may already have ended and destroyed the vote.
		if (IsValidHandle(bv_hVote)) delete bv_hVote;
		return Plugin_Handled;
	}
	bv_iTank = tankPercent;
	bv_iWitch = witchPercent;
	bv_bTank = changeTank;
	bv_bWitch = changeWitch;
	FakeClientCommand(client, "Vote Yes");

	return Plugin_Handled;
}

void BossVoteActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
	}
}

void BossVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i=0; i<num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_clients / 2))
			{

				// One last ready-up check.
				if (!g_ReadyUpAvailable || !IsInReady())  {
					DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
					CPrintToChatAll("%t", "BV_OnlyReadyUp");
					return;
				}

				if (!g_hCvarBossVoting.BoolValue || g_bIsRemix || InSecondHalfOfRound()
					|| (bv_iTank >= 0 && IsStaticTankMap())
					|| (bv_iWitch >= 0 && IsStaticWitchMap())
					|| !ApplyBossChange(bv_iTank, bv_iWitch))
				{
					DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
					CPrintToChatAll("%t %t", "BV_Tag", "BV_Invalid");
					return;
				}

				if (bv_bTank && bv_bWitch)	// Both Tank and Witch can be changed
				{
					char buffer[64];
					FormatEx(buffer, sizeof(buffer), "%T", "BV_SettingBoss", LANG_SERVER);
					DisplayBuiltinVotePass(vote, buffer);
				}
				else if (bv_bTank)	// Only Tank can be changed -- Witch must be static
				{
					char buffer[64];
					FormatEx(buffer, sizeof(buffer), "%T", "BV_SettingTank", LANG_SERVER);
					DisplayBuiltinVotePass(vote, buffer);
				}
				else if (bv_bWitch) // Only Witch can be changed -- Tank must be static
				{
					char buffer[64];
					FormatEx(buffer, sizeof(buffer), "%T", "BV_SettingWitch", LANG_SERVER);
					DisplayBuiltinVotePass(vote, buffer);
				}
				else // Neither can be changed... ok...
				{
					char buffer[64];
					FormatEx(buffer, sizeof(buffer), "%T", "BV_SettingBossDisabled", LANG_SERVER);
					DisplayBuiltinVotePass(vote, buffer);
				}

				// Forward da message man :) Publish the applied values, never rejected requests.
				PublishBossChange();

				return;
			}
		}
	}

	// Vote Failed
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	return;
}

bool IsInteger(const char[] buffer)
{
	// Negative values mean unchanged. Reject empty, bare minus and overflow.
	int start = buffer[0] == '-' ? 1 : 0;
	int len = strlen(buffer);
	if (len == start || len > 10) return false;
	int value;
	for (int i = start; i < len; i++)
	{
		if (!IsCharNumeric(buffer[i])) return false;
		int digit = buffer[i] - '0';
		if (value > (2147483647 - digit) / 10) return false;
		value = value * 10 + digit;
	}
	return true;
}

int g_iAppliedTank, g_iAppliedWitch;

bool ApplyBossChange(int tankPercent, int witchPercent)
{
	int round = InSecondHalfOfRound() ? 1 : 0;
	bool oldWitchEnabled = L4D2Direct_GetVSWitchToSpawnThisRound(round);
	float oldWitchFlow = GetWitchFlow(round);
	if (!SetBossPercents(tankPercent, witchPercent)) return false;

	// A Tank-only change can relocate or disable an existing conflicting Witch.
	bool witchChanged = witchPercent >= 0
		|| oldWitchEnabled != L4D2Direct_GetVSWitchToSpawnThisRound(round)
		|| oldWitchFlow != GetWitchFlow(round);
	if (tankPercent >= 0)
		g_bTankDisabled = !L4D2Direct_GetVSTankToSpawnThisRound(round);
	if (witchChanged)
		g_bWitchDisabled = !L4D2Direct_GetVSWitchToSpawnThisRound(round);
	GetBossPercents(null);
	UpdateReadyUpFooter();

	// Keep -1 for untouched bosses; otherwise publish the actual final value.
	g_iAppliedTank = tankPercent < 0 ? -1 : g_fTankPercent;
	g_iAppliedWitch = witchChanged ? g_fWitchPercent : -1;
	return true;
}

void PublishBossChange()
{
	Call_StartForward(g_forwardUpdateBosses);
	Call_PushCell(g_iAppliedTank);
	Call_PushCell(g_iAppliedWitch);
	Call_Finish();
}

/* ========================================================
// ==================== Admin Commands ====================
// ========================================================
 *
 * Where the admin commands for setting boss spawns will go
 *
 * vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
*/

Action ForceTankCommand(int client, int args)
{
	if (client && !IsClientInGame(client))
		return Plugin_Handled;

	if (!GetConVarBool(g_hCvarBossVoting)) {
		return Plugin_Handled;
	}

	if (g_bIsRemix)
	{
		CReplyToCommand(client, "%t", "BV_CommandNotAvailable");
		return Plugin_Handled;
	}

	if (IsStaticTankMap())
	{
		CReplyToCommand(client, "%t", "BV_TankSpawnStatic");
		return Plugin_Handled;
	}

	if (!g_ReadyUpAvailable || !IsInReady())
	{
		CReplyToCommand(client, "%t", "BV_OnlyReadyUp");
		return Plugin_Handled;
	}

	// Get Requested Tank Percent
	char bv_sTank[32];
	GetCmdArg(1, bv_sTank, 32);

	// Make sure the cmd argument is a number
	if (!IsInteger(bv_sTank))
		return Plugin_Handled;

	// Convert it to in int boy
	int p_iRequestedPercent = StringToInt(bv_sTank);

	if (p_iRequestedPercent < 0)
	{
		CReplyToCommand(client, "%t", "BV_PercentageInvalid");
		return Plugin_Handled;
	}

	// Check if percent is within limits
	if (!ApplyBossChange(p_iRequestedPercent, -1))
	{
		CReplyToCommand(client, "%t", "BV_Percentagebanned");
		return Plugin_Handled;
	}


	// Let everybody know
	char clientName[32];
	if (client) GetClientName(client, clientName, sizeof(clientName));
	else strcopy(clientName, sizeof(clientName), "Console");
	CPrintToChatAll("%t", "BV_TankSpawnAdmin", g_fTankPercent, clientName);

	// Forward da message man :)
	PublishBossChange();

	return Plugin_Handled;
}

Action ForceWitchCommand(int client, int args)
{
	if (client && !IsClientInGame(client))
		return Plugin_Handled;

	if (!GetConVarBool(g_hCvarBossVoting)) {
		return Plugin_Handled;
	}

	if (g_bIsRemix)
	{
		CReplyToCommand(client, "%t", "BV_CommandNotAvailable");
		return Plugin_Handled;
	}

	if (IsStaticWitchMap())
	{
		CReplyToCommand(client, "%t", "BV_WitchSpawnStatic");
		return Plugin_Handled;
	}

	if (!g_ReadyUpAvailable || !IsInReady())
	{
		CReplyToCommand(client, "%t", "BV_OnlyReadyUp");
		return Plugin_Handled;
	}

	// Get Requested Witch Percent
	char bv_sWitch[32];
	GetCmdArg(1, bv_sWitch, 32);

	// Make sure the cmd argument is a number
	if (!IsInteger(bv_sWitch))
		return Plugin_Handled;

	// Convert it to in int boy
	int p_iRequestedPercent = StringToInt(bv_sWitch);

	if (p_iRequestedPercent < 0)
	{
		CReplyToCommand(client, "%t", "BV_PercentageInvalid");
		return Plugin_Handled;
	}

	// Check if percent is within limits
	if (!ApplyBossChange(-1, p_iRequestedPercent))
	{
		CReplyToCommand(client, "%t", "BV_Percentagebanned");
		return Plugin_Handled;
	}


	// Let everybody know
	char clientName[32];
	if (client) GetClientName(client, clientName, sizeof(clientName));
	else strcopy(clientName, sizeof(clientName), "Console");
	CPrintToChatAll("%t", "BV_WitchSpawnAdmin", g_fWitchPercent, clientName);

	// Forward da message man :)
	PublishBossChange();

	return Plugin_Handled;
}
