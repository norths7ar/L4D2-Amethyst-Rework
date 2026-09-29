#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <player_management>
#include <vote_policy>

native bool Pause_CanCallVote(int client);

#define VOTE_MENU_PATH "configs/vote_menu.txt"

enum VoteKind
{
    Vote_Command,
    Vote_Kick,
    Vote_Spectate
}

Handle g_Vote;
KeyValues g_Menu;
VoteKind g_Kind;
int g_TargetSerial, g_Team, g_Electorate;
bool g_TargetChanged;
int g_VoterSerial[MAXPLAYERS + 1];
int g_Ballot[MAXPLAYERS + 1];
char g_Command[128];

public Plugin myinfo =
{
    name = "服务器投票菜单",
    author = "HazukiYuro, 海洋空氣, Rework contributors",
    description = "Shared vote menu, teammate kick and spectator votes",
    version = "2.0.0",
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    MarkNativeAsOptional("Pause_CanCallVote");
    RegPluginLibrary("server_votes");
    return APLRes_Success;
}

public void OnPluginStart()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), VOTE_MENU_PATH);
    g_Menu = new KeyValues("VoteMenu");
    if (!g_Menu.ImportFromFile(path))
        SetFailState("Cannot load %s", path);

    RegConsoleCmd("sm_vote", Command_Menu);
    RegConsoleCmd("sm_votekick", Command_Kick);
    RegConsoleCmd("sm_votespec", Command_Spectate);
    AddCommandListener(Listener_CallVote, "callvote");
    AddCommandListener(Listener_Ballot, "Vote");
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("round_end", Event_RoundEnd);
}

bool IsParticipant(int client)
{
    return VotePolicy_IsPlayingHuman(client);
}

bool CanInitiate(int client)
{
    if (!IsParticipant(client))
    {
        if (client > 0 && client <= MaxClients && IsClientInGame(client))
            PrintToChat(client, "[投票] 旁观者不能发起投票。");
        return false;
    }
    return true;
}

bool CanStart(int client)
{
    if (!VotePolicy_CheckCaller(client))
        return false;
    if (GetFeatureStatus(FeatureType_Native, "Pause_CanCallVote") == FeatureStatus_Available
        && !Pause_CanCallVote(client))
    {
        PrintToChat(client, "[投票] 刚切换旁观，请稍后再发起投票。");
        return false;
    }
    if (g_Vote != null || IsBuiltinVoteInProgress())
    {
        PrintToChat(client, "[投票] 已有投票正在进行。");
        return false;
    }
    int delay = CheckBuiltinVoteDelay();
    if (delay > 0)
    {
        PrintToChat(client, "[投票] 请等待 %d 秒后再发起投票。", delay);
        return false;
    }
    return true;
}

bool IsProtected(int client)
{
    // Follow effective sm_kick access, including root and admin overrides.
    return CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK);
}

bool CanTarget(int client, int target)
{
    return IsParticipant(target) && target != client
        && GetClientTeam(target) == GetClientTeam(client) && !IsProtected(target);
}

public Action Command_Kick(int client, int args)
{
    ShowTargets(client, Vote_Kick);
    return Plugin_Handled;
}

public Action Command_Spectate(int client, int args)
{
    ShowTargets(client, Vote_Spectate);
    return Plugin_Handled;
}

void ShowTargets(int client, VoteKind kind)
{
    if (!CanInitiate(client))
        return;
    Menu menu = new Menu(TargetMenuHandler);
    menu.SetTitle(kind == Vote_Kick ? "投票踢出队友" : "投票将队友移至旁观");
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!CanTarget(client, target))
            continue;
        char info[32], name[MAX_NAME_LENGTH];
        Format(info, sizeof(info), "%d %d", kind, GetClientSerial(target));
        GetClientName(target, name, sizeof(name));
        menu.AddItem(info, name);
    }
    if (menu.ItemCount == 0)
    {
        delete menu;
        PrintToChat(client, "[投票] 当前没有可选择的队友。");
        return;
    }
    menu.Display(client, kind == Vote_Kick ? 30 : 15);
}

public int TargetMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
        delete menu;
    else if (action == MenuAction_Select)
    {
        char info[32], parts[2][16];
        menu.GetItem(item, info, sizeof(info));
        ExplodeString(info, " ", parts, sizeof(parts), sizeof(parts[]));
        StartPlayerVote(client, GetClientFromSerial(StringToInt(parts[1])), view_as<VoteKind>(StringToInt(parts[0])));
    }
    return 0;
}

