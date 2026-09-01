#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <imatchext>

#define PLUGIN_VERSION "2.0.0"
#define MISSION_CYCLE_PATH "configs/missioncycle.txt"
#define MAX_MAP_NAME 128
#define MAP_CHANGE_DELAY 3.0
#define FINALE_CHANGE_DELAY 6.0
#define AUTO_MENU_DELAY 5.0

/**
 * Campaign Switcher started as Chris Pringle's Automatic Campaign Switcher and
 * was adapted for AstMod by 海洋空氣. This implementation keeps its finale
 * selection model, but uses imatchext's live Mission Cache for mission/chapter
 * facts and missioncycle.txt only for the server owner's allow-list, order and
 * display-name policy.
 *
 * Player-facing terminology intentionally uses Map for a complete mission and
 * Chapter for one BSP. Internally the game and imatchext call a complete Map a
 * Mission, so those names remain in API-facing code.
 *
 * The immediate vote flow follows Forgetest's vote_custom_campaigns plugin:
 * https://github.com/Target5150/MoYu_Server_Stupid_Plugins
 */

public Plugin myinfo =
{
	name = "Campaign Switcher",
	author = "Chris Pringle, 海洋空氣, Forgetest, Amethyst Rework",
	description = "Immediate Map votes, finale Map selection and Chapter votes",
	version = PLUGIN_VERSION,
	url = "https://github.com/Sglight/L4D2-Amethyst-Rework"
};

ArrayList g_mapMissions;
ArrayList g_mapFirstChapters;
ArrayList g_mapDisplayNames;
ArrayList g_mapOfficial;

ConVar g_voteParticipation;
ConVar g_votePassPercent;

char g_changeVoteMap[MAX_MAP_NAME];
char g_changeVoteName[MAX_MAP_NAME];
char g_nextMapVote[MAXPLAYERS + 1][MAX_MAP_NAME];
bool g_nextMapMenuShown[MAXPLAYERS + 1];
bool g_finaleChangeScheduled;

public void OnPluginStart()
{
	LoadTranslations("imatchext.phrases");

	g_mapMissions = new ArrayList();
	g_mapFirstChapters = new ArrayList(MAX_MAP_NAME);
	g_mapDisplayNames = new ArrayList(MAX_MAP_NAME);
	g_mapOfficial = new ArrayList();

	g_voteParticipation = CreateConVar(
		"campaign_vote_participation",
		"0.60",
		"Fraction of eligible players who must cast a vote before a Map or Chapter vote can pass.",
		FCVAR_NOTIFY,
		true,
		0.0,
		true,
		1.0
	);
	g_votePassPercent = CreateConVar(
		"campaign_vote_pass_percent",
		"0.60",
		"Fraction of cast votes that must approve an immediate Map or Chapter change.",
		FCVAR_NOTIFY,
		true,
		0.0,
		true,
		1.0
	);

	CreateConVar(
		"campaign_switcher_version",
		PLUGIN_VERSION,
		"Campaign Switcher version.",
		FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD
	);

	RegConsoleCmd("sm_mapvote", Command_MapVote, "Vote to change to another Map now");
	RegConsoleCmd("sm_nextmap", Command_NextMap, "Choose the Map played after the finale");
	RegConsoleCmd("sm_chaptervote", Command_ChapterVote, "Vote to change Chapter within the current Map");
	RegAdminCmd("sm_campaign_reload", Command_ReloadMaps, ADMFLAG_CHANGEMAP, "Reload missioncycle.txt against the Mission Cache");

	HookEvent("finale_win", Event_FinaleWin);

	ResetNextMapVotes();
}

public void OnConfigsExecuted()
{
	ReloadMapRegistry();
}

