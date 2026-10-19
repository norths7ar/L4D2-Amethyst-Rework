#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#define AIDIAG_IMPLEMENTATION
#include <ai_diagnostics>
#include <anne_nextbot>
#undef REQUIRE_EXTENSIONS
#include <actions>

// Observation only: no CommandABot, movement writes, path consumer ownership or
// scheduler configuration. ai_tank alone owns the Tank path consumer bit.
public Plugin myinfo = {
    name = "AI Diagnostics", author = "AstRedux",
    description = "Automatic complete Tank/SI sessions with bounded asynchronous logging",
    version = AIDIAG_VERSION
};

#define QUEUE_SIZE 2048
#define LINE_SIZE 768
#define CONTROL_RESERVE 96
#define FLUSH_LINES 64
#define FILE_SLOTS 512
#define DIRECTORY_STEPS 16
#define OWNER_SLOTS 8
#define OWNER_LENGTH 48
#define PATH_NODES 8
#define SERVICE_INTERVAL 0.2
#define MIB 1048576

ConVar g_enable, g_fileMB, g_totalMB;
bool g_running, g_mapLive, g_actions, g_paths, g_boundaryPending;
bool g_featuresReady, g_featuresReported;
char g_missingActions[256];
int g_actionHooks, g_actionCallbacks;
char g_pendingPrefix[160], g_pendingMeta[384], g_inventoryName[PLATFORM_MAX_PATH];
char g_queue[QUEUE_SIZE][LINE_SIZE];
bool g_boundary[QUEUE_SIZE];
int g_head, g_count, g_peak, g_dropped, g_truncated, g_throttled;
int g_ioErrors, g_ownerDrops, g_written, g_deleted, g_uncertainWrites;
int g_unflushed;
int g_reportedDrops, g_reportedTruncated, g_reportedOwnerDrops, g_reportedIO;
float g_captureMS, g_flushMS, g_flushMaxMS;
float g_lastFrame, g_frameSum, g_frameMax;
int g_frames, g_slowFrames;
float g_nextSummary, g_nextRetry;
float g_inventoryRetry;

char g_directory[PLATFORM_MAX_PATH], g_prefix[160], g_currentPath[PLATFORM_MAX_PATH];
File g_file;
DirectoryListing g_inventory;
bool g_storageReady;
char g_files[FILE_SLOTS][PLATFORM_MAX_PATH];
int g_sizes[FILE_SLOTS], g_times[FILE_SLOTS], g_currentFile = -1;
int g_diskBytes;
int g_part, g_mapSerial, g_sessionSerial, g_doorCursor = 1;

int g_session[MAXPLAYERS + 1], g_class[MAXPLAYERS + 1], g_target[MAXPLAYERS + 1];
int g_observedVictim[MAXPLAYERS + 1], g_birthTick[MAXPLAYERS + 1];
bool g_hasCommandTarget[MAXPLAYERS + 1];
int g_sequence[MAXPLAYERS + 1], g_moveType[MAXPLAYERS + 1], g_flags[MAXPLAYERS + 1];
char g_action[MAXPLAYERS + 1][64];
float g_started[MAXPLAYERS + 1], g_nextPath[MAXPLAYERS + 1];
float g_rawVel[MAXPLAYERS + 1][3];
int g_rawButtons[MAXPLAYERS + 1];
char g_owners[MAXPLAYERS + 1][OWNER_SLOTS][OWNER_LENGTH];
bool g_ownerUsed[MAXPLAYERS + 1][OWNER_SLOTS];
float g_nextCommand[MAXPLAYERS + 1][OWNER_SLOTS];
float g_lastPos[MAXPLAYERS + 1][3], g_anchor[MAXPLAYERS + 1][3];
float g_windowPos[MAXPLAYERS + 1][3], g_climbPos[MAXPLAYERS + 1][3];
float g_stillSince[MAXPLAYERS + 1], g_windowSince[MAXPLAYERS + 1], g_walked[MAXPLAYERS + 1];
bool g_stalled[MAXPLAYERS + 1];
float g_climbSince[MAXPLAYERS + 1];
int g_climbs[MAXPLAYERS + 1];
int g_door[MAXPLAYERS + 1];
float g_doorSince[MAXPLAYERS + 1], g_nextDoor[MAXPLAYERS + 1];
float g_doorPos[MAXPLAYERS + 1][3];
bool g_doorStopped[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
    RegPluginLibrary(AIDIAG_LIBRARY);
    CreateNative("AIDiag_Event", NativeEvent);
    CreateNative("AIDiag_Command", NativeCommand);
    MarkNativeAsOptional("AnneNextBot_GetPathSnapshotInfo");
    MarkNativeAsOptional("AnneNextBot_GetPathSegment");
    return APLRes_Success;
}

bool NativeAvailable(const char[] name)
{
    return GetFeatureStatus(FeatureType_Native, name) == FeatureStatus_Available;
}

void RefreshFeatures()
{
    // GetFeatureStatus checks this plugin's native imports, not every native
    // exported by an extension. Do not gate capture on unused GetReason: the
    // compiler does not import it. These are the interfaces we actually call.
    static const char required[][] = {
        "__action_setlistener", "__action_removelistener", "ActionsManager.Iterator",
        "BehaviorAction.GetName", "BehaviorAction.Actor.get",
        "BehaviorAction.IsStarted.get", "BehaviorAction.IsSuspended.get"
    };
    bool wasAvailable = g_actions;
    g_actions = true;
    g_missingActions[0] = '\0';
    for (int i = 0; i < sizeof(required); i++)
    {
        if (NativeAvailable(required[i])) continue;
        g_actions = false;
        if (g_missingActions[0]) StrCat(g_missingActions, sizeof(g_missingActions), ",");
        StrCat(g_missingActions, sizeof(g_missingActions), required[i]);
    }
    g_paths = NativeAvailable("AnneNextBot_GetPathSnapshotInfo") && NativeAvailable("AnneNextBot_GetPathSegment");
    if (g_featuresReady && (!g_featuresReported || wasAvailable != g_actions))
    {
        if (!g_actions) LogError("[AIDiag] Actions capture unavailable; missing imported natives: %s. Basic trajectories continue.", g_missingActions);
        else LogMessage("[AIDiag] Actions capture available; start/end/suspend/resume observers enabled.");
        g_featuresReported = true;
    }
}

