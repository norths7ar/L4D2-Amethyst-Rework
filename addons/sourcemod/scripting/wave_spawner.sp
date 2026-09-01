#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <left4dhooks>

#define TEAM_SPECTATORS         1
#define TEAM_SURVIVORS          2
#define TEAM_INFECTED           3

#define ZC_SMOKER               1
#define ZC_BOOMER               2
#define ZC_HUNTER               3
#define ZC_SPITTER              4
#define ZC_JOCKEY               5
#define ZC_CHARGER              6
#define ZC_WITCH                7
#define ZC_TANK                 8

ConVar g_hWaveSpawnEnabled;
ConVar g_hSITimer;
ConVar g_hSILimit;
ConVar g_hOverrideActive;

float g_fSISpawnTime;
int g_iMaxSILimit;
int g_iSpawnedSICount = 0;
int g_iAliveSICount = 0;
bool g_bHasFirstDeath = false;
float g_fFirstDeathTime = 0.0;
float g_fBonusSpawnTime = 0.0;

float tempSITimerNew = -1.0;
int tempSILimitNew = -1;
int preDifficulty = -1;

Handle g_hVote = INVALID_HANDLE;

public Plugin myinfo =
{
    name            = "Wave Spawner",
    author          = "海洋空氣",
    description     = "Force Director to spawn Special Infected in waves.",
    version         = "1.0-integration",
    url             = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
}