public Action Listener_CallVote(int client, const char[] command, int argc)
{
    char issue[32], argument[64];
    GetCmdArg(1, issue, sizeof(issue));
    if (!StrEqual(issue, "Kick", false))
        return Plugin_Continue;
    // Native Kick auto-votes No for the target. Route every kick entry here.
    GetCmdArg(2, argument, sizeof(argument));
    StartPlayerVote(client, GetClientOfUserId(StringToInt(argument)), Vote_Kick);
    return Plugin_Handled;
}

void StartPlayerVote(int client, int target, VoteKind kind)
{
    // Do not mutate a running vote when a stale or concurrent menu is selected.
    if (!CanStart(client))
        return;
    if (!CanTarget(client, target))
    {
        PrintToChat(client, "[投票] 目标已离开、不是可投票的队友，或受管理员保护。");
        return;
    }
    if (kind == Vote_Spectate
        && GetFeatureStatus(FeatureType_Native, "PlayerManagement_MoveToSpectator") != FeatureStatus_Available)
    {
        PrintToChat(client, "[投票] 当前无法执行转旁观。");
        return;
    }
    char text[192];
    Format(text, sizeof(text), kind == Vote_Kick ? "踢出 %N？" : "将 %N 移至旁观？", target);
    g_Kind = kind;
    g_TargetSerial = GetClientSerial(target);
    g_TargetChanged = false;
    g_Team = GetClientTeam(client);
    BeginVote(client, text, kind == Vote_Kick ? 20 : 15);
}

bool BeginVote(int client, const char[] text, int duration)
{
    int clients[MAXPLAYERS + 1];
    g_Electorate = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        g_VoterSerial[i] = 0;
        g_Ballot[i] = -1;
        if (!IsParticipant(i) || (g_Team != 0 && GetClientTeam(i) != g_Team))
            continue;
        clients[g_Electorate++] = i;
        g_VoterSerial[i] = GetClientSerial(i);
    }
    g_Vote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo,
        BuiltinVoteAction_Select | BuiltinVoteAction_Cancel | BuiltinVoteAction_End);
    if (g_Vote == null)
        return false;
    SetBuiltinVoteArgument(g_Vote, text);
    SetBuiltinVoteInitiator(g_Vote, client);
    if (g_Team != 0)
        SetBuiltinVoteTeam(g_Vote, g_Team);
    SetBuiltinVoteResultCallback(g_Vote, VoteResult);
    if (!DisplayBuiltinVote(g_Vote, clients, g_Electorate, duration))
    {
        // A start veto may already have called End and cleared g_Vote.
        delete g_Vote;
        return false;
    }
    PrintToChatAll("[投票] %N 发起：%s", client, text);
    FakeClientCommand(client, "Vote Yes");
    return true;
}

public Action Listener_Ballot(int client, const char[] command, int argc)
{
    if (g_Vote == null)
        return Plugin_Continue;
    if (!IsParticipant(client) || g_VoterSerial[client] != GetClientSerial(client)
        || (g_Team != 0 && GetClientTeam(client) != g_Team))
        return Plugin_Handled;
    return Plugin_Continue;
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
    if (action == BuiltinVoteAction_Select)
    {
        if (IsParticipant(param1) && g_VoterSerial[param1] == GetClientSerial(param1)
            && (g_Team == 0 || GetClientTeam(param1) == g_Team))
            g_Ballot[param1] = param2;
    }
    else if (action == BuiltinVoteAction_Cancel)
        DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Generic);
    else if (action == BuiltinVoteAction_End)
    {
        if (g_Vote == vote)
            g_Vote = null;
        delete vote;
    }
}

