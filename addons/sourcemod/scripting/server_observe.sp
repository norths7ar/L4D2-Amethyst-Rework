#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

native bool IsInPause();
native bool IsInReady();

public Plugin myinfo =
{
    name = "Server frame observer",
    author = "L4D2-Amethyst-Rework",
    description = "Wall-clock frame intervals and workload snapshots, not CPU profiling",
    version = "1.0.1"
};

char g_Map[128], g_Day[16], g_Path[PLATFORM_MAX_PATH];
float g_LastFrame, g_WindowStart, g_Sum, g_Max;
int g_Frames, g_Over20, g_Over50, g_Over100;
int g_Hibernating = -1;
bool g_MapActive;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
    MarkNativeAsOptional("IsInPause");
    MarkNativeAsOptional("IsInReady");
    return APLRes_Success;
}

public void OnPluginStart()
{
    RegAdminCmd("sm_observe_mark", Command_Mark, ADMFLAG_GENERIC, "sm_observe_mark <label>");
    RegAdminCmd("sm_lag", Command_QuickMark, ADMFLAG_GENERIC, "Mark current play as laggy");
    RegAdminCmd("sm_fine", Command_QuickMark, ADMFLAG_GENERIC, "Mark current play as smooth");
    GetCurrentMap(g_Map, sizeof(g_Map));
    ResetWindow();
    WriteRecord("plugin_start", "");
}

public void OnMapStart()
{
    GetCurrentMap(g_Map, sizeof(g_Map));
    g_MapActive = true;
    g_Hibernating = -1;
    ResetWindow();
    WriteRecord("map_start", "");
}

public void OnMapEnd()
{
    WriteRecord("map_end", "");
    g_MapActive = false;
    ResetWindow();
}

public void OnPluginEnd()
{
    WriteRecord("plugin_end", "");
}

// Split windows at explicit pause boundaries so pause time is not a lag spike.
// These forwards describe the installed pause plugin, not arbitrary engine pauses.
public void OnPause()
{
    WriteRecord("pause_start", "");
    ResetWindow();
}

public void OnUnpause()
{
    WriteRecord("pause_end", "");
    ResetWindow();
}

// Left4DHooks forwards this when present; -1 means no observed transition yet.
public void L4D_OnServerHibernationUpdate(bool hibernating)
{
    g_Hibernating = hibernating ? 1 : 0;
    WriteRecord("hibernation", "");
    ResetWindow();
}

void ResetWindow()
{
    g_WindowStart = GetEngineTime();
    g_LastFrame = 0.0;
    g_Sum = 0.0;
    g_Max = 0.0;
    g_Frames = 0;
    g_Over20 = 0;
    g_Over50 = 0;
    g_Over100 = 0;
}

public void OnGameFrame()
{
    float now = GetEngineTime();
    if (g_LastFrame > 0.0)
    {
        float interval = (now - g_LastFrame) * 1000.0;
        g_Frames++;
        g_Sum += interval;
        if (interval > g_Max) g_Max = interval;
        if (interval > 20.0) g_Over20++;
        if (interval > 50.0) g_Over50++;
        if (interval > 100.0) g_Over100++;
    }
    g_LastFrame = now;
    // Real engine clock, not simulation-time timers. A stall is recorded on return.
    // No in-process plugin can write while the engine itself is blocked.
    if (now - g_WindowStart >= 5.0)
    {
        WriteRecord("sample", "");
        ResetWindow();
        g_LastFrame = now;
    }
}

public Action Command_QuickMark(int client, int args)
{
    char command[32];
    GetCmdArg(0, command, sizeof(command));
    bool lag = StrEqual(command, "sm_lag", false);
    if (WriteRecord("mark", lag ? "lag" : "smooth"))
        ReplyToCommand(client, lag ? "已标记：卡顿。" : "已标记：流畅。");
    else
        ReplyToCommand(client, "标记写入失败，请检查服务器日志。");
    return Plugin_Handled;
}