public void OnAllPluginsLoaded() { g_featuresReady = true; RefreshFeatures(); AttachExistingActions(); }
public void OnLibraryAdded(const char[] name) { RefreshFeatures(); AttachExistingActions(); }
public void OnLibraryRemoved(const char[] name) { RefreshFeatures(); }

public void OnPluginStart()
{
    g_enable = CreateConVar("ai_diagnostics_enable", "1", "Automatically record complete Tank and SI sessions", _, true, 0.0, true, 1.0);
    g_fileMB = CreateConVar("ai_diagnostics_file_mb", "4", "Maximum size of each diagnostic log part (MiB)", _, true, 1.0, true, 64.0);
    g_totalMB = CreateConVar("ai_diagnostics_total_mb", "128", "Total retained diagnostic logs (MiB), oldest parts removed first", _, true, 8.0, true, 1024.0);
    g_running = g_enable.BoolValue;
    g_enable.AddChangeHook(EnableChanged);
    RegAdminCmd("sm_ai_diag_status", StatusCommand, ADMFLAG_ROOT, "AI diagnostic queue, storage and timing status");
    HookEvent("player_spawn", Spawn, EventHookMode_Post);
    HookEvent("tank_spawn", Spawn, EventHookMode_Post);
    HookEvent("player_death", Death, EventHookMode_Pre);
    HookEvent("player_team", TeamChanged, EventHookMode_Pre);
    HookEvent("round_start", RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end", RoundEnd, EventHookMode_PostNoCopy);
    HookEventEx("mission_lost", RoundEnd, EventHookMode_PostNoCopy);
    HookEventEx("map_transition", RoundEnd, EventHookMode_PostNoCopy);
    HookEventEx("finale_win", RoundEnd, EventHookMode_PostNoCopy);
    HookEventEx("weapon_fire", WeaponFire, EventHookMode_Post);
    BuildPath(Path_SM, g_directory, sizeof(g_directory), "logs/ai_diagnostics");
    if (!DirExists(g_directory) && !CreateDirectory(g_directory, 511))
        LogError("[AIDiag] Cannot create log directory; queued records remain bounded, failures counted.");
    BeginInventory();
    RefreshFeatures();
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
    CreateTimer(SERVICE_INTERVAL, Service, _, TIMER_REPEAT);
    // Also supports late loading: OnMapStart is called by SourceMod afterwards.
}

public void OnMapStart()
{
    EndAll("map_start_cleanup");
    char map[96], stamp[40], prefix[160];
    GetCurrentMap(map, sizeof(map));
    FileToken(map);
    FormatTime(stamp, sizeof(stamp), "%Y%m%d_%H%M%S", GetTime());
    FormatEx(prefix, sizeof(prefix), "aid_%s_%s_%d_%d", map, stamp, GetSysTickCount(), ++g_mapSerial);
    if (g_boundaryPending) g_dropped++; // A whole map boundary could not be queued.
    strcopy(g_pendingPrefix, sizeof(g_pendingPrefix), prefix);
    FormatEx(g_pendingMeta, sizeof(g_pendingMeta), "schema=1 plugin=%s map=%s sample_hz=5 command_hz_per_owner=5 queue=%d flush_lines=%d path_window_nodes=%d actions=%d paths=%d privacy=entity_indices_only capture_scope=service_and_accepted_native",
        AIDIAG_VERSION, map, QUEUE_SIZE, FLUSH_LINES, PATH_NODES, g_actions, g_paths);
    g_boundaryPending = true;
    g_mapLive = true;
    g_lastFrame = 0.0;
    g_nextSummary = GetEngineTime() + 5.0;
    if (g_running)
    {
        QueueMapBoundary();
        for (int client = 1; client <= MaxClients; client++) EnsureSession(client, "map_start_or_late_load");
    }
    else QueueMapBoundary();
}

void QueueMapBoundary()
{
    // Do not mislabel new-map records as belonging to the preceding map if an
    // overloaded queue has not made room for its boundary yet.
    if (!g_boundaryPending || g_count >= QUEUE_SIZE) return;
    int slot = (g_head + g_count) % QUEUE_SIZE;
    g_count++;
    if (g_count > g_peak) g_peak = g_count;
    g_boundary[slot] = true;
    strcopy(g_queue[slot], LINE_SIZE, g_pendingPrefix);
    g_boundaryPending = false;
    if (g_running) Emit(0, "map_begin", g_pendingMeta, true);
}

public void OnMapEnd()
{
    EndAll("map_end");
    if (g_running) Emit(0, "map_end", "automatic=1", true);
    g_mapLive = false;
    FlushBatch(FLUSH_LINES);
}

public void OnPluginEnd()
{
    EndAll("plugin_unload");
    // Never drain an unbounded backlog during unload. The omitted tail is
    // explicitly counted in both the last part and SourceMod's server log.
    FlushBatch(FLUSH_LINES - 2);
    if (g_count > 0)
    {
        g_dropped += g_count;
        g_count = 0;
    }
    char tail[360];
    FormatEx(tail, sizeof(tail), "dropped=%d truncated=%d owner_drops=%d io_errors=%d uncertain_writes=%d written=%d",
        g_dropped, g_truncated, g_ownerDrops, g_ioErrors, g_uncertainWrites, g_written);
    Emit(0, "unload_summary", tail, true);
    FlushBatch(2);
    if (g_count) { g_dropped += g_count; g_count = 0; }
    if (g_dropped || g_ioErrors || g_truncated || g_ownerDrops)
        LogMessage("[AIDiag] unload: dropped=%d truncated=%d owner_drops=%d io_errors=%d written=%d",
            g_dropped, g_truncated, g_ownerDrops, g_ioErrors, g_written);
    ClosePart();
    delete g_inventory;
}

public void EnableChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    if (!cvar.BoolValue) EndAll("disabled");
    g_running = cvar.BoolValue;
    if (g_running && g_mapLive)
        for (int client = 1; client <= MaxClients; client++) EnsureSession(client, "enabled");
}

