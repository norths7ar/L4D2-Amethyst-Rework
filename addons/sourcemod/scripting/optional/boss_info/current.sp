ConVar g_hVsBossBuffer;


void Cur_OnPluginStart()
{
	g_hVsBossBuffer = FindConVar("versus_boss_buffer");

	RegConsoleCmd("sm_cur", CurrentCmd);
	RegConsoleCmd("sm_current", CurrentCmd);
}

Action CurrentCmd(int client, int args)
{
	if (!client || !IsClientInGame(client))
		return Plugin_Handled;

	float proximity;
	if (!GetBossProximity(proximity))
	{
		CPrintToChat(client, "%t %t", "Cur_Tag", "Cur_Unavailable");
		return Plugin_Handled;
	}
	int boss_proximity = RoundToNearest(proximity * 100.0);
	CPrintToChat(client, "%t %t", "Cur_Tag", "Cur_Current", boss_proximity);
	return Plugin_Handled;
}

/**
 * Calculates the proximity of the boss to the survivors.
 *
 * @return Whether valid flow data was available.
 */
bool GetBossProximity(float &proximity)
{
	float maxFlow = L4D2Direct_GetMapMaxFlowDistance();
	float buffer = g_hVsBossBuffer.FloatValue;
	float flow;
	if (!IsValidFlow(maxFlow) || maxFlow <= 0.0 || !IsValidFlow(buffer)
		|| !GetMaxSurvivorFlow(flow)) return false;
	proximity = (flow + buffer) / maxFlow;
	if (!IsValidFlow(proximity)) return false;
	if (proximity > 1.0) proximity = 1.0;
	return true;
}

/**
 * Reads the furthest valid flow among living survivors.
 *
 * @return Whether at least one living survivor had valid nav flow.
 */
bool GetMaxSurvivorFlow(float &flow)
{
	flow = 0.0;
	bool found;
	Address pNavArea;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVORS && IsPlayerAlive(i)) {
			pNavArea = L4D_GetLastKnownArea(i);
			if (pNavArea != Address_Null) {
				float tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
				if (!IsValidFlow(tmp_flow)) continue;
				flow = (flow > tmp_flow) ? flow : tmp_flow;
				found = true;
			}
		}
	}

	return found;
}

bool IsValidFlow(float value)
{
	// Reject negative/unreachable distances, NaN, infinity and FLT_MAX nav sentinels.
	return value >= 0.0 && value < view_as<float>(0x7F7FFFFF);
}

/**
 * Check if the translation file exists
 *
 * @param translation	Translation name.
 * @noreturn
 */
stock void LoadTranslation(const char[] translation)
{
	char
		sPath[PLATFORM_MAX_PATH],
		sName[64];

	FormatEx(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}