public void OnMapStart()
{
	ResetNextMapVotes();
	g_finaleChangeScheduled = false;
	CreateTimer(0.5, Timer_ReloadRegistry, _, TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(AUTO_MENU_DELAY, Timer_ShowFinaleMenus, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMissionCacheReload()
{
	CreateTimer(0.1, Timer_ReloadRegistry, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client)
{
	if (IsFakeClient(client))
		return;

	CreateTimer(AUTO_MENU_DELAY, Timer_ShowFinaleMenuToClient, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
	g_nextMapVote[client][0] = '\0';
	g_nextMapMenuShown[client] = false;
}

public Action Timer_ReloadRegistry(Handle timer)
{
	ReloadMapRegistry();
	return Plugin_Stop;
}

public Action Command_ReloadMaps(int client, int args)
{
	if (ReloadMapRegistry())
		ReplyToCommand(client, "[地图] 已载入 %d 张 Map。", g_mapMissions.Length);
	else
		ReplyToCommand(client, "[地图] 没有可用 Map，请检查 Mission Cache 与 missioncycle.txt。");

	return Plugin_Handled;
}

bool ReloadMapRegistry()
{
	g_mapMissions.Clear();
	g_mapFirstChapters.Clear();
	g_mapDisplayNames.Clear();
	g_mapOfficial.Clear();

	if (!ModeSymbol.IsValid(CurrentMode))
	{
		LogError("Cannot build Map registry: current game mode is unavailable in imatchext");
		return false;
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), MISSION_CYCLE_PATH);

	KeyValues policy = new KeyValues("MissionCycle");
	if (!policy.ImportFromFile(path))
	{
		delete policy;
		LogError("Cannot load %s", MISSION_CYCLE_PATH);
		return false;
	}

	if (policy.GotoFirstSubKey())
	{
		do
		{
			if (!policy.GotoFirstSubKey())
				continue;

			do
			{
				char firstChapter[MAX_MAP_NAME];
				char displayName[MAX_MAP_NAME];
				policy.GetSectionName(firstChapter, sizeof(firstChapter));
				policy.GetString("name", displayName, sizeof(displayName), firstChapter);

				MissionSymbol mission = FindMissionByFirstChapter(firstChapter);
				if (!MissionSymbol.IsValid(mission))
				{
					LogMessage("Skipping unavailable Map policy entry: %s (%s)", firstChapter, displayName);
					continue;
				}

				if (FindMapIndex(firstChapter) != -1)
				{
					LogError("Ignoring duplicate Map policy entry: %s", firstChapter);
					continue;
				}

				g_mapMissions.Push(view_as<int>(mission));
				g_mapFirstChapters.PushString(firstChapter);
				g_mapDisplayNames.PushString(displayName);
				g_mapOfficial.Push(mission.IsAddon ? 0 : 1);
			}
			while (policy.GotoNextKey());

			policy.GoBack();
		}
		while (policy.GotoNextKey());
	}

	delete policy;
	LogMessage("Loaded %d allowed Maps from %s", g_mapMissions.Length, MISSION_CYCLE_PATH);
	return g_mapMissions.Length > 0;
}

MissionSymbol FindMissionByFirstChapter(const char[] expectedMap)
{
	for (MissionSymbol mission = MissionSymbol.First(); MissionSymbol.IsValid(mission); mission = mission.Next())
	{
		if (mission.IsDisabled || CurrentMode.GetNumChapters(mission) < 1)
			continue;

		char mapName[MAX_MAP_NAME];
		char unusedDisplayName[1];
		if (GetChapterInfo(mission, 1, mapName, sizeof(mapName), unusedDisplayName, 0, LANG_SERVER)
			&& StrEqual(mapName, expectedMap, false))
		{
			return mission;
		}
	}

	return MissionSymbol_Invalid;
}

int FindMapIndex(const char[] firstChapter)
{
	char candidate[MAX_MAP_NAME];
	for (int i = 0; i < g_mapFirstChapters.Length; i++)
	{
		g_mapFirstChapters.GetString(i, candidate, sizeof(candidate));
		if (StrEqual(candidate, firstChapter, false))
			return i;
	}
	return -1;
}

int FindMapIndexByMission(MissionSymbol mission)
{
	for (int i = 0; i < g_mapMissions.Length; i++)
	{
		if (view_as<MissionSymbol>(g_mapMissions.Get(i)) == mission)
			return i;
	}
	return -1;
}

bool GetChapterInfo(
	MissionSymbol mission,
	int chapter,
	char[] mapName,
	int mapNameLength,
	char[] displayName,
	int displayNameLength,
	int client
)
{
	mapName[0] = '\0';
	if (displayNameLength > 0)
		displayName[0] = '\0';

	KeyValues chapterInfo = new KeyValues("chapter");
	if (!CurrentMode.ExportChapter(mission, chapter, chapterInfo))
	{
		delete chapterInfo;
		return false;
	}

	chapterInfo.GetString("Map", mapName, mapNameLength);
	char rawDisplayName[MAX_MAP_NAME];
	chapterInfo.GetString("DisplayName", rawDisplayName, sizeof(rawDisplayName));
	delete chapterInfo;

	if (!mapName[0])
		return false;

	if (displayNameLength > 0)
	{
		char localized[MAX_MAP_NAME];
		if (TranslateGamePhrase(rawDisplayName, localized, sizeof(localized), client))
			FormatEx(displayName, displayNameLength, "第%d关 - %s", chapter, localized);
		else if (rawDisplayName[0] && rawDisplayName[0] != '#')
			FormatEx(displayName, displayNameLength, "第%d关 - %s", chapter, rawDisplayName);
		else
			FormatEx(displayName, displayNameLength, "第%d关 - %s", chapter, mapName);
	}

	return true;
}

bool TranslateGamePhrase(const char[] rawPhrase, char[] output, int outputLength, int client)
{
	if (!rawPhrase[0])
		return false;

	char phrase[MAX_MAP_NAME];
	int source = rawPhrase[0] == '#' ? 1 : 0;
	int target;
	while (rawPhrase[source] && target < sizeof(phrase) - 1)
	{
		phrase[target++] = CharToLower(rawPhrase[source++]);
	}
	phrase[target] = '\0';

	if (!phrase[0] || !TranslationPhraseExists(phrase))
		return false;

	if (client != LANG_SERVER && !IsTranslatedForLanguage(phrase, GetClientLanguage(client)))
		return false;

	FormatEx(output, outputLength, "%T", phrase, client);
	return true;
}

public Action Command_MapVote(int client, int args)
{
	if (!IsEligibleHuman(client))
		return Plugin_Handled;

	if (!g_mapMissions.Length)
	{
		PrintToChat(client, "\x04[地图] \x01当前没有可投票的 Map。");
		return Plugin_Handled;
	}

	Menu menu = new Menu(MapSelectionHandler);
	menu.SetTitle("投票立即更换 Map\n共 %d 张", g_mapMissions.Length);
	menu.ExitButton = true;

	char firstChapter[MAX_MAP_NAME];
	char displayName[MAX_MAP_NAME];
	for (int i = 0; i < g_mapMissions.Length; i++)
	{
		g_mapFirstChapters.GetString(i, firstChapter, sizeof(firstChapter));
		g_mapDisplayNames.GetString(i, displayName, sizeof(displayName));
		menu.AddItem(firstChapter, displayName);
	}

	menu.Display(client, 60);
	return Plugin_Handled;
}

public int MapSelectionHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char firstChapter[MAX_MAP_NAME];
		menu.GetItem(item, firstChapter, sizeof(firstChapter));
		int mapIndex = FindMapIndex(firstChapter);
		if (mapIndex == -1)
		{
			PrintToChat(client, "\x04[地图] \x01该 Map 已不可用，请重新打开菜单。");
			return 0;
		}

		char displayName[MAX_MAP_NAME];
		g_mapDisplayNames.GetString(mapIndex, displayName, sizeof(displayName));
		StartImmediateChangeVote(client, firstChapter, displayName);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_ChapterVote(int client, int args)
{
	if (!IsEligibleHuman(client))
		return Plugin_Handled;

	MissionSymbol mission = CurrentMission;
	if (!MissionSymbol.IsValid(mission) || !ModeSymbol.IsValid(CurrentMode))
	{
		PrintToChat(client, "\x04[章节] \x01无法识别当前 Map。");
		return Plugin_Handled;
	}

	int chapterCount = CurrentMode.GetNumChapters(mission);
	if (chapterCount < 1)
	{
		PrintToChat(client, "\x04[章节] \x01当前 Map 没有可用 Chapter。");
		return Plugin_Handled;
	}

	char mapTitle[MAX_MAP_NAME];
	int currentIndex = FindMapIndexByMission(mission);
	if (currentIndex != -1)
		g_mapDisplayNames.GetString(currentIndex, mapTitle, sizeof(mapTitle));
	else
		mission.GetName(mapTitle, sizeof(mapTitle));

	Menu menu = new Menu(ChapterSelectionHandler);
	menu.SetTitle("%s\n选择 Chapter 后发起实时投票", mapTitle);
	menu.ExitButton = true;

	for (int chapter = 1; chapter <= chapterCount; chapter++)
	{
		char mapName[MAX_MAP_NAME];
		char displayName[MAX_MAP_NAME];
		if (!GetChapterInfo(mission, chapter, mapName, sizeof(mapName), displayName, sizeof(displayName), client))
			continue;
		if (!IsMapValid(mapName))
			continue;
		menu.AddItem(mapName, displayName);
	}

	if (!menu.ItemCount)
	{
		delete menu;
		PrintToChat(client, "\x04[章节] \x01当前 Map 没有有效 Chapter。");
		return Plugin_Handled;
	}

	menu.Display(client, 60);
	return Plugin_Handled;
}

public int ChapterSelectionHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char mapName[MAX_MAP_NAME];
		char displayName[MAX_MAP_NAME];
		menu.GetItem(item, mapName, sizeof(mapName), _, displayName, sizeof(displayName));
		if (!IsMapValid(mapName))
		{
			PrintToChat(client, "\x04[章节] \x01该 Chapter 已不可用。");
			return 0;
		}
		StartImmediateChangeVote(client, mapName, displayName);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool StartImmediateChangeVote(int client, const char[] mapName, const char[] displayName)
{
	if (!CheckVoteAccess(client))
		return false;

	int[] players = new int[MaxClients];
	int total;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsEligibleHuman(i))
			players[total++] = i;
	}

	if (!total)
		return false;

	Handle vote = CreateBuiltinVote(
		ImmediateVoteHandler,
		BuiltinVoteType_ChgCampaign,
		BuiltinVoteAction_Select | BuiltinVoteAction_Cancel | BuiltinVoteAction_End
	);

	strcopy(g_changeVoteMap, sizeof(g_changeVoteMap), mapName);
	strcopy(g_changeVoteName, sizeof(g_changeVoteName), displayName);
	SetBuiltinVoteArgument(vote, g_changeVoteName);
	SetBuiltinVoteInitiator(vote, client);
	SetBuiltinVoteResultCallback(vote, ImmediateVoteResult);

	if (!DisplayBuiltinVote(vote, players, total, FindConVar("sv_vote_timer_duration").IntValue))
	{
		delete vote;
		PrintToChat(client, "\x04[地图] \x01无法启动投票。");
		return false;
	}

	return true;
}

bool CheckVoteAccess(int client)
{
	if (!IsEligibleHuman(client))
		return false;

	if (IsBuiltinVoteInProgress())
	{
		PrintToChat(client, "\x04[地图] \x01已有投票正在进行。");
		return false;
	}

	int delay = CheckBuiltinVoteDelay();
	if (delay > 0)
	{
		PrintToChat(client, "\x04[地图] \x01请等待 %d 秒再发起投票。", delay);
		return false;
	}

	return true;
}

public int ImmediateVoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	if (action == BuiltinVoteAction_Cancel)
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Generic);
	else if (action == BuiltinVoteAction_End)
		delete vote;

	return 0;
}

