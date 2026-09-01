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

public Plugin myinfo =
{
    name = "AstRedux Wave Spawner",
    author = "海洋空氣, norths7ar",
    description = "Runs the single wave-based Special Infected spawn model for AstRedux.",
    version = "1.0.0",
    url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

ConVar g_cvDefaultInterval;
ConVar g_cvDefaultSize;
ConVar g_cvInterval;
ConVar g_cvSize;
ConVar g_cvOverrideActive;

float g_fWaveInterval;
int g_iWaveSize;
int g_iSpawnedSICount;
int g_iAliveSICount;
bool g_bHasFirstDeath;
bool g_bWaitingBonus;
float g_fFirstDeathTime;
float g_fBonusSpawnTime;

float g_fPendingInterval = -1.0;
int g_iPendingSize = -1;
Handle g_hVote = INVALID_HANDLE;
Handle g_hWaveTimer;
bool g_bApplyingEffectiveWave;

public void OnPluginStart()
{
    CreateConVar("astredux_wave_version", "1.0.0", "AstRedux Wave Spawner version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvDefaultInterval = CreateConVar("astredux_wave_default_interval", "8.0", "Profile default interval between SI waves.", FCVAR_DONTRECORD, true, 0.0, true, 10000.0);
    g_cvDefaultSize = CreateConVar("astredux_wave_default_size", "3", "Profile default number of SI in each wave.", FCVAR_DONTRECORD, true, 1.0, true, 32.0);
    g_cvInterval = CreateConVar("astredux_wave_interval", "8.0", "Effective interval between SI waves.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvSize = CreateConVar("astredux_wave_size", "3", "Effective number of SI in each wave.", FCVAR_NOTIFY, true, 1.0, true, 32.0);
    g_cvOverrideActive = CreateConVar("astredux_wave_override_active", "0", "Whether effective wave parameters are a player override.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    CreateConVar("astredux_si_hunter_limit", "1", "Hunter limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_smoker_limit", "1", "Smoker limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_boomer_limit", "0", "Boomer limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_spitter_limit", "0", "Spitter limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_jockey_limit", "1", "Jockey limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_charger_limit", "1", "Charger limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("astredux_si_preferred_direction", "4", "Preferred special direction for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);

    RegConsoleCmd("sm_si", Command_WaveOverride, "Adjust AstRedux SI wave interval and size.");
    RegConsoleCmd("sm_spawnwave", Command_ForceWave, "Reset the current AstRedux SI wave.");
    RegServerCmd("sm_astredux_wave_reset_override", Command_ResetWaveOverride, "Clear the active AstRedux wave override.");

    HookEvent("round_end", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
    HookConVarChange(g_cvInterval, OnEffectiveWaveChanged);
    HookConVarChange(g_cvSize, OnEffectiveWaveChanged);

    RefreshEffectiveWave();
}

public void OnConfigsExecuted()
{
    if (!g_cvOverrideActive.BoolValue)
    {
        SetEffectiveWave(g_cvDefaultInterval.FloatValue, g_cvDefaultSize.IntValue);
    }
    ApplyDirectorSettings();
}

public void OnMapEnd()
{
    g_hWaveTimer = null;
    g_hVote = INVALID_HANDLE;
}

public void AstRedux_OnProfileApplied(int profile)
{
    if (!g_cvOverrideActive.BoolValue)
    {
        SetEffectiveWave(g_cvDefaultInterval.FloatValue, g_cvDefaultSize.IntValue);
    }
    else
    {
        RefreshEffectiveWave();
    }
    ApplyDirectorSettings();
}

public void OnEffectiveWaveChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bApplyingEffectiveWave)
    {
        return;
    }

    g_cvOverrideActive.BoolValue = true;
    RefreshEffectiveWave();
    RescheduleActiveWave();
    ApplyDirectorSettings();
}

public void Event_RoundBoundary(Event event, const char[] name, bool dontBroadcast)
{
    delete g_hWaveTimer;
    g_iAliveSICount = 0;
    RefreshEffectiveWave();
    ResetWaveState();
    ResetWaveNow();
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    g_iAliveSICount++;
}

public Action L4D_OnSpawnSpecial(int &zombieClass, const float vecPos[3], const float vecAng[3])
{
    if (zombieClass < ZC_WITCH)
    {
        if (g_iSpawnedSICount >= g_iWaveSize)
        {
            return Plugin_Handled;
        }
        g_iSpawnedSICount++;
        g_iAliveSICount++;
    }
    return Plugin_Continue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != TEAM_INFECTED)
    {
        return;
    }

    int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (event.GetBool("victimisbot") && zombieClass < ZC_WITCH)
    {
        g_iAliveSICount--;
        float now = GetEngineTime();
        if (!g_bHasFirstDeath)
        {
            g_bHasFirstDeath = true;
            g_fFirstDeathTime = now;
            ScheduleWaveReset(g_fWaveInterval);
        }
        else if (g_fWaveInterval > 0.0)
        {
            float remaining = g_fWaveInterval - (now - g_fFirstDeathTime) + g_fBonusSpawnTime;
            float remainingRatio = remaining / g_fWaveInterval;
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
        g_iAliveSICount--;
        if (g_iWaveSize == 1)
        {
            ScheduleWaveReset(g_fWaveInterval);
        }
    }

    if (g_iAliveSICount < 0)
    {
        g_iAliveSICount = 0;
    }
}

public Action Timer_ResetWave(Handle timer)
{
    if (timer != g_hWaveTimer)
    {
        return Plugin_Stop;
    }
    g_hWaveTimer = null;

    if (g_fBonusSpawnTime > 0.0)
    {
        g_bWaitingBonus = true;
        ScheduleWaveReset(g_fBonusSpawnTime);
        g_fBonusSpawnTime = 0.0;
        return Plugin_Handled;
    }

    ResetWaveNow();
    return Plugin_Handled;
}

void ResetWaveNow()
{
    g_iSpawnedSICount = g_iAliveSICount;
    g_bHasFirstDeath = false;
    g_bWaitingBonus = false;

    int entity = CreateEntityByName("logic_script");
    if (entity != -1)
    {
        DispatchSpawn(entity);
        SetVariantString("Director.ResetSpecialTimers()");
        AcceptEntityInput(entity, "RunScriptCode");
        RemoveEdict(entity);
    }
}

public Action Command_ForceWave(int client, int args)
{
    delete g_hWaveTimer;
    g_fBonusSpawnTime = 0.0;
    ResetWaveNow();
    return Plugin_Handled;
}

public Action Command_WaveOverride(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVORS)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01只有生还者可以调整特感刷新参数。");
        return Plugin_Handled;
    }

    if (args != 2)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01当前刷新速率：\x03%.1f秒%d特", g_cvInterval.FloatValue, g_cvSize.IntValue);
        ReplyToCommand(client, "\x04[AstRedux] \x01使用方法：\x03!si <刷新时间> <特感数量>\x01，例如：\x03!si 7.5 3");
        return Plugin_Handled;
    }

    char intervalArgument[16];
    char sizeArgument[16];
    GetCmdArg(1, intervalArgument, sizeof(intervalArgument));
    GetCmdArg(2, sizeArgument, sizeof(sizeArgument));
    if (StringToFloatEx(intervalArgument, g_fPendingInterval) != strlen(intervalArgument)
        || StringToIntEx(sizeArgument, g_iPendingSize) != strlen(sizeArgument)
        || g_fPendingInterval < 0.0 || g_fPendingInterval > 10000.0 || g_iPendingSize < 1 || g_iPendingSize > 32)
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01刷新时间必须为 0–10000 秒，数量必须为 1–32。");
        return Plugin_Handled;
    }

    if (CountHumanSurvivors() <= 1)
    {
        ApplyWaveOverride(g_fPendingInterval, g_iPendingSize);
        PrintToChatAll("\x04[AstRedux] \x01已将特感刷新速度调整为 \x03%.1f秒%d特\x01。", g_fPendingInterval, g_iPendingSize);
        return Plugin_Handled;
    }

    if (!IsNewBuiltinVoteAllowed())
    {
        ReplyToCommand(client, "\x04[AstRedux] \x01当前无法发起新投票。");
        return Plugin_Handled;
    }

    int players[MAXPLAYERS];
    int playerCount;
    for (int index = 1; index <= MaxClients; index++)
    {
        if (IsClientInGame(index) && !IsFakeClient(index) && GetClientTeam(index) == TEAM_SURVIVORS)
        {
            players[playerCount++] = index;
        }
    }

    char voteText[64];
    Format(voteText, sizeof(voteText), "修改特感刷新速度为 [%.1f秒%d特]", g_fPendingInterval, g_iPendingSize);
    g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
    SetBuiltinVoteResultCallback(g_hVote, WaveVoteResultHandler);
    SetBuiltinVoteArgument(g_hVote, voteText);
    SetBuiltinVoteInitiator(g_hVote, client);
    DisplayBuiltinVote(g_hVote, players, playerCount, 15);
    FakeClientCommand(client, "Vote Yes");
    return Plugin_Handled;
}

