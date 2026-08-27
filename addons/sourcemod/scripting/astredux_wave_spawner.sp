#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <left4dhooks>

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define ZC_WITCH 7
#define ZC_TANK 8

ConVar g_cvWaveSpawnEnabled;
ConVar g_cvSITimer;
ConVar g_cvSILimit;

float g_fSISpawnTime;
int g_iMaxSILimit;
int g_iSpawnedSICount;
int g_iAliveSICount;
bool g_bHasFirstDeath;
float g_fFirstDeathTime;
float g_fBonusSpawnTime;
Handle g_hResetTimer = null;

float g_fPendingSITimer = -1.0;
int g_iPendingSILimit = -1;
Handle g_hVote = null;

public Plugin myinfo =
{
    name = "AstRedux Wave Spawner",
    author = "海洋空氣; AstRedux adaptation by norths7ar",
    description = "Force the Director to spawn bot Special Infected in waves.",
    version = "1.0-redux.1",
    url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

public void OnPluginStart()
{
    g_cvWaveSpawnEnabled = CreateConVar("ast_wave_spawn", "1", "新版特感生成机制开关", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvSITimer = CreateConVar("ast_sitimer_new", "8", "新版波次从第一只特感死亡起计算的刷新时间", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvSILimit = CreateConVar("ast_silimit_new", "3", "新版单波允许生成的特感数量", FCVAR_NOTIFY, true, 0.0, true, 32.0);

    RegConsoleCmd("sm_si", Command_SITimer, "投票修改新版特感波次的刷新时间与数量");
    RegAdminCmd("sm_spawnwave", Command_ForceWave, ADMFLAG_ROOT, "立即开放下一波特感，用于管理员诊断");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);

    g_cvSITimer.AddChangeHook(OnSISettingChanged);
    g_cvSILimit.AddChangeHook(OnSISettingChanged);
    g_cvWaveSpawnEnabled.AddChangeHook(OnWaveModeChanged);

    SyncSettings();
    ResetWaveState(false);
}

public void OnMapStart()
{
    ResetWaveState(false);
}

public void OnConfigsExecuted()
{
    SyncSettings();
    ResetWaveState(true);
}

public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
    ResetWaveState(true);
    return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    SyncSettings();
    ResetWaveState(false);
    return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    ResetWaveState(false);
    return Plugin_Continue;
}

public Action Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (g_cvWaveSpawnEnabled.BoolValue)
    {
        g_iAliveSICount++;
    }
    return Plugin_Continue;
}

// Left4DHooks invokes this only for Director-controlled bot special spawns.
public Action L4D_OnSpawnSpecial(int &zombieClass, const float vecPos[3], const float vecAng[3])
{
    if (!g_cvWaveSpawnEnabled.BoolValue || zombieClass >= ZC_WITCH)
    {
        return Plugin_Continue;
    }

    if (g_iSpawnedSICount >= g_iMaxSILimit)
    {
        return Plugin_Handled;
    }

    g_iSpawnedSICount++;
    g_iAliveSICount++;
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvWaveSpawnEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_INFECTED)
    {
        return Plugin_Continue;
    }

    int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (IsFakeClient(client) && zombieClass < ZC_WITCH)
    {
        g_iAliveSICount = MaxInt(0, g_iAliveSICount - 1);

        float currentTime = GetEngineTime();
        if (!g_bHasFirstDeath)
        {
            g_bHasFirstDeath = true;
            g_fFirstDeathTime = currentTime;
            ScheduleWaveReset(g_fSISpawnTime);
        }
        else if (g_fSISpawnTime > 0.0)
        {
            float elapsed = currentTime - g_fFirstDeathTime;
            float remaining = g_fSISpawnTime - elapsed + g_fBonusSpawnTime;
            float remainingRatio = remaining / g_fSISpawnTime;

            if (remainingRatio <= 0.25)
            {
                g_fBonusSpawnTime += 5.0;
            }
            else if (remainingRatio <= 0.5)
            {
                g_fBonusSpawnTime += 3.0;
            }
            else if (remainingRatio <= 0.8)
            {
                g_fBonusSpawnTime += 2.0;
            }
        }
    }
    else if (zombieClass == ZC_TANK)
    {
        g_iAliveSICount = MaxInt(0, g_iAliveSICount - 1);
        if (g_iMaxSILimit == 1 && g_hResetTimer == null)
        {
            ScheduleWaveReset(g_fSISpawnTime);
        }
    }

    return Plugin_Continue;
}

public Action Timer_ResetWave(Handle timer)
{
    g_hResetTimer = null;

    if (!g_cvWaveSpawnEnabled.BoolValue)
    {
        ResetWaveState(false);
        return Plugin_Stop;
    }

    if (g_fBonusSpawnTime > 0.0)
    {
        float bonusTime = g_fBonusSpawnTime;
        g_fBonusSpawnTime = 0.0;
        ScheduleWaveReset(bonusTime);
        return Plugin_Stop;
    }

    g_iSpawnedSICount = g_iAliveSICount;
    g_bHasFirstDeath = false;
    ResetDirectorSpecialTimers();
    return Plugin_Stop;
}

public void OnSISettingChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    SyncSettings();
}

public void OnWaveModeChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ResetWaveState(convar.BoolValue);
    ServerCommand("sm_reloadscript");
}