public void OnPluginStart()
{
    g_hWaveSpawnEnabled = CreateConVar("ast_wave_spawn",        "1", "新版特感生成机制开关", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hSITimer = CreateConVar("ast_sitimer_new",                "8", "特感刷新时间（新版，直接刷新控制时间）", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_hSILimit = CreateConVar("ast_silimit_new",                "3", "特感刷新数量（新版，一波特感数量）", FCVAR_NOTIFY, true, 0.0, true, 32.0);
    g_hOverrideActive = CreateConVar("ast_wave_override_active", "0", "当前波次参数是否来自玩家临时调整", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_si", NewSITimerCommand, "新版特感刷新速率调节，无极调节");
    RegConsoleCmd("sm_spawnwave", forceSpawnCommand, "刷新测试");
    RegServerCmd("sm_ast_wave_reset_override", ResetWaveOverrideCommand, "清除玩家临时波次参数记录");

    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
    HookEvent("player_team", OnChangeTeam, EventHookMode_Post);

    g_fSISpawnTime = GetConVarFloat(g_hSITimer);
    g_iMaxSILimit = GetConVarInt(g_hSILimit);
    HookConVarChange(g_hSITimer, OnSIParamChange);
    HookConVarChange(g_hSILimit, OnSIParamChange);
}

public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
    if (!GetConVarBool(g_hWaveSpawnEnabled)) return;

    g_iAliveSICount = 0;
    g_fSISpawnTime = GetConVarFloat(g_hSITimer);
    g_iMaxSILimit = GetConVarInt(g_hSILimit);

    Timer_ResetWave(null);
}

public void Event_TankSpawn(Handle event, const char[] name, bool dontBroadcast)
{
    if (!GetConVarBool(g_hWaveSpawnEnabled)) return;

    // 克局特感 -1
    g_iAliveSICount++;
}

// Only used for bot special spawns (not players)
public Action L4D_OnSpawnSpecial(int &zombieClass, const float vecPos[3], const float vecAng[3])
{
    if (!GetConVarBool(g_hWaveSpawnEnabled)) return Plugin_Continue;

    if (zombieClass < ZC_WITCH) {
        if (g_iSpawnedSICount >= g_iMaxSILimit) { // 超过一波数量
            // 阻止复活
            return Plugin_Handled;
        }
        g_iSpawnedSICount++;
        g_iAliveSICount++;
    }
    return Plugin_Continue;
}

public void Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
    if (!GetConVarBool(g_hWaveSpawnEnabled)) return;

    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    bool isBot = GetEventBool(event, "victimisbot");
    if (!isClientValid(client)) return;

    int team = GetClientTeam(client);
    if (team != TEAM_INFECTED) return;

    int zombieClass = GetZombieClass(client);

    if (isBot && zombieClass < ZC_WITCH ) {
        g_iAliveSICount--;

        float time = GetEngineTime();
        // 如果是第一只死的
        if (!g_bHasFirstDeath) {
            g_bHasFirstDeath = true;
            g_fFirstDeathTime = time;

            // 计时重置波次
            // 轨迹注：CreateTimer 的第三参数是 data，TIMER_FLAG_NO_MAPCHANGE 应放在第四参数。
            CreateTimer(g_fSISpawnTime, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
        } else { // 后面死的
            // 减去第一只死的时间，计算还有多久下一波
            float interval = time - g_fFirstDeathTime;
            // 剩余复活时间 = 设定复活时间 - 当前时间 + 奖励时间
            float remainTime = g_fSISpawnTime - interval + g_fBonusSpawnTime;
            float timeDiv = remainTime / g_fSISpawnTime;

            // 分段发放奖励时间，理论上特感越多，奖励时间就越长
            if (timeDiv <= 0.25) {
                g_fBonusSpawnTime += 5.0;
            } else if (timeDiv <= 0.5) {
                g_fBonusSpawnTime += 3.0;
            } else if (timeDiv <= 0.8) {
                g_fBonusSpawnTime += 2.0;
            }
        }
    } else if (zombieClass == ZC_TANK) {
        g_iAliveSICount--;
        if (g_iMaxSILimit == 1) {
            // 当特感数为 1 的时候，Tank 死后要触发波数重置
            CreateTimer(g_fSISpawnTime, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
        }
    }

    if (g_iAliveSICount < 0) {
        // 小于 0 情况：玩家特感复活后跑路
        g_iAliveSICount = 0;
    }
}

public Action Timer_ResetWave(Handle timer)
{
    if (g_fBonusSpawnTime > 0.0) {
        // 等待奖励时间
        // PrintToChatAll("Bonus Time: %.1f", g_fBonusSpawnTime);
        CreateTimer(g_fBonusSpawnTime, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
        g_fBonusSpawnTime = 0.0;
    } else {
        // 记录存活的特感数量
        g_iSpawnedSICount = g_iAliveSICount;
        g_bHasFirstDeath = false;
        // 强制刷新
        // Director.ResetSpecialTimers();
        int entity = CreateEntityByName("logic_script");
        if( entity != -1 )
        {
            DispatchSpawn(entity);
            SetVariantString("Director.ResetSpecialTimers()");
            AcceptEntityInput(entity, "RunScriptCode");
            RemoveEdict(entity);
        }
    }
    return Plugin_Handled;
}

public void OnSIParamChange(ConVar convar, const char[] oldvalue, const char[] newvalue)
{
    g_fSISpawnTime = GetConVarFloat(g_hSITimer);
    g_iMaxSILimit = GetConVarInt(g_hSILimit);

    ServerCommand("sm_reloadscript");
}

public Action forceSpawnCommand(int client, int args) {
    Timer_ResetWave(null);
    return Plugin_Handled;
}

public Action NewSITimerCommand(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS) {
        ReplyToCommand(client, "\x04[AstMod] \x01只有生还者可以调整特感刷新参数。");
        return Plugin_Handled;
    }

    if ( !GetConVarBool(g_hWaveSpawnEnabled) ) {
        ReplyToCommand(client, "\x04[AstMod] \x01此指令仅支持新版刷特机制！");
        return Plugin_Handled;
    }

    if( args != 2 )
    {
        // 获取当前设定值
        float fTimerCurrent = GetConVarFloat(g_hSITimer);
        int iLimitCurrent = GetConVarInt(g_hSILimit);
        ReplyToCommand(client, "\x04[AstMod] \x01当前刷新速率：\x03%.1f秒%i特", fTimerCurrent, iLimitCurrent);
        ReplyToCommand(client, "\x04[AstMod] \x01使用方法: \x3!si <刷新时间> <特感数量>\x01，如：\x03!si 7.5 3");
        return Plugin_Handled;
    }

    // 发起投票修改
    char sSITimerNew[8];
    char sSILimitNew[8];
    GetCmdArg(1, sSITimerNew, sizeof(sSITimerNew));
    GetCmdArg(2, sSILimitNew, sizeof(sSILimitNew));
    tempSITimerNew = StringToFloat(sSITimerNew);
    tempSILimitNew = StringToInt(sSILimitNew);

    // 轨迹注：单人生还者直接应用调整；多人时保留海洋原有的投票流程。
    if (CountHumanSurvivors() <= 1) {
        ApplyWaveOverride(tempSITimerNew, tempSILimitNew);
        PrintToChatAll("\x04[AstMod] \x01已将特感刷新速度调整为 \x03%.1f秒%i特\x01。", tempSITimerNew, tempSILimitNew);
        return Plugin_Handled;
    }

    // Call Vote
    if ( IsNewBuiltinVoteAllowed() ) {
        int iNumPlayers;
        int iPlayers[MAXPLAYERS];
        for (int i = 1; i <= MaxClients; i++) {
            if (!IsClientInGame(i) || IsFakeClient(i) || (GetClientTeam(i) != TEAM_SURVIVORS)) {
                continue;
            }
            iPlayers[iNumPlayers++] = i;
        }

        char sBuffer[64];
        g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);

        Format(sBuffer, sizeof(sBuffer), "修改特感刷新速度为 [%.1f秒%i特]", tempSITimerNew, tempSILimitNew);
        SetBuiltinVoteResultCallback(g_hVote, SITimerNewVoteResultHandler);

        SetBuiltinVoteArgument(g_hVote, sBuffer);
        SetBuiltinVoteInitiator(g_hVote, client);
        DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, 15);
        FakeClientCommand(client, "Vote Yes");
    }

    return Plugin_Handled;
}


public void SITimerNewVoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
    for (int i = 0; i < num_items; i++) {
        if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES) {
            if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_votes / 2)) {
                char sBuffer[64];
                Format(sBuffer, sizeof(sBuffer), "修改特感刷新速度为 [%.1f秒%i特]", tempSITimerNew, tempSILimitNew);
                DisplayBuiltinVotePass(vote, sBuffer);
                ApplyWaveOverride(tempSITimerNew, tempSILimitNew);
                return;
            }
        }
    }
    tempSITimerNew = GetConVarFloat(g_hSITimer);
    tempSILimitNew = GetConVarInt(g_hSILimit);
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
    return;
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
    switch (action) {
        case BuiltinVoteAction_End: {
            g_hVote = INVALID_HANDLE;
            CloseHandle(vote);
            return;
        }
        case BuiltinVoteAction_Cancel: {
            DisplayBuiltinVoteFail( vote, view_as<BuiltinVoteFailReason>(param1) );
            return;
        }
    }
    return;
}