public int ImmediateVoteResult(
	Handle vote,
	int numVotes,
	int numClients,
	const int[][] clientInfo,
	int numItems,
	const int[][] itemInfo
)
{
	if (numClients < 1 || float(numVotes) / float(numClients) < g_voteParticipation.FloatValue)
	{
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_NotEnoughVotes);
		return 0;
	}

	int yesVotes;
	for (int i = 0; i < numItems; i++)
	{
		if (itemInfo[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
			yesVotes = itemInfo[i][BUILTINVOTEINFO_ITEM_VOTES];
	}

	if (numVotes > 0 && float(yesVotes) / float(numVotes) >= g_votePassPercent.FloatValue)
	{
		DisplayBuiltinVotePass2(vote, TRANSLATION_L4D_VOTE_CHANGECAMPAIGN_PASSED, g_changeVoteName);
		ScheduleMapChange(g_changeVoteMap, g_changeVoteName, MAP_CHANGE_DELAY);
	}
	else
	{
		DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
	}

	return 0;
}

public Action Command_NextMap(int client, int args)
{
	if (!IsEligibleHuman(client))
		return Plugin_Handled;

	if (!IsMissionFinalMap())
	{
		PrintToChat(client, "\x04[下一张图] \x01只能在救援关选择下一张 Map。");
		return Plugin_Handled;
	}

	ShowNextMapMenu(client);
	return Plugin_Handled;
}

void ShowNextMapMenu(int client, int firstItem = 0)
{
	if (!IsEligibleHuman(client) || !IsMissionFinalMap() || !g_mapMissions.Length)
		return;

	int mapCount = g_mapMissions.Length;
	int[] counts = new int[mapCount];
	int votesCast;
	int highestVotes;
	int tiedMaps;
	int leader = BuildNextMapVoteStats(counts, votesCast, highestVotes, tiedMaps);
	int eligible = CountEligibleHumans();

	Menu menu = new Menu(NextMapMenuHandler);
	if (leader == -1)
		menu.SetTitle("选择下一张 Map（已投 %d/%d）\n尚无人投票", votesCast, eligible);
	else if (tiedMaps > 1)
		menu.SetTitle("选择下一张 Map（已投 %d/%d）\n%d 张 Map 以 %d 票并列领先", votesCast, eligible, tiedMaps, highestVotes);
	else
	{
		char leaderName[MAX_MAP_NAME];
		g_mapDisplayNames.GetString(leader, leaderName, sizeof(leaderName));
		menu.SetTitle("选择下一张 Map（已投 %d/%d）\n领先：%s [%d票]", votesCast, eligible, leaderName, highestVotes);
	}

	char firstChapter[MAX_MAP_NAME];
	char displayName[MAX_MAP_NAME];
	char itemText[MAX_MAP_NAME + 32];
	for (int i = 0; i < mapCount; i++)
	{
		g_mapFirstChapters.GetString(i, firstChapter, sizeof(firstChapter));
		g_mapDisplayNames.GetString(i, displayName, sizeof(displayName));
		FormatEx(
			itemText,
			sizeof(itemText),
			StrEqual(g_nextMapVote[client], firstChapter, false) ? "[✓ %d票] %s" : "[%d票] %s",
			counts[i],
			displayName
		);
		menu.AddItem(firstChapter, itemText);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
	g_nextMapMenuShown[client] = true;
}

public int NextMapMenuHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		char firstChapter[MAX_MAP_NAME];
		menu.GetItem(item, firstChapter, sizeof(firstChapter));
		int mapIndex = FindMapIndex(firstChapter);
		if (mapIndex == -1)
		{
			PrintToChat(client, "\x04[下一张图] \x01该 Map 已不可用。");
			return 0;
		}

		strcopy(g_nextMapVote[client], sizeof(g_nextMapVote[]), firstChapter);
		char displayName[MAX_MAP_NAME];
		g_mapDisplayNames.GetString(mapIndex, displayName, sizeof(displayName));
		PrintToChatAll("\x04[下一张图] \x03%N \x01选择了 \x05%s\x01。", client, displayName);

		DataPack pack;
		CreateDataTimer(0.1, Timer_RedisplayNextMap, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(GetMenuSelectionPosition());
	}
	else if (action == MenuAction_Cancel)
	{
		g_nextMapMenuShown[client] = false;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Timer_RedisplayNextMap(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int firstItem = pack.ReadCell();
	if (client > 0)
		ShowNextMapMenu(client, firstItem);
	return Plugin_Stop;
}

int BuildNextMapVoteStats(int[] counts, int &votesCast, int &highestVotes, int &tiedMaps)
{
	votesCast = 0;
	highestVotes = 0;
	tiedMaps = 0;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsEligibleHuman(client) || !g_nextMapVote[client][0])
			continue;

		int mapIndex = FindMapIndex(g_nextMapVote[client]);
		if (mapIndex == -1)
			continue;

		counts[mapIndex]++;
		votesCast++;
	}

	int leader = -1;
	for (int i = 0; i < g_mapMissions.Length; i++)
	{
		if (counts[i] > highestVotes)
		{
			highestVotes = counts[i];
			tiedMaps = 1;
			leader = i;
		}
		else if (counts[i] > 0 && counts[i] == highestVotes)
		{
			tiedMaps++;
		}
	}

	return leader;
}

public Action Timer_ShowFinaleMenus(Handle timer)
{
	if (!IsMissionFinalMap())
		return Plugin_Stop;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsEligibleHuman(client) && !g_nextMapMenuShown[client])
			ShowNextMapMenu(client);
	}

	return Plugin_Stop;
}