public Action Command_Mark(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "用法：sm_observe_mark <lag/smooth/备注>");
        return Plugin_Handled;
    }
    char label[192];
    GetCmdArgString(label, sizeof(label));
    StripQuotes(label);
    // Keep one parseable line; never record the caller's identity.
    ReplaceString(label, sizeof(label), "\\", "/");
    ReplaceString(label, sizeof(label), "\"", "'");
    ReplaceString(label, sizeof(label), "\n", " ");
    ReplaceString(label, sizeof(label), "\r", " ");
    ReplaceString(label, sizeof(label), "\t", " ");
    if (WriteRecord("mark", label))
        ReplyToCommand(client, "已记录观测标记。");
    else
        ReplyToCommand(client, "标记写入失败，请检查服务器日志。");
    return Plugin_Handled;
}

void PrepareLog()
{
    char day[16];
    FormatTime(day, sizeof(day), "%Y%m%d", GetTime());
    if (StrEqual(day, g_Day)) return;
    strcopy(g_Day, sizeof(g_Day), day);
    BuildPath(Path_SM, g_Path, sizeof(g_Path), "logs/server_observe_%s.log", day);

    char directory[PLATFORM_MAX_PATH], name[PLATFORM_MAX_PATH], oldPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, directory, sizeof(directory), "logs");
    DirectoryListing listing = OpenDirectory(directory);
    if (listing == null) return;
    FileType type;
    while (listing.GetNext(name, sizeof(name), type))
    {
        if (type != FileType_File || strlen(name) != 27
            || StrContains(name, "server_observe_") != 0 || !StrEqual(name[23], ".log")) continue;
        bool ownFile = true;
        for (int i = 15; i < 23; i++)
            if (name[i] < '0' || name[i] > '9') ownFile = false;
        if (!ownFile) continue;
        FormatEx(oldPath, sizeof(oldPath), "%s/%s", directory, name);
        int modified = GetFileTime(oldPath, FileTime_LastChange);
        if (modified > 0 && GetTime() - modified > 7 * 86400) DeleteFile(oldPath);
    }
    delete listing;
}

bool WriteRecord(const char[] event, const char[] label)
{
    PrepareLog();
    int humans, specialAlive, commonAlive, witches, entities;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        if (!IsFakeClient(client)) humans++;
        if (GetClientTeam(client) == 3 && IsPlayerAlive(client)
            && !GetEntProp(client, Prop_Send, "m_isGhost")) specialAlive++;
    }
    // Only scan at emission, never each game frame.
    if (g_MapActive)
    {
        char classname[64];
        int limit = GetMaxEntities();
        for (int entity = MaxClients + 1; entity < limit; entity++)
        {
            if (!IsValidEntity(entity)) continue;
            entities++;
            GetEntityClassname(entity, classname, sizeof(classname));
            if (StrEqual(classname, "infected") && GetEntProp(entity, Prop_Data, "m_iHealth") > 0) commonAlive++;
            else if (StrEqual(classname, "witch") && GetEntProp(entity, Prop_Data, "m_iHealth") > 0) witches++;
        }
    }
    int paused = -1, ready = -1;
    if (GetFeatureStatus(FeatureType_Native, "IsInPause") == FeatureStatus_Available) paused = IsInPause() ? 1 : 0;
    if (GetFeatureStatus(FeatureType_Native, "IsInReady") == FeatureStatus_Available) ready = IsInReady() ? 1 : 0;
    File log = OpenFile(g_Path, "a");
    if (log == null)
    {
        LogError("Cannot open server observer log: %s", g_Path);
        return false;
    }
    float avg = g_Frames > 0 ? g_Sum / float(g_Frames) : 0.0;
    bool written = log.WriteLine("schema=1 ts=%d engine_s=%.3f event=%s map=%s window_s=%.3f frame_intervals=%d frame_interval_avg_ms=%.3f frame_interval_max_ms=%.3f over20=%d over50=%d over100=%d humans=%d special_alive=%d common_alive=%d witches_alive=%d nonclient_entities=%d processing=%d hibernating=%d paused=%d ready=%d label=\"%s\"",
        GetTime(), GetEngineTime(), event, g_Map, GetEngineTime() - g_WindowStart,
        g_Frames, avg, g_Max, g_Over20, g_Over50, g_Over100,
        humans, specialAlive, commonAlive, witches, entities, IsServerProcessing() ? 1 : 0,
        g_Hibernating, paused, ready, label);
    delete log;
    return written;
}
