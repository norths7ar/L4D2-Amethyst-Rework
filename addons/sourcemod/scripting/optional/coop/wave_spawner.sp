#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <vote_policy>
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
    version = "1.1.0",
    url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

ConVar g_cvInterval;
ConVar g_cvSize;
ConVar g_cvOverrideActive;
ConVar g_cvWaveFields[9];

// Current snapshot: only first successful spawn (or round initialization)
// writes these. Death handling must never read the mutable settings CVars.
float g_fWaveInterval;
int g_iWaveSize;
// Prepared settings may change until the first successful spawn. The current
// wave snapshot above remains the owner of death timing until then.
float g_fPreparedInterval;
int g_iPreparedSize;
bool g_bWaveStarted;
int g_iSpawnedSICount;
int g_iAliveSICount;
bool g_bHasFirstDeath;
bool g_bWaveSettingsPending;
bool g_bMapReady;
bool g_bRoundEnded;
float g_fFirstDeathTime;
float g_fDeathInterval;
float g_fBonusSpawnTime;

float g_fVoteInterval = -1.0;
int g_iVoteSize = -1;
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

// Small waves rotate the base pool, not the VScript's random extra slots.
// Living bots occupy pool slots outside this FIFO; duplicate classes are
// separate entries. Settings are updated only with the prepared wave.
ArrayList g_RotationQueue;
bool g_bRotation;
int g_iRotationLimits[ZC_WITCH];

public void OnPluginStart()
{
    LoadTranslations("wave_spawner.phrases");
    CreateConVar("wave_spawner_version", "1.1.0", "Coop Wave Spawner version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_RotationQueue = new ArrayList();
    g_cvInterval = CreateConVar("wave_interval", "8.0", "Interval selected for the next SI wave; running timers keep their snapshot.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
    g_cvSize = CreateConVar("wave_size", "3", "Size selected for the next SI wave; a spawning wave keeps its snapshot.", FCVAR_NOTIFY, true, 1.0, true, 32.0);
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
    RegAdminCmd("sm_spawnwave", Command_ForceWave, ADMFLAG_GENERIC, "Reset the current Coop SI wave.");
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

}

public void OnConfigsExecuted()
{
    g_bMapReady = true;
    g_bWaveSettingsPending = true;
    // round_start can precede SourceMod's map-ready boundary. Initialize here
    // as well so the first round and late plugin loads do not miss their reset.
    ResetWaveNow();
}

public void OnMapStart()
{
    g_bMapReady = false;
    g_bRoundEnded = false;
    g_bRotation = false;
    g_RotationQueue.Clear();
}

public void OnMapEnd()
{
    g_bMapReady = false;
    g_hWaveTimer = null;
    g_hVote = INVALID_HANDLE;
    g_iVoteInitiator = 0;
}

public void ProfileController_OnProfileApplied(int profile)
{
    g_bProfileApplying = false;
    ApplySlotOrCurrent(profile);
    MarkWaveSettingsPending();
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
    MarkWaveSettingsPending();
}

void MarkWaveSettingsPending()
{
    g_bWaveSettingsPending = true;
    PrepareWaveSettings();
}

void PrepareWaveSettings()
{
    // Settings writes never reopen a running wave or alter its timer/counters.
    if (!g_bMapReady || g_bRoundEnded || g_bWaveStarted || !g_bWaveSettingsPending) return;
    if (!ApplyDirectorSettings()) return;
    g_fPreparedInterval = g_cvInterval.FloatValue;
    g_iPreparedSize = g_cvSize.IntValue;
    PrepareRotation();
    g_bWaveSettingsPending = false;
}

void CountRotationAlive(int counts[ZC_WITCH], int skipClient = 0)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client == skipClient || !IsClientInGame(client) || !IsFakeClient(client)
            || !IsPlayerAlive(client) || GetClientTeam(client) != TEAM_INFECTED) continue;
        int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if (zombieClass > 0 && zombieClass < ZC_WITCH) counts[zombieClass]++;
    }
}