public void OnClientPutInServer(int client)
{
    g_session[client] = 0;
    SDKHook(client, SDKHook_PostThinkPost, ThinkPost);
}
public void OnClientDisconnect(int client) { EndSession(client, "disconnect"); }

bool IsInfected(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
        && GetClientTeam(client) == 3 && IsPlayerAlive(client)
        && GetEntProp(client, Prop_Send, "m_zombieClass") != 7;
}

void EnsureSession(int client, const char[] reason)
{
    if (!g_running || !g_mapLive || g_boundaryPending || !IsInfected(client) || g_session[client]) return;
    g_session[client] = ++g_sessionSerial;
    g_class[client] = GetEntProp(client, Prop_Send, "m_zombieClass");
    g_started[client] = GetGameTime();
    g_birthTick[client] = GetGameTickCount();
    g_target[client] = 0;
    g_observedVictim[client] = -1;
    g_hasCommandTarget[client] = false;
    g_sequence[client] = -1;
    g_moveType[client] = -1;
    g_flags[client] = -1;
    g_action[client][0] = '\0';
    g_nextPath[client] = 0.0;
    g_stillSince[client] = g_windowSince[client] = g_started[client];
    g_walked[client] = 0.0;
    g_stalled[client] = false;
    g_climbs[client] = 0;
    g_climbSince[client] = 0.0;
    g_door[client] = INVALID_ENT_REFERENCE;
    g_doorStopped[client] = false;
    g_nextDoor[client] = 0.0;
    g_rawButtons[client] = 0;
    for (int axis = 0; axis < 3; axis++) g_rawVel[client][axis] = 0.0;
    for (int owner = 0; owner < OWNER_SLOTS; owner++)
    {
        g_owners[client][owner][0] = '\0';
        g_ownerUsed[client][owner] = false;
        g_nextCommand[client][owner] = 0.0;
    }
    GetClientAbsOrigin(client, g_lastPos[client]);
    g_anchor[client] = g_lastPos[client];
    g_windowPos[client] = g_lastPos[client];
    char detail[200];
    FormatEx(detail, sizeof(detail), "reason=%s bot=%d actions=%d paths=%d", reason, IsFakeClient(client), g_actions, g_paths);
    Emit(client, "session_begin", detail, true);
    if (g_actions) ActionsManager.Iterator(client, AttachAction);
}

void EndSession(int client, const char[] reason)
{
    if (client < 1 || client > MaxClients || !g_session[client]) return;
    char detail[192];
    FormatEx(detail, sizeof(detail), "reason=%s duration=%.3f", reason, GetGameTime() - g_started[client]);
    Emit(client, "session_end", detail, true);
    g_session[client] = 0;
}
void EndAll(const char[] reason)
{
    for (int client = 1; client <= MaxClients; client++) EndSession(client, reason);
}
public void Spawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1) client = event.GetInt("tankid");
    // Another plugin can report si_spawn before our event listener runs.
    // Keep that same-tick session instead of separating its birth evidence.
    if (client > 0 && client <= MaxClients && StrEqual(name, "player_spawn")
        && g_session[client] && (g_birthTick[client] != GetGameTickCount()
        || (IsClientInGame(client) && g_class[client] != GetEntProp(client, Prop_Send, "m_zombieClass"))))
        EndSession(client, "respawn");
    EnsureSession(client, name);
}
public void Death(Event event, const char[] name, bool dontBroadcast)
{
    EndSession(GetClientOfUserId(event.GetInt("userid")), "death");
}
public void TeamChanged(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("team") != 3) EndSession(GetClientOfUserId(event.GetInt("userid")), "team_change");
}
public void RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    EndAll("round_restart");
    g_mapLive = true;
    if (g_running) Emit(0, "round_start", "automatic=1", true);
}
public void RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    EndAll(name);
    if (g_running) Emit(0, "round_end", name, true);
    g_mapLive = false;
}
public void WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || !g_session[client]) return;
    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    Emit(client, "weapon_fire", weapon);
}

// Immediate state edges, not a sampled approximation of sequence/ground/ladder
// transitions. Animation sequence IDs remain raw for model/map investigation.
public void ThinkPost(int client)
{
    if (!g_session[client] || !g_running || !IsInfected(client)) return;
    int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
    int moveType = view_as<int>(GetEntityMoveType(client));
    int flags = GetEntityFlags(client) & (FL_ONGROUND | FL_DUCKING | FL_INWATER);
    if (sequence == g_sequence[client] && moveType == g_moveType[client] && flags == g_flags[client]) return;
    bool climbing = moveType == view_as<int>(MOVETYPE_LADDER)
        || (g_class[client] == 8 && sequence >= 16 && sequence <= 23);
    bool wasClimbing = g_moveType[client] == view_as<int>(MOVETYPE_LADDER)
        || (g_class[client] == 8 && g_sequence[client] >= 16 && g_sequence[client] <= 23);
    char detail[192];
    FormatEx(detail, sizeof(detail), "seq=%d->%d move=%d->%d flags=%d->%d climbing=%d",
        g_sequence[client], sequence, g_moveType[client], moveType, g_flags[client], flags, climbing);
    Emit(client, "state", detail);
    if (climbing && !wasClimbing) MarkClimb(client);
    g_sequence[client] = sequence;
    g_moveType[client] = moveType;
    g_flags[client] = flags;
}

public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_session[client]) return;
    g_rawButtons[client] = buttons;
    g_rawVel[client] = vel;
}
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
    if (!g_session[client]) return;
    RecordCommand(client, g_hasCommandTarget[client] ? g_target[client] : g_observedVictim[client], "pipeline", g_rawButtons[client], g_rawVel[client], buttons, vel);
}