public Action Timer_ShowFinaleMenuToClient(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client > 0 && IsMissionFinalMap() && !g_nextMapMenuShown[client])
		ShowNextMapMenu(client);
	return Plugin_Stop;
}

public Action Event_FinaleWin(Event event, const char[] name, bool dontBroadcast)
{
	if (g_finaleChangeScheduled || !IsMissionFinalMap())
		return Plugin_Continue;

	g_finaleChangeScheduled = true;
	int winner = SelectNextMapWinner();
	if (winner == -1)
	{
		LogError("No valid official Map is available for finale fallback");
		return Plugin_Continue;
	}

	char firstChapter[MAX_MAP_NAME];
	char displayName[MAX_MAP_NAME];
	g_mapFirstChapters.GetString(winner, firstChapter, sizeof(firstChapter));
	g_mapDisplayNames.GetString(winner, displayName, sizeof(displayName));

	int[] counts = new int[g_mapMissions.Length];
	int votesCast;
	int highestVotes;
	int tiedMaps;
	BuildNextMapVoteStats(counts, votesCast, highestVotes, tiedMaps);
	if (votesCast > 0)
		PrintToChatAll("\x04[下一张图] \x01投票结果：\x05%s\x01。", displayName);
	else
		PrintToChatAll("\x04[下一张图] \x01无人投票，随机官图：\x05%s\x01。", displayName);

	ScheduleMapChange(firstChapter, displayName, FINALE_CHANGE_DELAY);
	return Plugin_Continue;
}