public Action Command_ForceWave(int client, int args)
{
    SyncSettings();
    ResetWaveState(true);
    ResetDirectorSpecialTimers();
    ReplyToCommand(client, "[AstRedux] 已立即开放下一波特感。");
    return Plugin_Handled;
}

public Action Command_SITimer(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[AstRedux] !si 只能由游戏内玩家发起。");
        return Plugin_Handled;
    }

    if (!g_cvWaveSpawnEnabled.BoolValue)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01此指令仅支持新版刷特机制。");
        return Plugin_Handled;
    }

    if (args != 2)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01当前刷新速率：\x03%.1f秒%i特", g_cvSITimer.FloatValue, g_cvSILimit.IntValue);
        ReplyToCommand(client, "\x04[AstRedux] \x01使用方法：\x03!si <刷新时间> <特感数量>\x01，例如：\x03!si 7.5 3");
        return Plugin_Handled;
    }

    char timerArg[16];
    char limitArg[16];
    GetCmdArg(1, timerArg, sizeof(timerArg));
    GetCmdArg(2, limitArg, sizeof(limitArg));
    g_fPendingSITimer = StringToFloat(timerArg);
    g_iPendingSILimit = StringToInt(limitArg);

    if (g_fPendingSITimer < 0.0 || g_iPendingSILimit < 0 || g_iPendingSILimit > 32)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01刷新时间必须不小于 0，特感数量必须为 0–32。");
        return Plugin_Handled;
    }

    if (!IsNewBuiltinVoteAllowed())
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01当前无法发起新投票。");
        return Plugin_Handled;
    }

    int players[MAXPLAYERS];
    int playerCount;
    for (int target = 1; target <= MaxClients; target++)
    {
        if (IsClientInGame(target) && !IsFakeClient(target) && GetClientTeam(target) == TEAM_SURVIVORS)
        {
            players[playerCount++] = target;
        }
    }

    if (playerCount == 0)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01没有可参与投票的生还者玩家。");
        return Plugin_Handled;
    }

    char voteText[64];
    Format(voteText, sizeof(voteText), "修改特感刷新速度为 [%.1f秒%i特]", g_fPendingSITimer, g_iPendingSILimit);

    g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
    SetBuiltinVoteResultCallback(g_hVote, SITimerVoteResultHandler);
    SetBuiltinVoteArgument(g_hVote, voteText);
    SetBuiltinVoteInitiator(g_hVote, client);
    DisplayBuiltinVote(g_hVote, players, playerCount, 15);
    FakeClientCommand(client, "Vote Yes");
    return Plugin_Handled;
}

public void SITimerVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
    for (int item = 0; item < numItems; item++)
    {
        if (itemInfo[item][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES && itemInfo[item][BUILTINVOTEINFO_ITEM_VOTES] > numVotes / 2)
        {
            char voteText[64];
            Format(voteText, sizeof(voteText), "修改特感刷新速度为 [%.1f秒%i特]", g_fPendingSITimer, g_iPendingSILimit);
            DisplayBuiltinVotePass(vote, voteText);
            g_cvSITimer.FloatValue = g_fPendingSITimer;
            g_cvSILimit.IntValue = g_iPendingSILimit;
            SyncSettings();
            ServerCommand("sm_reloadscript");
            return;
        }
    }

    g_fPendingSITimer = g_cvSITimer.FloatValue;
    g_iPendingSILimit = g_cvSILimit.IntValue;
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
    if (action == BuiltinVoteAction_End)
    {
        g_hVote = null;
        CloseHandle(vote);
    }
    else if (action == BuiltinVoteAction_Cancel)
    {
        DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
    }
}

void SyncSettings()
{
    g_fSISpawnTime = g_cvSITimer.FloatValue;
    g_iMaxSILimit = g_cvSILimit.IntValue;
}

void ResetWaveState(bool countAlive)
{
    if (g_hResetTimer != null)
    {
        delete g_hResetTimer;
        g_hResetTimer = null;
    }

    g_bHasFirstDeath = false;
    g_fFirstDeathTime = 0.0;
    g_fBonusSpawnTime = 0.0;
    g_iAliveSICount = countAlive ? CountAliveSpecials() : 0;
    g_iSpawnedSICount = g_iAliveSICount;
}

void ScheduleWaveReset(float delay)
{
    if (g_hResetTimer != null)
    {
        delete g_hResetTimer;
    }
    g_hResetTimer = CreateTimer(delay, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
}

int CountAliveSpecials()
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INFECTED)
        {
            continue;
        }

        int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if ((IsFakeClient(client) && zombieClass < ZC_WITCH) || zombieClass == ZC_TANK)
        {
            count++;
        }
    }
    return count;
}

void ResetDirectorSpecialTimers()
{
    int entity = CreateEntityByName("logic_script");
    if (entity == -1)
    {
        LogError("[AstRedux] Failed to create logic_script for Director.ResetSpecialTimers().");
        return;
    }

    DispatchSpawn(entity);
    SetVariantString("Director.ResetSpecialTimers()");
    AcceptEntityInput(entity, "RunScriptCode");
    RemoveEntity(entity);
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client);
}

int MaxInt(int left, int right)
{
    return left > right ? left : right;
}