// L4DHooks' existing global forward works without introducing a hard native
// dependency. This is the victim seen at this observer's callback order, not a
// claim that a later gameplay plugin cannot change it. Keep command target too.
public Action L4D2_OnChooseVictim(int client, int &target)
{
    if (client < 1 || client > MaxClients || !g_session[client] || g_observedVictim[client] == target) return Plugin_Continue;
    char detail[128];
    FormatEx(detail, sizeof(detail), "old=%d new=%d source=choose_victim_observer", g_observedVictim[client], target);
    Emit(client, "victim", detail);
    g_observedVictim[client] = target;
    return Plugin_Continue;
}

public any NativeEvent(Handle plugin, int params)
{
    int client = GetNativeCell(1);
    EnsureSession(client, "native_event");
    if (client < 1 || client > MaxClients || !g_session[client]) return 0;
    if (g_count >= QUEUE_SIZE - CONTROL_RESERVE) { g_dropped++; return 0; }
    float began = GetEngineTime();
    char category[48], detail[384];
    int length;
    GetNativeStringLength(2, length);
    if (length >= sizeof(category)) g_truncated++;
    GetNativeStringLength(3, length);
    if (length >= sizeof(detail)) g_truncated++;
    GetNativeString(2, category, sizeof(category));
    GetNativeString(3, detail, sizeof(detail));
    Emit(client, category, detail);
    g_captureMS += (GetEngineTime() - began) * 1000.0;
    return 0;
}

public any NativeCommand(Handle plugin, int params)
{
    int client = GetNativeCell(1);
    EnsureSession(client, "native_command");
    if (client < 1 || client > MaxClients || !g_session[client]) return 0;
    char owner[OWNER_LENGTH];
    GetNativeString(3, owner, sizeof(owner));
    int ownerSlot = CommandSlot(client, owner);
    if (ownerSlot < 0) return 0;
    int target = GetNativeCell(2);
    if (!g_hasCommandTarget[client] || g_target[client] != target)
    {
        char detail[128];
        FormatEx(detail, sizeof(detail), "old=%d new=%d owner=%s", g_target[client], target, owner);
        Emit(client, "target", detail);
        g_target[client] = target;
    }
    g_hasCommandTarget[client] = true;
    if (!CommandDue(client, ownerSlot)) return 0;
    float began = GetEngineTime(), raw[3], finalVel[3];
    GetNativeArray(5, raw, 3);
    GetNativeArray(7, finalVel, 3);
    int length;
    GetNativeStringLength(3, length);
    if (length >= sizeof(owner)) g_truncated++;
    WriteCommand(client, target, owner, GetNativeCell(4), raw, GetNativeCell(6), finalVel);
    g_captureMS += (GetEngineTime() - began) * 1000.0;
    return 0;
}

int CommandSlot(int client, const char[] owner)
{
    for (int slot = 0; slot < OWNER_SLOTS; slot++)
    {
        if (g_ownerUsed[client][slot] && StrEqual(g_owners[client][slot], owner)) return slot;
        if (!g_ownerUsed[client][slot])
        {
            g_ownerUsed[client][slot] = true;
            strcopy(g_owners[client][slot], OWNER_LENGTH, owner);
            return slot;
        }
    }
    g_ownerDrops++;
    return -1;
}
bool CommandDue(int client, int slot)
{
    float now = GetGameTime();
    if (now < g_nextCommand[client][slot]) { g_throttled++; return false; }
    g_nextCommand[client][slot] = now + SERVICE_INTERVAL;
    if (g_count >= QUEUE_SIZE - CONTROL_RESERVE) { g_dropped++; return false; }
    return true;
}
void RecordCommand(int client, int target, const char[] owner, int rawButtons, const float rawVel[3], int finalButtons, const float finalVel[3])
{
    int slot = CommandSlot(client, owner);
    if (slot >= 0 && CommandDue(client, slot)) WriteCommand(client, target, owner, rawButtons, rawVel, finalButtons, finalVel);
}
void WriteCommand(int client, int target, const char[] owner, int rawButtons, const float rawVel[3], int finalButtons, const float finalVel[3])
{
    char detail[384], safeOwner[OWNER_LENGTH];
    strcopy(safeOwner, sizeof(safeOwner), owner);
    Clean(safeOwner);
    FormatEx(detail, sizeof(detail), "target=%d owner=%s raw_buttons=%d raw_vel=%.2f,%.2f,%.2f final_buttons=%d final_vel=%.2f,%.2f,%.2f",
        target, safeOwner, rawButtons, rawVel[0], rawVel[1], rawVel[2], finalButtons, finalVel[0], finalVel[1], finalVel[2]);
    Emit(client, "command", detail);
}

public Action Service(Handle timer)
{
    float began = GetEngineTime();
    QueueMapBoundary();
    if (g_running && g_mapLive)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (g_session[client] && !IsInfected(client)) EndSession(client, "no_longer_alive_infected");
            EnsureSession(client, "observed_alive");
            if (!g_session[client]) continue;
            Sample(client);
            if (g_class[client] == 8) CapturePath(client);
        }
        ScanDoors();
    }
    g_captureMS += (GetEngineTime() - began) * 1000.0;
    if (GetEngineTime() >= g_nextSummary && (g_running || g_count))
    {
        EmitSummary();
        g_nextSummary = GetEngineTime() + 5.0;
    }
    InventoryStep();
    FlushBatch(FLUSH_LINES);
    return Plugin_Continue;
}

void Sample(int client)
{
    float pos[3], velocity[3];
    GetClientAbsOrigin(client, pos);
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    int enemy = HasEntProp(client, Prop_Send, "m_hEnemy") ? GetEntPropEnt(client, Prop_Send, "m_hEnemy") : -1;
    char detail[480];
    FormatEx(detail, sizeof(detail), "pos=%.2f,%.2f,%.2f velocity=%.2f,%.2f,%.2f target=%d command_target_valid=%d observed_victim=%d enemy=%d seq=%d move=%d flags=%d hp=%d action=%s",
        pos[0], pos[1], pos[2], velocity[0], velocity[1], velocity[2], g_hasCommandTarget[client] ? g_target[client] : g_observedVictim[client], g_hasCommandTarget[client], g_observedVictim[client], enemy,
        g_sequence[client], g_moveType[client], g_flags[client], GetClientHealth(client), g_action[client]);
    Emit(client, "sample", detail);
    MarkMovement(client, pos);
}