int SelectNextMapWinner()
{
	int mapCount = g_mapMissions.Length;
	if (!mapCount)
		return -1;

	int[] counts = new int[mapCount];
	int votesCast;
	int highestVotes;
	int tiedMaps;
	BuildNextMapVoteStats(counts, votesCast, highestVotes, tiedMaps);

	if (highestVotes > 0)
	{
		int[] leaders = new int[mapCount];
		int leaderCount;
		for (int i = 0; i < mapCount; i++)
		{
			if (counts[i] == highestVotes)
				leaders[leaderCount++] = i;
		}
		return leaders[GetRandomInt(0, leaderCount - 1)];
	}

	return SelectRandomOfficialMap();
}

int SelectRandomOfficialMap()
{
	int mapCount = g_mapMissions.Length;
	int[] candidates = new int[mapCount];
	int candidateCount;
	MissionSymbol current = CurrentMission;

	for (int i = 0; i < mapCount; i++)
	{
		MissionSymbol mission = view_as<MissionSymbol>(g_mapMissions.Get(i));
		if (g_mapOfficial.Get(i) && mission != current)
			candidates[candidateCount++] = i;
	}

	if (!candidateCount)
	{
		for (int i = 0; i < mapCount; i++)
		{
			if (g_mapOfficial.Get(i))
				candidates[candidateCount++] = i;
		}
	}

	return candidateCount ? candidates[GetRandomInt(0, candidateCount - 1)] : -1;
}