public void WaveVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
    for (int item = 0; item < numItems; item++)
    {
        if (itemInfo[item][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES && itemInfo[item][BUILTINVOTEINFO_ITEM_VOTES] > (numVotes / 2))
        {
            char voteText[64];
            Format(voteText, sizeof(voteText), "修改特感刷新速度为 [%.1f秒%d特]", g_fPendingInterval, g_iPendingSize);
            DisplayBuiltinVotePass(vote, voteText);
            ApplyWaveOverride(g_fPendingInterval, g_iPendingSize);
            return;
        }
    }
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
    if (action == BuiltinVoteAction_End)
    {
        g_hVote = INVALID_HANDLE;
        CloseHandle(vote);
    }
    else if (action == BuiltinVoteAction_Cancel)
    {
        DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
    }
}

public Action Command_ResetWaveOverride(int args)
{
    g_cvOverrideActive.BoolValue = false;
    SetEffectiveWave(g_cvDefaultInterval.FloatValue, g_cvDefaultSize.IntValue);
    ApplyDirectorSettings();
    return Plugin_Handled;
}

void ApplyWaveOverride(float interval, int size)
{
    g_cvOverrideActive.BoolValue = true;
    SetEffectiveWave(interval, size);
    ApplyDirectorSettings();
}

void SetEffectiveWave(float interval, int size)
{
    g_bApplyingEffectiveWave = true;
    g_cvInterval.FloatValue = interval;
    g_cvSize.IntValue = size;
    g_bApplyingEffectiveWave = false;
    RefreshEffectiveWave();
    RescheduleActiveWave();
}

void RefreshEffectiveWave()
{
    g_fWaveInterval = g_cvInterval.FloatValue;
    g_iWaveSize = g_cvSize.IntValue;
}

void ApplyDirectorSettings()
{
    ServerCommand("sm_reloadscript");
}

void ResetWaveState()
{
    g_iSpawnedSICount = 0;
    g_bHasFirstDeath = false;
    g_bWaitingBonus = false;
    g_fFirstDeathTime = 0.0;
    g_fBonusSpawnTime = 0.0;
}

void ScheduleWaveReset(float delay)
{
    delete g_hWaveTimer;
    g_hWaveTimer = CreateTimer(delay, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
}

void RescheduleActiveWave()
{
    if (!g_bHasFirstDeath || g_bWaitingBonus)
    {
        return;
    }

    float remaining = g_fWaveInterval - (GetEngineTime() - g_fFirstDeathTime);
    ScheduleWaveReset(remaining > 0.0 ? remaining : 0.0);
}

int CountHumanSurvivors()
{
    int humans;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVORS)
        {
            humans++;
        }
    }
    return humans;
}

bool IsValidClient(int client)
{
    return client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client);
}