// Heuristic labels are evidence for investigation, never gameplay decisions.
void MarkMovement(int client, const float pos[3])
{
    float now = GetGameTime();
    if (GetVectorDistance(pos, g_anchor[client]) >= 24.0)
    {
        if (g_stalled[client]) Emit(client, "mark_stall_end", "movement_resumed=1");
        g_stalled[client] = false;
        g_anchor[client] = pos;
        g_stillSince[client] = now;
    }
    else if (!g_stalled[client] && now - g_stillSince[client] >= 3.0)
    {
        Emit(client, "mark_stall", "heuristic=1 radius=24 duration=3 includes_no_input_and_intentional_wait");
        g_stalled[client] = true;
    }
    float step = GetVectorDistance(pos, g_lastPos[client]);
    if (step > 256.0)
    {
        Emit(client, "position_discontinuity", "step_over_256=1 window_reset=1");
        g_windowSince[client] = now;
        g_windowPos[client] = pos;
        g_walked[client] = 0.0;
    }
    else g_walked[client] += step;
    if (now - g_windowSince[client] >= 8.0)
    {
        float net = GetVectorDistance(pos, g_windowPos[client]);
        if (g_walked[client] >= 240.0 && net < 80.0)
        {
            char detail[160];
            FormatEx(detail, sizeof(detail), "heuristic=1 duration=%.2f travelled=%.2f net=%.2f", now - g_windowSince[client], g_walked[client], net);
            Emit(client, "mark_back_and_forth", detail);
        }
        g_windowSince[client] = now;
        g_windowPos[client] = pos;
        g_walked[client] = 0.0;
    }
    g_lastPos[client] = pos;
}
void MarkClimb(int client)
{
    float pos[3], now = GetGameTime();
    GetClientAbsOrigin(client, pos);
    if (!g_climbs[client] || now - g_climbSince[client] > 12.0 || GetVectorDistance(pos, g_climbPos[client]) > 96.0)
    {
        g_climbs[client] = 0;
        g_climbSince[client] = now;
        g_climbPos[client] = pos;
    }
    if (++g_climbs[client] == 3) Emit(client, "mark_repeated_climb", "heuristic=1 count=3 radius=96 window=12");
}

// At most four simple traces per service (20/s globally), round-robin clients.
void ScanDoors()
{
    int budget = 4;
    float now = GetGameTime();
    for (int visited = 0; visited < MaxClients && budget > 0; visited++)
    {
        int client = g_doorCursor;
        g_doorCursor = g_doorCursor % MaxClients + 1;
        if (!g_session[client] || !IsInfected(client) || now < g_nextDoor[client]) continue;
        g_nextDoor[client] = now + 0.5;
        budget--;
        float origin[3], angles[3], direction[3], end[3];
        GetClientAbsOrigin(client, origin);
        origin[2] += 40.0;
        GetClientEyeAngles(client, angles);
        angles[0] = 0.0;
        GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
        ScaleVector(direction, 110.0);
        AddVectors(origin, direction, end);
        Handle trace = TR_TraceRayFilterEx(origin, end, MASK_SOLID, RayType_EndPoint, IgnoreActors);
        int entity = TR_DidHit(trace) ? TR_GetEntityIndex(trace) : -1;
        delete trace;
        int ref = INVALID_ENT_REFERENCE;
        char classname[64];
        if (entity > MaxClients && IsValidEntity(entity))
        {
            GetEntityClassname(entity, classname, sizeof(classname));
            if (StrEqual(classname, "prop_door_rotating") || StrEqual(classname, "func_door") || StrEqual(classname, "func_door_rotating"))
                ref = EntIndexToEntRef(entity);
        }
        if (ref != g_door[client])
        {
            if (g_door[client] != INVALID_ENT_REFERENCE) Emit(client, "door_leave", "forward_trace_changed=1");
            g_door[client] = ref;
            g_doorSince[client] = now;
            g_doorStopped[client] = false;
            GetClientAbsOrigin(client, g_doorPos[client]);
            if (ref != INVALID_ENT_REFERENCE)
            {
                char detail[128];
                FormatEx(detail, sizeof(detail), "entity=%d ref=%d class=%s", entity, ref, classname);
                Emit(client, "door_ahead", detail);
            }
        }
        if (ref == INVALID_ENT_REFERENCE) continue;
        GetClientAbsOrigin(client, origin);
        if (GetVectorDistance(origin, g_doorPos[client]) > 32.0)
        {
            g_doorSince[client] = now;
            g_doorPos[client] = origin;
            g_doorStopped[client] = false;
        }
        else if (!g_doorStopped[client] && now - g_doorSince[client] >= 3.0)
        {
            char detail[128];
            FormatEx(detail, sizeof(detail), "heuristic=1 entity=%d ref=%d duration=%.2f", entity, ref, now - g_doorSince[client]);
            Emit(client, "mark_door_stop", detail);
            g_doorStopped[client] = true;
        }
    }
}
public bool IgnoreActors(int entity, int mask) { return entity < 1 || entity > MaxClients; }