void ScheduleMapChange(const char[] mapName, const char[] displayName, float delay)
{
	DataPack pack;
	CreateDataTimer(delay, Timer_ChangeMap, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteString(mapName);
	pack.WriteString(displayName);
}

public Action Timer_ChangeMap(Handle timer, DataPack pack)
{
	pack.Reset();
	char mapName[MAX_MAP_NAME];
	char displayName[MAX_MAP_NAME];
	pack.ReadString(mapName, sizeof(mapName));
	pack.ReadString(displayName, sizeof(displayName));

	if (!IsMapValid(mapName))
	{
		LogError("Cannot change to invalid Chapter %s (%s)", mapName, displayName);
		PrintToChatAll("\x04[地图] \x01换图失败：目标 Chapter 已不可用。");
		return Plugin_Stop;
	}

	PrintToChatAll("\x04[地图] \x01正在载入 \x05%s\x01……", displayName);
	ForceChangeLevel(mapName, "Campaign Switcher vote");
	return Plugin_Stop;
}

void ResetNextMapVotes()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		g_nextMapVote[client][0] = '\0';
		g_nextMapMenuShown[client] = false;
	}
}

bool IsEligibleHuman(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& GetClientTeam(client) != 1;
}

int CountEligibleHumans()
{
	int count;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsEligibleHuman(client))
			count++;
	}
	return count;
}
