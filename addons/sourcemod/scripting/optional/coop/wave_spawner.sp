#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <left4dhooks>
#include <script_reloader>
#undef REQUIRE_PLUGIN
#include <profile_controller>

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3
#define ZC_WITCH 7
#define ZC_TANK 8

public Plugin myinfo =
{
    name = "Coop Wave Spawner",
    author = "海洋空氣, norths7ar",
    description = "Runs the single wave-based Special Infected spawn model for Coop.",
    version = "1.0.0",
    url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

ConVar g_cvInterval;
ConVar g_cvSize;
ConVar g_cvOverrideActive;
ConVar g_cvWaveFields[9];

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
int g_iPendingWaveSlot;
Handle g_hVote = INVALID_HANDLE;
int g_iVoteInitiator;
Handle g_hWaveTimer;
bool g_bApplyingEffectiveWave;
bool g_bProfileApplying;
bool g_bInternalWrite;
float g_fSlotInterval[5];
int g_iSlotSize[5];
int g_iSlotLimits[5][6];
int g_iSlotDirection[5];
int g_iSlotOverrideMask[5];

public void OnPluginStart()
{
    LoadTranslations("wave_spawner.phrases");
    CreateConVar("wave_spawner_version", "1.0.0", "Coop Wave Spawner version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvInterval = CreateConVar("wave_interval", "8.0", "Effective interval between SI waves.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvSize = CreateConVar("wave_size", "3", "Effective number of SI in each wave.", FCVAR_NOTIFY, true, 1.0, true, 32.0);
    g_cvOverrideActive = CreateConVar("wave_override_active", "0", "Whether effective wave parameters are a player override.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvWaveFields[0] = g_cvInterval;
    g_cvWaveFields[1] = g_cvSize;

    CreateConVar("wave_hunter_limit", "1", "Hunter limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_smoker_limit", "1", "Smoker limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_boomer_limit", "0", "Boomer limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_spitter_limit", "0", "Spitter limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_jockey_limit", "1", "Jockey limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_charger_limit", "1", "Charger limit for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);
    CreateConVar("wave_preferred_direction", "4", "Preferred special direction for the Coop VScript.", FCVAR_DONTRECORD, true, 0.0);

    RegConsoleCmd("sm_si", Command_WaveOverride, "Adjust Coop SI wave interval and size.");
    RegConsoleCmd("sm_spawnwave", Command_ForceWave, "Reset the current Coop SI wave.");
    RegServerCmd("sm_wave_reset_override", Command_ResetWaveOverride, "Clear the active Coop wave override.");

    HookEvent("round_end", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundBoundary, EventHookMode_PostNoCopy);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_PostNoCopy);
    g_cvWaveFields[2] = FindConVar("wave_hunter_limit");
    g_cvWaveFields[3] = FindConVar("wave_smoker_limit");
    g_cvWaveFields[4] = FindConVar("wave_boomer_limit");
    g_cvWaveFields[5] = FindConVar("wave_spitter_limit");
    g_cvWaveFields[6] = FindConVar("wave_jockey_limit");
    g_cvWaveFields[7] = FindConVar("wave_charger_limit");
    g_cvWaveFields[8] = FindConVar("wave_preferred_direction");
    for (int field = 0; field < 9; field++) HookConVarChange(g_cvWaveFields[field], OnEffectiveWaveChanged);

    RegPluginLibrary("wave_spawner");
    CreateNative("WaveSpawner_ResetAllOverrides", Native_ResetAllOverrides);
    CreateNative("WaveSpawner_GetCurrentOverrideMask", Native_GetCurrentOverrideMask);

    RefreshEffectiveWave();
}

public void OnConfigsExecuted()
{
    ApplyDirectorSettings();
}

public void OnMapEnd()
{
    g_hWaveTimer = null;
    g_hVote = INVALID_HANDLE;
    g_iVoteInitiator = 0;
}

public void ProfileController_OnProfileApplied(int profile)
{
    g_bProfileApplying = false;
    ApplySlotOrCurrent(profile);
    ApplyDirectorSettings();
}

public void ProfileController_OnProfilePreApply(int profile)
{
    g_bProfileApplying = true;
}

public void OnEffectiveWaveChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bApplyingEffectiveWave || g_bProfileApplying || g_bInternalWrite)
    {
        return;
    }

    int slot = GetCurrentProfile();
    if (slot < 1 || slot > 4) return;
    CaptureField(slot, convar);
    g_cvOverrideActive.BoolValue = g_iSlotOverrideMask[slot] != 0;
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

    if (!IsServerProcessing() || FindEntityByClassname(-1, "worldspawn") == -1)
    {
        return;
    }

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
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveSurvivorsOnly");
        return Plugin_Handled;
    }

    if (args != 2)
    {
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveCurrent", g_cvInterval.FloatValue, g_cvSize.IntValue);
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveUsage");
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
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveInvalidRange");
        return Plugin_Handled;
    }

    if (CountHumanSurvivors() <= 1)
    {
        ApplyWaveOverride(g_fPendingInterval, g_iPendingSize, GetCurrentProfile());
        PrintToChatAll("\x04[%t] \x01%t", "WaveTag", "WaveApplied", g_fPendingInterval, g_iPendingSize);
        return Plugin_Handled;
    }

    if (!IsNewBuiltinVoteAllowed())
    {
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveVoteUnavailable");
        return Plugin_Handled;
    }

    g_iPendingWaveSlot = GetCurrentProfile();

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
    FormatEx(voteText, sizeof(voteText), "%T", "WaveVoteQuestion", client, g_fPendingInterval, g_iPendingSize);
    g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
    g_iVoteInitiator = client;
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
            int languageClient = LANG_SERVER;
            if (g_iVoteInitiator > 0 && g_iVoteInitiator <= MaxClients && IsClientInGame(g_iVoteInitiator)) languageClient = g_iVoteInitiator;
            FormatEx(voteText, sizeof(voteText), "%T", "WaveVotePassed", languageClient, g_fPendingInterval, g_iPendingSize);
            DisplayBuiltinVotePass(vote, voteText);
            ApplyWaveOverride(g_fPendingInterval, g_iPendingSize, g_iPendingWaveSlot);
            g_iPendingWaveSlot = 0;
            return;
        }
    }
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