public void AnneNextBot_OnTankPathSnapshotUpdated(int client)
{
    if (client > 0 && client <= MaxClients && g_session[client]) CapturePath(client);
}
void CapturePath(int client)
{
    float now = GetGameTime();
    if (now < g_nextPath[client]) return;
    g_nextPath[client] = now + 0.5;
    int count = 0, current = -1;
    bool complete = false;
    float age = -1.0;
    bool valid = g_paths && AnneNextBot_GetPathSnapshotInfo(client, count, current, complete, age);
    int start = current > 0 ? current - 1 : 0;
    int stop = start + PATH_NODES;
    if (stop > count) stop = count;
    char detail[300];
    FormatEx(detail, sizeof(detail), "available=%d valid=%d count=%d current=%d complete=%d age=%.3f first=%d stop=%d omitted=%d",
        g_paths, valid, count, current, complete, age, start, stop, count > PATH_NODES ? count - (stop - start) : 0);
    Emit(client, "path_snapshot", detail);
    if (!valid) return;
    for (int index = start; index < stop; index++)
    {
        Address area;
        int traverse, type;
        float goal[3], forwardVector[3], length, distance;
        if (!AnneNextBot_GetPathSegment(client, index, area, traverse, goal, type, forwardVector, length, distance))
        {
            FormatEx(detail, sizeof(detail), "index=%d valid=0", index);
            Emit(client, "path_segment", detail);
            continue;
        }
        FormatEx(detail, sizeof(detail), "index=%d valid=1 nav=%x traverse=%d type=%d goal=%.2f,%.2f,%.2f forward=%.3f,%.3f,%.3f length=%.2f distance=%.2f",
            index, area, traverse, type, goal[0], goal[1], goal[2], forwardVector[0], forwardVector[1], forwardVector[2], length, distance);
        Emit(client, "path_segment", detail);
    }
}

void AttachExistingActions()
{
    if (!g_actions) return;
    for (int client = 1; client <= MaxClients; client++)
        if (g_session[client] && IsInfected(client)) ActionsManager.Iterator(client, AttachAction);
}
public void AttachAction(BehaviorAction action)
{
    if (!g_actions || action == INVALID_ACTION) return;
    // Remove only our own function before reattaching (late-load/iteration can
    // see an action twice). Other plugins' decision listeners are untouched.
    __action_removelistener(action, __action_processor_OnStart, ActionStart, true);
    __action_removelistener(action, __action_processor_OnEnd, ActionEnd, true);
    __action_removelistener(action, __action_processor_OnSuspend, ActionSuspend, true);
    __action_removelistener(action, __action_processor_OnResume, ActionResume, true);
    action.OnStartPost = ActionStart;
    action.OnEndPost = ActionEnd;
    action.OnSuspendPost = ActionSuspend;
    action.OnResumePost = ActionResume;
    g_actionHooks++;
    int actor = action.Actor;
    if (actor > 0 && actor <= MaxClients && g_session[actor] && action.IsStarted && !action.IsSuspended)
        ActionEdge(action, actor, "action_existing", true);
}
public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
    if (!g_actions || (actor > 0 && !IsInfected(actor))) return;
    AttachAction(action);
    if (actor > 0 && actor <= MaxClients && g_session[actor]) Emit(actor, "action_created", name);
}
public void OnActionDestroyed(BehaviorAction action, int actor, const char[] name)
{
    if (actor > 0 && actor <= MaxClients && g_session[actor]) Emit(actor, "action_destroyed", name);
}
void ActionEdge(BehaviorAction action, int actor, const char[] edge, bool active)
{
    if (actor < 1 || actor > MaxClients || !g_session[actor]) return;
    if (!StrEqual(edge, "action_existing")) g_actionCallbacks++;
    char name[64];
    action.GetName(name, sizeof(name));
    Emit(actor, edge, name);
    if (active) strcopy(g_action[actor], sizeof(g_action[]), name);
    else if (StrEqual(g_action[actor], name)) g_action[actor][0] = '\0';
}
public Action ActionStart(BehaviorAction action, int actor, BehaviorAction prior, ActionResult result)
{
    ActionEdge(action, actor, "action_start", true);
    return Plugin_Continue;
}
public void ActionEnd(BehaviorAction action, int actor, BehaviorAction next, ActionResult result)
{
    ActionEdge(action, actor, "action_end", false);
}
public Action ActionSuspend(BehaviorAction action, int actor, BehaviorAction next, ActionResult result)
{
    ActionEdge(action, actor, "action_suspend", false);
    return Plugin_Continue;
}
public Action ActionResume(BehaviorAction action, int actor, BehaviorAction prior, ActionResult result)
{
    ActionEdge(action, actor, "action_resume", true);
    return Plugin_Continue;
}

public void OnGameFrame()
{
    if (!g_running || !g_mapLive) return;
    float now = GetEngineTime();
    if (g_lastFrame > 0.0)
    {
        float interval = now - g_lastFrame;
        g_frames++;
        g_frameSum += interval;
        if (interval > g_frameMax) g_frameMax = interval;
        if (interval > GetTickInterval() * 1.5) g_slowFrames++;
    }
    g_lastFrame = now;
}
void EmitSummary()
{
    char detail[520];
    FormatEx(detail, sizeof(detail), "frames=%d frame_mean_ms=%.3f frame_max_ms=%.3f slow_frames=%d capture_ms=%.3f flush_ms=%.3f flush_max_ms=%.3f queue=%d peak=%d dropped=%d truncated=%d owner_drops=%d throttled=%d io_errors=%d uncertain_writes=%d written=%d disk_bytes=%d deleted_parts=%d actions=%d paths=%d",
        g_frames, g_frames ? g_frameSum * 1000.0 / g_frames : 0.0, g_frameMax * 1000.0, g_slowFrames,
        g_captureMS, g_flushMS, g_flushMaxMS, g_count, g_peak, g_dropped, g_truncated, g_ownerDrops, g_throttled, g_ioErrors, g_uncertainWrites, g_written, g_diskBytes, g_deleted, g_actions, g_paths);
    Emit(0, "performance", detail, true);
    if (g_reportedDrops != g_dropped || g_reportedTruncated != g_truncated || g_reportedOwnerDrops != g_ownerDrops || g_reportedIO != g_ioErrors)
    {
        LogMessage("[AIDiag] budget/storage counters: dropped=%d truncated=%d owner_drops=%d io_errors=%d queue=%d peak=%d",
            g_dropped, g_truncated, g_ownerDrops, g_ioErrors, g_count, g_peak);
        g_reportedDrops = g_dropped;
        g_reportedTruncated = g_truncated;
        g_reportedOwnerDrops = g_ownerDrops;
        g_reportedIO = g_ioErrors;
    }
    g_frames = g_slowFrames = 0;
    g_frameSum = g_frameMax = g_captureMS = g_flushMS = g_flushMaxMS = 0.0;
}
public Action StatusCommand(int client, int args)
{
    int sessions, tanks;
    for (int actor = 1; actor <= MaxClients; actor++)
        if (g_session[actor]) { sessions++; if (g_class[actor] == 8) tanks++; }
    ReplyToCommand(client, "[AIDiag] enabled=%d live=%d sessions=%d tanks=%d actions=%d paths=%d inventory_ready=%d queue=%d/%d peak=%d",
        g_running, g_mapLive, sessions, tanks, g_actions, g_paths, g_storageReady, g_count, QUEUE_SIZE, g_peak);
    ReplyToCommand(client, "[AIDiag] written=%d dropped=%d truncated=%d owner_drops=%d throttled=%d io_errors=%d uncertain_writes=%d disk=%.2fMiB cap=%dMiB deleted=%d",
        g_written, g_dropped, g_truncated, g_ownerDrops, g_throttled, g_ioErrors, g_uncertainWrites, float(g_diskBytes) / MIB, g_totalMB.IntValue, g_deleted);
    ReplyToCommand(client, "[AIDiag] interval frames=%d mean=%.3fms max=%.3fms slow=%d capture=%.3fms flush=%.3fms flush_max=%.3fms file=%s",
        g_frames, g_frames ? g_frameSum * 1000.0 / g_frames : 0.0, g_frameMax * 1000.0, g_slowFrames, g_captureMS, g_flushMS, g_flushMaxMS, g_currentPath);
    ReplyToCommand(client, "[AIDiag] action_hooks=%d action_callbacks=%d missing_action_natives=%s",
        g_actionHooks, g_actionCallbacks, g_actions ? "none" : g_missingActions);
    return Plugin_Handled;
}