public void VoteResult(Handle vote, int numVotes, int numClients, const int[][] clientInfo,
    int numItems, const int[][] itemInfo)
{
    int yes, no;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_Ballot[i] == BUILTINVOTES_VOTE_YES)
            yes++;
        else if (g_Ballot[i] == BUILTINVOTES_VOTE_NO)
            no++;
    }
    // Player votes freeze the denominator: disconnect cannot lower the threshold.
    bool passed = yes * 2 >= g_Electorate && yes > no;
    if (g_Kind == Vote_Command)
    {
        // Keep configured command votes' original extension result-time 60% rule.
        yes = 0;
        for (int i = 0; i < numItems; i++)
            if (itemInfo[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
                yes = itemInfo[i][BUILTINVOTEINFO_ITEM_VOTES];
        passed = yes > 0 && yes * 5 >= numClients * 3;
    }
    if (!passed)
    {
        DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
        return;
    }
    if (g_Kind == Vote_Command)
    {
        DisplayBuiltinVotePass(vote, "正在执行投票选项……");
        ServerCommand("%s", g_Command);
        return;
    }
    int target = GetClientFromSerial(g_TargetSerial);
    if (g_TargetChanged || !IsParticipant(target) || GetClientTeam(target) != g_Team || IsProtected(target))
    {
        ActionFailed(vote, "目标已离开、换队或受管理员保护");
        return;
    }
    char name[MAX_NAME_LENGTH], text[192];
    GetClientName(target, name, sizeof(name));
    if (g_Kind == Vote_Spectate)
    {
        if (GetFeatureStatus(FeatureType_Native, "PlayerManagement_MoveToSpectator") != FeatureStatus_Available
            || !PlayerManagement_MoveToSpectator(target))
        {
            ActionFailed(vote, "目标当前无法转旁观（如正在操控 Tank 或控制其他玩家）");
            return;
        }
        Format(text, sizeof(text), "已将 %s 移至旁观", name);
    }
    else
    {
        KickClientEx(target, "经队友投票踢出");
        Format(text, sizeof(text), "已踢出 %s", name);
    }
    DisplayBuiltinVotePass(vote, text);
}

void ActionFailed(Handle vote, const char[] reason)
{
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Generic);
    PrintToChatAll("[投票] 投票通过，但%s失败：%s。", g_Kind == Vote_Kick ? "踢出" : "转旁观", reason);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (g_Vote == null || event.GetInt("oldteam") == event.GetInt("team"))
        return;
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        if (GetClientSerial(client) == g_TargetSerial)
            g_TargetChanged = true;
        // A player leaving the electorate cannot vote again by rejoining it.
        if (event.GetInt("team") < 2 || (g_Team != 0 && event.GetInt("team") != g_Team))
        {
            g_VoterSerial[client] = 0;
            g_Ballot[client] = -1;
        }
    }
}

public void OnClientDisconnect(int client)
{
    g_VoterSerial[client] = 0;
    g_Ballot[client] = -1;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    CancelOwnVote();
}

public void OnMapEnd()
{
    CancelOwnVote();
}

public void OnPluginEnd()
{
    CancelOwnVote();
}

void CancelOwnVote()
{
    if (g_Vote != null && BuiltinVote_IsVoteInProgress())
        CancelBuiltinVote();
}

public Action Command_Menu(int client, int args)
{
    if (!CanInitiate(client))
        return Plugin_Handled;
    if (args > 0)
    {
        char key[128];
        GetCmdArg(1, key, sizeof(key));
        ActivateItem(client, key);
        return Plugin_Handled;
    }
    Menu menu = new Menu(VoteMenuHandler);
    menu.SetTitle("投票与玩法菜单");
    g_Menu.Rewind();
    if (g_Menu.GotoFirstSubKey())
    {
        do
        {
            char key[128], label[128], type[16];
            g_Menu.GetSectionName(key, sizeof(key));
            g_Menu.GetString("type", type, sizeof(type));
            if (StrEqual(type, "panel") && !PanelAvailable(key))
                continue;
            g_Menu.GetString("label", label, sizeof(label), key);
            menu.AddItem(key, label);
        } while (g_Menu.GotoNextKey());
    }
    menu.Display(client, 20);
    return Plugin_Handled;
}

bool PanelAvailable(const char[] command)
{
    char name[128];
    strcopy(name, sizeof(name), command);
    int space = FindCharInString(name, ' ');
    if (space != -1)
        name[space] = '\0';
    return GetCommandFlags(name) != INVALID_FCVAR_FLAGS;
}

public int VoteMenuHandler(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
        delete menu;
    else if (action == MenuAction_Select)
    {
        char key[128];
        menu.GetItem(item, key, sizeof(key));
        ActivateItem(client, key);
    }
    return 0;
}

void ActivateItem(int client, const char[] key)
{
    if (!CanInitiate(client))
        return;
    g_Menu.Rewind();
    if (!g_Menu.JumpToKey(key))
    {
        PrintToChat(client, "[投票] 该选项已不可用。");
        return;
    }
    char type[16], label[128];
    g_Menu.GetString("type", type, sizeof(type));
    g_Menu.GetString("label", label, sizeof(label), key);
    if (StrEqual(type, "panel") && PanelAvailable(key))
        FakeClientCommand(client, "%s", key);
    else if (StrEqual(type, "command") && CanStart(client))
    {
        g_Kind = Vote_Command;
        g_Team = 0;
        g_TargetSerial = 0;
        strcopy(g_Command, sizeof(g_Command), key);
        BeginVote(client, label, 20);
    }
}