void PrepareRotation()
{
    // CVar order differs from the engine's Smoker/Boomer/Hunter/... IDs.
    static const int classes[] = {3, 1, 2, 4, 5, 6};
    int total;
    for (int i = 0; i < sizeof(classes); i++)
    {
        g_iRotationLimits[classes[i]] = g_cvWaveFields[i + 2].IntValue;
        total += g_iRotationLimits[classes[i]];
    }
    g_bRotation = g_iPreparedSize < total;
    if (!g_bRotation) g_RotationQueue.Clear();
    else ReconcileRotation();
}

void ReconcileRotation()
{
    int occupied[ZC_WITCH];
    CountRotationAlive(occupied);
    // Keep the oldest valid entries when limits shrink. Live bots are never
    // removed, including extra classes carried over from a larger wave.
    for (int i = 0; i < g_RotationQueue.Length;)
    {
        int zombieClass = g_RotationQueue.Get(i);
        if (occupied[zombieClass] >= g_iRotationLimits[zombieClass]) g_RotationQueue.Erase(i);
        else
        {
            occupied[zombieClass]++;
            i++;
        }
    }
    int firstNew = g_RotationQueue.Length;
    for (int zombieClass = 1; zombieClass < ZC_WITCH; zombieClass++)
        for (int count = occupied[zombieClass]; count < g_iRotationLimits[zombieClass]; count++)
            g_RotationQueue.Push(zombieClass);
    // Randomize only new slots (initial pool, increased limits, missing bots),
    // never the existing death order. This also recovers non-death removals.
    for (int i = g_RotationQueue.Length - 1; i > firstNew; i--)
    {
        int other = GetRandomInt(firstNew, i);
        int zombieClass = g_RotationQueue.Get(i);
        g_RotationQueue.Set(i, g_RotationQueue.Get(other));
        g_RotationQueue.Set(other, zombieClass);
    }
}

void ReturnRotationClass(int zombieClass, int deadClient)
{
    if (!g_bRotation || zombieClass <= 0 || zombieClass >= ZC_WITCH) return;
    int occupied[ZC_WITCH];
    CountRotationAlive(occupied, deadClient);
    for (int i = 0; i < g_RotationQueue.Length; i++) occupied[g_RotationQueue.Get(i)]++;
    // Do not turn surplus survivors from a previous large wave into pool slots.
    if (occupied[zombieClass] < g_iRotationLimits[zombieClass]) g_RotationQueue.Push(zombieClass);
}

public void Event_RoundBoundary(Event event, const char[] name, bool dontBroadcast)
{
    g_bRoundEnded = StrEqual(name, "round_end");
    delete g_hWaveTimer;
    g_iAliveSICount = 0;
    ResetWaveState();
    // round_end may run during map teardown; only a new round needs a wave.
    if (StrEqual(name, "round_start")) ResetWaveNow();
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    g_iAliveSICount++;
}