public void VoteHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
    if (action == BuiltinVoteAction_End)
    {
        g_iPendingWaveSlot = 0;
        g_iVoteInitiator = 0;
        g_hVote = INVALID_HANDLE;
        CloseHandle(vote);
    }
    else if (action == BuiltinVoteAction_Cancel)
    {
        g_iPendingWaveSlot = 0;
        DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
    }
}

public Action Command_ResetWaveOverride(int args)
{
    int slot = GetCurrentProfile();
    if (slot >= 1 && slot <= 4) g_iSlotOverrideMask[slot] = 0;
    g_cvOverrideActive.BoolValue = false;
    RefreshEffectiveWave();
    if (LibraryExists("profile_controller") && GetFeatureStatus(FeatureType_Native, "ProfileController_Reapply") == FeatureStatus_Available)
    {
        ProfileController_Reapply();
    }
    ApplyDirectorSettings();
    return Plugin_Handled;
}

void ApplyWaveOverride(float interval, int size, int slot)
{
	if (slot < 1 || slot > 4) slot = GetCurrentProfile();
    if (slot < 1 || slot > 4) return;
    g_fSlotInterval[slot] = interval;
    g_iSlotSize[slot] = size;
    g_iSlotOverrideMask[slot] |= (1 << 0) | (1 << 1);
    if (slot != GetCurrentProfile()) return;
    g_cvOverrideActive.BoolValue = g_iSlotOverrideMask[slot] != 0;
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

int GetCurrentProfile()
{
    ConVar profile = FindConVar("profile_current");
    return profile == null ? 1 : profile.IntValue;
}

void CaptureField(int slot, ConVar convar)
{
    for (int field = 0; field < 9; field++)
    {
        if (convar != g_cvWaveFields[field]) continue;
        if (field == 0) g_fSlotInterval[slot] = convar.FloatValue;
        else if (field == 1) g_iSlotSize[slot] = convar.IntValue;
        else if (field < 8) g_iSlotLimits[slot][field - 2] = convar.IntValue;
        else g_iSlotDirection[slot] = convar.IntValue;
        g_iSlotOverrideMask[slot] |= (1 << field);
        return;
    }
}

void ApplySlotOrCurrent(int slot)
{
    if (slot < 1 || slot > 4) slot = GetCurrentProfile();
    if (slot < 1 || slot > 4) return;
    if (g_iSlotOverrideMask[slot] != 0)
    {
        g_bInternalWrite = true;
        if (g_iSlotOverrideMask[slot] & (1 << 0)) g_cvWaveFields[0].FloatValue = g_fSlotInterval[slot];
        if (g_iSlotOverrideMask[slot] & (1 << 1)) g_cvWaveFields[1].IntValue = g_iSlotSize[slot];
        for (int field = 2; field < 8; field++) if (g_iSlotOverrideMask[slot] & (1 << field)) g_cvWaveFields[field].IntValue = g_iSlotLimits[slot][field - 2];
        if (g_iSlotOverrideMask[slot] & (1 << 8)) g_cvWaveFields[8].IntValue = g_iSlotDirection[slot];
        g_bInternalWrite = false;
    }
    g_cvOverrideActive.BoolValue = g_iSlotOverrideMask[slot] != 0;
    RefreshEffectiveWave();
}

public int Native_ResetAllOverrides(Handle plugin, int numParams)
{
    for (int slot = 1; slot <= 4; slot++) g_iSlotOverrideMask[slot] = 0;
    g_cvOverrideActive.BoolValue = false;
    return 0;
}

public int Native_GetCurrentOverrideMask(Handle plugin, int numParams)
{
    int slot = GetCurrentProfile();
    return (slot >= 1 && slot <= 4) ? g_iSlotOverrideMask[slot] : 0;
}

void RefreshEffectiveWave()
{
    g_fWaveInterval = g_cvInterval.FloatValue;
    g_iWaveSize = g_cvSize.IntValue;
}

void ApplyDirectorSettings()
{
    if (!VScript_Reload())
    {
        LogError("[Wave] Could not apply Director settings through script_reloader.");
    }
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