// 延迟设置 cvar，覆盖 cfg 设置
public Action OnChangeTeam(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    int newteam = GetEventInt(event, "team");
    int oldteam = GetEventInt(event, "oldteam");
    // 轨迹注：人类加入或离开生还者队伍也可能改变 DAS/profile，不能只监听 BOT 换队。
    if (client > 0 && IsClientInGame(client)
    && (newteam == TEAM_SURVIVORS || oldteam == TEAM_SURVIVORS)) {
        CreateTimer(1.0, Timer_RewriteCfgConVar, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Continue;
}

public Action Timer_RewriteCfgConVar(Handle timer)
{
    if (!g_hOverrideActive.BoolValue) return Plugin_Handled;

    // 对比投票成功时的人数，如果相同则恢复投票时的设定，缺点是只保存一次记录
    // 轨迹注：难度标记变化后清除临时覆盖，避免把旧人数档位的参数带入新档位。
    int curDifficulty = GetCurrentDifficultyMarker();
    if (curDifficulty != preDifficulty) {
        ClearWaveOverride();
        return Plugin_Handled;
    }

    if (tempSITimerNew != -1) {
        SetConVarFloat(g_hSITimer, tempSITimerNew);
    }
    if (tempSILimitNew != -1) {
        SetConVarInt(g_hSILimit, tempSILimitNew);
    }
    return Plugin_Continue;
}

public void OnConfigsExecuted()
{
    // 轨迹注：换图重新执行 cfg 后，仅在人数档位未变化时恢复玩家本次会话的临时设置。
    if (g_hOverrideActive.BoolValue) {
        CreateTimer(0.5, Timer_RewriteCfgConVar, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action ResetWaveOverrideCommand(int args)
{
    // 轨迹注：供空服重置流程清除前一批玩家留下的临时波次参数。
    ClearWaveOverride();
    return Plugin_Handled;
}

void ApplyWaveOverride(float interval, int limit)
{
    SetConVarFloat(g_hSITimer, interval);
    SetConVarInt(g_hSILimit, limit);
    tempSITimerNew = interval;
    tempSILimitNew = limit;
    preDifficulty = GetCurrentDifficultyMarker();
    g_hOverrideActive.BoolValue = true;
}

void ClearWaveOverride()
{
    tempSITimerNew = -1.0;
    tempSILimitNew = -1;
    preDifficulty = -1;
    g_hOverrideActive.BoolValue = false;
}

int GetCurrentDifficultyMarker()
{
    // 轨迹注：Baseline 使用 DAS 难度，Redux scaffold 使用独立 profile；两者共用覆盖生命周期。
    ConVar difficulty = FindConVar("das_fakedifficulty");
    if (difficulty == null) {
        difficulty = FindConVar("astredux_profile_current");
    }
    return difficulty == null ? -1 : difficulty.IntValue;
}

int CountHumanSurvivors()
{
    int humans;
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS) {
            humans++;
        }
    }
    return humans;
}


// UTILS

bool isClientValid(int client)
{
    if (client <= 0 || client > MaxClients) return false;
    if (!IsClientConnected(client)) return false;
    if (!IsClientInGame(client)) return false;
    return true;
}

int GetZombieClass(int client) {
	return GetEntProp(client, Prop_Send, "m_zombieClass");
}