public Action L4D_OnSpawnSpecial(int &zombieClass, const float vecPos[3], const float vecAng[3])
{
    if (zombieClass < ZC_WITCH)
    {
        if (!g_bMapReady || g_bRoundEnded) return Plugin_Handled;
        if (!g_bWaveStarted && g_bWaveSettingsPending)
        {
            // The Director has already selected a class at this hook. If its
            // settings were not ready, prepare outside the spawn call and let
            // it select again instead of mixing two settings in the first SI.
            RequestFrame(PrepareWaveNextFrame);
            return Plugin_Handled;
        }
        int size = g_bWaveStarted ? g_iWaveSize : g_iPreparedSize;
        if (g_iSpawnedSICount >= size)
        {
            return Plugin_Handled;
        }
        if (g_bRotation)
        {
            ReconcileRotation();
            if (!g_RotationQueue.Length) return Plugin_Handled;
            zombieClass = g_RotationQueue.Get(0);
            // Peek only. A blocked/failed spawn must not consume its turn.
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}

void PrepareWaveNextFrame(any data)
{
    PrepareWaveSettings();
}

public void L4D_OnSpawnSpecial_Post(int client, int zombieClass, const float vecPos[3], const float vecAng[3])
{
    if (client <= 0 || zombieClass >= ZC_WITCH || !g_bMapReady || g_bRoundEnded) return;
    if (g_bRotation)
    {
        // Account for the actual class if another spawn hook changed it.
        int actualClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        int index = g_RotationQueue.FindValue(actualClass);
        if (index != -1) g_RotationQueue.Erase(index);
    }
    if (!g_bWaveStarted)
    {
        g_fWaveInterval = g_fPreparedInterval;
        g_iWaveSize = g_iPreparedSize;
        g_bWaveStarted = true;
    }
    g_iSpawnedSICount++;
    g_iAliveSICount++;
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
        if (!g_bRoundEnded) ReturnRotationClass(zombieClass, client);
        g_iAliveSICount--;
        float now = GetEngineTime();
        if (!g_bHasFirstDeath)
        {
            g_bHasFirstDeath = true;
            // Tank recovery may already own a countdown for this waiting
            // wave. Its start time and interval must remain unchanged.
            if (g_hWaveTimer == null) StartWaveCountdown(g_fWaveInterval);
        }
        else if (g_fDeathInterval > 0.0)
        {
            float remaining = g_fDeathInterval - (now - g_fFirstDeathTime) + g_fBonusSpawnTime;
            float remainingRatio = remaining / g_fDeathInterval;
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
    }

    if (g_iAliveSICount < 0)
    {
        g_iAliveSICount = 0;
    }
    EnsureWaveProgress(client);
}

void EnsureWaveProgress(int deadClient)
{
    if (!g_bMapReady || g_bRoundEnded || g_hWaveTimer != null) return;
    if (!g_bWaveStarted && g_bWaveSettingsPending) return;
    int size = g_bWaveStarted ? g_iWaveSize : g_iPreparedSize;
    if (g_iSpawnedSICount < size) return; // The Director can still fill this wave.

    // Quota includes survivors of the previous wave, while deaths deliberately
    // do not refund it. If no ordinary SI remains to start a death countdown,
    // this blocked quota needs a next-wave timer, regardless of Tank count.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client == deadClient || !IsClientInGame(client) || !IsPlayerAlive(client)
            || GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client)) continue;
        int zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if (zombieClass > 0 && zombieClass < ZC_WITCH) return;
    }
    StartWaveCountdown(g_bWaveStarted ? g_fWaveInterval : g_fPreparedInterval);
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
    g_bWaveStarted = false;

    if (!g_bMapReady)
    {
        return;
    }

    PrepareWaveSettings();

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
    float interval;
    int size;
    GetCmdArg(1, intervalArgument, sizeof(intervalArgument));
    GetCmdArg(2, sizeArgument, sizeof(sizeArgument));
    if (StringToFloatEx(intervalArgument, interval) != strlen(intervalArgument)
        || StringToIntEx(sizeArgument, size) != strlen(sizeArgument)
        || interval < 0.0 || interval > 10000.0 || size < 1 || size > 32)
    {
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveInvalidRange");
        return Plugin_Handled;
    }

    if (CountHumanSurvivors() <= 1)
    {
        ApplyWaveOverride(interval, size, GetCurrentProfile());
        PrintToChatAll("\x04[%t] \x01%t", "WaveTag", "WaveApplied", interval, size);
        return Plugin_Handled;
    }

    if (g_hVote != INVALID_HANDLE || !IsNewBuiltinVoteAllowed())
    {
        ReplyToCommand(client, "\x04[%t] \x01%t", "WaveTag", "WaveVoteUnavailable");
        return Plugin_Handled;
    }

    if (!VotePolicy_CheckCaller(client)) return Plugin_Handled;

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
    FormatEx(voteText, sizeof(voteText), "%T", "WaveVoteQuestion", client, interval, size);
    g_hVote = CreateBuiltinVote(VoteHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
    if (g_hVote == null) return Plugin_Handled;
    SetBuiltinVoteResultCallback(g_hVote, WaveVoteResultHandler);
    SetBuiltinVoteArgument(g_hVote, voteText);
    SetBuiltinVoteInitiator(g_hVote, client);
    if (!DisplayBuiltinVote(g_hVote, players, playerCount, 15))
    {
        // A start veto may already have ended and destroyed the vote.
        if (IsValidHandle(g_hVote)) delete g_hVote;
        return Plugin_Handled;
    }
    // Only an accepted vote owns these values. Parsing another command, even
    // a rejected command or a solo direct change, cannot mutate this proposal.
    g_fVoteInterval = interval;
    g_iVoteSize = size;
    g_iPendingWaveSlot = GetCurrentProfile();
    g_iVoteInitiator = client;
    FakeClientCommand(client, "Vote Yes");
    return Plugin_Handled;
}