int Reserve(bool control = false)
{
    if (g_count >= (control ? QUEUE_SIZE - 1 : QUEUE_SIZE - CONTROL_RESERVE)) { g_dropped++; return -1; }
    int slot = (g_head + g_count) % QUEUE_SIZE;
    g_count++;
    if (g_count > g_peak) g_peak = g_count;
    g_boundary[slot] = false;
    return slot;
}
void Emit(int client, const char[] category, const char[] detail, bool control = false)
{
    if (g_boundaryPending) { g_dropped++; return; }
    int slot = Reserve(control);
    if (slot < 0) return;
    char safeCategory[64], safeDetail[560];
    if (strlen(category) >= sizeof(safeCategory) || strlen(detail) >= sizeof(safeDetail)) g_truncated++;
    strcopy(safeCategory, sizeof(safeCategory), category);
    strcopy(safeDetail, sizeof(safeDetail), detail);
    Clean(safeCategory); Clean(safeDetail);
    int length = FormatEx(g_queue[slot], LINE_SIZE, "t=%.3f tick=%d session=%d client=%d class=%d kind=%s %s\n",
        GetGameTime(), GetGameTickCount(), client ? g_session[client] : 0, client, client ? g_class[client] : 0, safeCategory, safeDetail);
    if (length >= LINE_SIZE - 1) g_truncated++;
}
void Clean(char[] value)
{
    for (int i = 0; value[i]; i++) if (value[i] < 32 || value[i] == 127) value[i] = ' ';
}
void FileToken(char[] value)
{
    for (int i = 0; value[i]; i++)
        if (!IsCharAlpha(value[i]) && !IsCharNumeric(value[i]) && value[i] != '_' && value[i] != '-') value[i] = '_';
}

// Inventory and retention are bounded as well as writes. Existing logs are
// scanned in small batches before any new bytes can bypass the total quota.
void BeginInventory()
{
    delete g_inventory;
    g_inventory = OpenDirectory(g_directory);
    g_storageReady = false;
    if (g_inventory == null) { g_ioErrors++; g_nextRetry = GetEngineTime() + 5.0; }
}
int EmptyFileSlot()
{
    for (int i = 0; i < FILE_SLOTS; i++) if (!g_files[i][0]) return i;
    return -1;
}
bool DeleteOldest()
{
    int oldest = -1;
    for (int i = 0; i < FILE_SLOTS; i++)
        if (g_files[i][0] && i != g_currentFile && (oldest < 0 || g_times[i] < g_times[oldest])) oldest = i;
    if (oldest < 0) return false;
    if (!DeleteFile(g_files[oldest])) { g_ioErrors++; return false; }
    g_diskBytes -= g_sizes[oldest];
    g_sizes[oldest] = 0;
    g_files[oldest][0] = '\0';
    g_deleted++;
    return true;
}
void InventoryStep()
{
    if (g_storageReady) return;
    if (GetEngineTime() < g_inventoryRetry) return;
    if (g_inventory == null)
    {
        if (GetEngineTime() >= g_nextRetry) BeginInventory();
        return;
    }
    for (int step = 0; step < DIRECTORY_STEPS; step++)
    {
        char name[PLATFORM_MAX_PATH];
        FileType type;
        // Make room before consuming an entry, so a failed deletion cannot
        // silently exclude an existing file from the total-space accounting.
        int slot = EmptyFileSlot();
        if (slot < 0)
        {
            if (!DeleteOldest()) { g_inventoryRetry = GetEngineTime() + 5.0; return; }
            slot = EmptyFileSlot();
        }
        if (g_inventoryName[0])
        {
            strcopy(name, sizeof(name), g_inventoryName);
            type = FileType_File;
        }
        else if (!g_inventory.GetNext(name, sizeof(name), type))
        {
            delete g_inventory;
            g_storageReady = true;
            return;
        }
        int length = strlen(name);
        if (type != FileType_File || StrContains(name, "aid_") != 0 || length < 8 || !StrEqual(name[length - 4], ".log")) continue;
        char path[PLATFORM_MAX_PATH];
        FormatEx(path, sizeof(path), "%s/%s", g_directory, name);
        int bytes = FileSize(path);
        if (bytes < 0)
        {
            g_ioErrors++;
            strcopy(g_inventoryName, sizeof(g_inventoryName), name);
            g_inventoryRetry = GetEngineTime() + 5.0;
            return;
        }
        // Avoid integer overflow even when an old/corrupt directory is far
        // over quota. Hold the entry and reclaim at most one indexed part per
        // inventory step before accounting for it; never underestimate bytes.
        if (g_diskBytes > 2147480000 - bytes)
        {
            strcopy(g_inventoryName, sizeof(g_inventoryName), name);
            if (!DeleteOldest()) g_inventoryRetry = GetEngineTime() + 5.0;
            continue;
        }
        g_inventoryName[0] = '\0';
        strcopy(g_files[slot], PLATFORM_MAX_PATH, path);
        g_sizes[slot] = bytes;
        g_times[slot] = GetFileTime(path, FileTime_LastChange);
        g_diskBytes += bytes;
    }
}