public void WaveVoteResultHandler(Handle vote, int numVotes, int numClients, const int[][] clientInfo, int numItems, const int[][] itemInfo)
{
    if (vote != g_hVote) return;
    for (int item = 0; item < numItems; item++)
    {
        if (itemInfo[item][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES && itemInfo[item][BUILTINVOTEINFO_ITEM_VOTES] > (numVotes / 2))
        {
            char voteText[64];
            int languageClient = LANG_SERVER;
            if (g_iVoteInitiator > 0 && g_iVoteInitiator <= MaxClients && IsClientInGame(g_iVoteInitiator)) languageClient = g_iVoteInitiator;
            FormatEx(voteText, sizeof(voteText), "%T", "WaveVotePassed", languageClient, g_fVoteInterval, g_iVoteSize);
            DisplayBuiltinVotePass(vote, voteText);
            ApplyWaveOverride(g_fVoteInterval, g_iVoteSize, g_iPendingWaveSlot);
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
        if (vote == g_hVote)
        {
            g_iPendingWaveSlot = 0;
            g_iVoteInitiator = 0;
            g_hVote = INVALID_HANDLE;
        }
        CloseHandle(vote);
    }
    else if (action == BuiltinVoteAction_Cancel && vote == g_hVote)
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
    if (LibraryExists("profile_controller") && GetFeatureStatus(FeatureType_Native, "ProfileController_Reapply") == FeatureStatus_Available)
    {
        ProfileController_Reapply();
    }
    MarkWaveSettingsPending();
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
}

void SetEffectiveWave(float interval, int size)
{
    g_bApplyingEffectiveWave = true;
    g_cvInterval.FloatValue = interval;
    g_cvSize.IntValue = size;
    g_bApplyingEffectiveWave = false;
    MarkWaveSettingsPending();
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

bool ApplyDirectorSettings()
{
    // A late load can receive OnConfigsExecuted before Confogl assigns the
    // mode's script filename. Keep this request pending until it is configured.
    char filename[PLATFORM_MAX_PATH];
    FindConVar("sm_vscript_filename").GetString(filename, sizeof(filename));
    if (!filename[0]) return false;
    // Publish a separate script snapshot: reloading astredux.nut must not read
    // next-wave CVars into a wave which has already started spawning.
    int entity = CreateEntityByName("logic_script");
    if (entity == -1) return false;
    DispatchSpawn(entity);
    char code[512];
    FormatEx(code, sizeof(code), "::WaveSpawnSettings <- { size = %d, limits = [%d,%d,%d,%d,%d,%d], direction = %d, resolved = false };",
        g_cvSize.IntValue, g_cvWaveFields[2].IntValue, g_cvWaveFields[3].IntValue,
        g_cvWaveFields[4].IntValue, g_cvWaveFields[5].IntValue, g_cvWaveFields[6].IntValue,
        g_cvWaveFields[7].IntValue, g_cvWaveFields[8].IntValue);
    SetVariantString(code);
    bool published = AcceptEntityInput(entity, "RunScriptCode");
    RemoveEdict(entity);
    if (!published) return false;
    if (!VScript_Reload())
    {
        LogError("[Wave] Could not apply Director settings through script_reloader.");
        return false;
    }
    return true;
}

void ResetWaveState()
{
    g_bRotation = false;
    g_RotationQueue.Clear();
    g_bWaveStarted = false;
    g_bWaveSettingsPending = true;
    g_fWaveInterval = g_cvInterval.FloatValue;
    g_iWaveSize = g_cvSize.IntValue;
    g_iSpawnedSICount = 0;
    g_bHasFirstDeath = false;
    g_fFirstDeathTime = 0.0;
    g_fDeathInterval = 0.0;
    g_fBonusSpawnTime = 0.0;
}

void StartWaveCountdown(float interval)
{
    g_fFirstDeathTime = GetEngineTime();
    g_fDeathInterval = interval;
    ScheduleWaveReset(interval);
}

void ScheduleWaveReset(float delay)
{
    delete g_hWaveTimer;
    g_hWaveTimer = CreateTimer(delay, Timer_ResetWave, _, TIMER_FLAG_NO_MAPCHANGE);
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