bool OpenPart()
{
    if (!g_prefix[0]) return false;
    int slot = EmptyFileSlot();
    if (slot < 0) return false; // Retention frees a slot on a later service.
    // Timestamp, map, engine millisecond stamp, map serial and part together
    // avoid collisions; never overwrite an old log even after a fast reload.
    for (int attempt = 0; attempt < 4; attempt++)
    {
        FormatEx(g_currentPath, sizeof(g_currentPath), "%s/%s_%04d.log", g_directory, g_prefix, ++g_part);
        if (!FileExists(g_currentPath)) break;
        if (attempt == 3) return false;
    }
    // Binary mode keeps byte quotas exact on Windows as well as Linux (LF).
    g_file = OpenFile(g_currentPath, "wb");
    if (g_file == null) { g_ioErrors++; g_nextRetry = GetEngineTime() + 5.0; return false; }
    g_currentFile = slot;
    strcopy(g_files[slot], PLATFORM_MAX_PATH, g_currentPath);
    g_sizes[slot] = 0;
    g_times[slot] = GetTime();
    char header[256];
    FormatEx(header, sizeof(header), "schema=1 plugin=%s stream=%s part=%d sample_hz=5 privacy=no_names_no_ids_no_ips\n", AIDIAG_VERSION, g_prefix, g_part);
    if (WriteLineBounded(header)) return true;
    // Never let data follow a missing/partial metadata header.
    g_dropped++;
    ClosePart();
    g_nextRetry = GetEngineTime() + 5.0;
    return false;
}

bool WriteLineBounded(const char[] line)
{
    int bytes = strlen(line);
    if (g_file == null || g_currentFile < 0 || g_diskBytes > g_totalMB.IntValue * MIB - bytes
        || g_sizes[g_currentFile] + bytes > PartBytes()) return false;
    if (!g_file.WriteString(line, false))
    {
        g_ioErrors++;
        int actual = g_file.Size();
        if (actual >= 0)
        {
            g_diskBytes += actual - g_sizes[g_currentFile];
            g_sizes[g_currentFile] = actual;
        }
        return false;
    }
    g_sizes[g_currentFile] += bytes;
    g_diskBytes += bytes;
    g_written++;
    g_unflushed++;
    return true;
}

bool FlushCurrent()
{
    if (g_file == null || !g_unflushed) return true;
    bool success = g_file.Flush();
    if (!success)
    {
        g_ioErrors++;
        g_uncertainWrites += g_unflushed;
    }
    g_unflushed = 0;
    return success;
}
void ClosePart()
{
    FlushCurrent();
    delete g_file;
    g_currentFile = -1;
}

int PartBytes()
{
    int bytes = g_fileMB.IntValue * MIB;
    int halfTotal = g_totalMB.IntValue * MIB / 2;
    return bytes < halfTotal ? bytes : halfTotal;
}

void FlushBatch(int limit)
{
    if (!g_storageReady || GetEngineTime() < g_nextRetry) return;
    float began = GetEngineTime();
    if (g_file != null && (g_sizes[g_currentFile] + LINE_SIZE * 2 > PartBytes()
        || g_diskBytes > g_totalMB.IntValue * MIB - LINE_SIZE * 2))
    {
        ClosePart();
    }
    // At most four deletions per service; do not spin on a large old directory.
    for (int removed = 0; removed < 4; removed++)
    {
        if (g_diskBytes <= g_totalMB.IntValue * MIB - LINE_SIZE * 2 && EmptyFileSlot() >= 0) break;
        if (!DeleteOldest()) break;
    }
    int wroteAtStart = g_written;
    for (int done = 0; done < limit && g_count; done++)
    {
        if (g_written - wroteAtStart >= limit) break;
        int slot = g_head;
        if (g_boundary[slot])
        {
            ClosePart();
            strcopy(g_prefix, sizeof(g_prefix), g_queue[slot]);
            g_part = 0;
        }
        else
        {
            if (g_file != null && g_sizes[g_currentFile] + strlen(g_queue[slot]) > PartBytes())
            {
                ClosePart();
            }
            if (g_diskBytes > g_totalMB.IntValue * MIB - LINE_SIZE * 2) break;
            if (g_file == null)
            {
                if (g_written - wroteAtStart >= limit - 1 || !OpenPart()) break;
            }
            if (!WriteLineBounded(g_queue[slot]))
            {
                // A partial/failed write is not retried blindly (may duplicate).
                // Drop exactly this record and retry opening on the next service.
                g_dropped++;
                ClosePart();
                g_nextRetry = GetEngineTime() + 5.0;
            }
        }
        g_head = (g_head + 1) % QUEUE_SIZE;
        g_count--;
        if (GetEngineTime() < g_nextRetry) break;
    }
    if (g_written > wroteAtStart && !FlushCurrent())
    {
        g_nextRetry = GetEngineTime() + 5.0;
        ClosePart();
    }
    float elapsed = (GetEngineTime() - began) * 1000.0;
    g_flushMS += elapsed;
    if (elapsed > g_flushMaxMS) g_flushMaxMS = elapsed;
}
