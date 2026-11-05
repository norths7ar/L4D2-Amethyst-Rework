// Native ready-up warps are independent from countdown eligibility.
enum StartReturnState
{
    StartIdle, StartRequested, StartDone
};
StartReturnState g_startReturn[MAXPLAYERS + 1];
bool g_readyWarp = true;
bool g_startPlacement, g_startIntroPositions;
int g_startEpoch;
bool g_startLimited[MAXPLAYERS + 1], g_startInput[MAXPLAYERS + 1];
bool g_startBoundary[MAXPLAYERS + 1], g_startCounted[MAXPLAYERS + 1], g_startNotify[MAXPLAYERS + 1];
int g_startLoopCount[MAXPLAYERS + 1];
float g_startLoopTimes[MAXPLAYERS + 1][3], g_startRequestedAt[MAXPLAYERS + 1];
float g_startNextNotice[MAXPLAYERS + 1];
bool IsReadySurvivor(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client)
    && GetClientTeam(client) == TEAM_SURVIVORS && IsPlayerAlive(client);
}
bool StartArea_FreeNoclip(int client)
{
    return g_readyPhase && !g_startPlacement && g_countdownTimer == null
    && IsReadySurvivor(client) && GetEntityMoveType(client) == MOVETYPE_NOCLIP;
}
bool StartArea_IntroControlled(int client)
{
    if (!IsStartInitialized()) return true;
    if (g_startIntroPositions || L4D_IsInIntro()) return true;
    int camera = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
    if (camera <= MaxClients || !IsValidEntity(camera)) return false;
    char classname[64];
    GetEntityClassname(camera, classname, sizeof(classname));
    return StrContains(classname, "point_viewcontrol") == 0
    || StrEqual(classname, "point_deathfall_camera");
}
bool StartArea_PhysicallySafe(int client)
{
    return (GetEntityFlags(client) & FL_ONGROUND) != 0
    && GetEntProp(client, Prop_Send, "m_nWaterLevel") < 2
    && !GetEntProp(client, Prop_Send, "m_isIncapacitated")
    && !GetEntProp(client, Prop_Send, "m_isHangingFromLedge");
}
void StartArea_CountBoundaryTeleport(int client)
{
    if (!g_startBoundary[client] || g_startCounted[client]) return;
    g_startCounted[client] = true;
    if (g_startInput[client])
    {
        g_startLoopCount[client] = 0;
        return;
    }
    float now = GetEngineTime();
    int count;
    for (int i = 0; i < g_startLoopCount[client]; i++)
        if (now - g_startLoopTimes[client][i] <= 5.0)
            g_startLoopTimes[client][count++] = g_startLoopTimes[client][i];
    if (count < 3) g_startLoopTimes[client][count++] = now;
    g_startLoopCount[client] = count;
    if (count >= 3)
    {
        g_startLimited[client] = true;
        StartArea_Notice(client);
    }
}
bool StartArea_AllFinished()
{
    int survivors;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        survivors++;
        if (g_startReturn[client] != StartDone) return false;
    }
    return survivors > 0;
}
void StartArea_FreezeLanded()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsReadySurvivor(client)) continue;
        bool grounded = !StartArea_IntroControlled(client)
        && StartArea_PhysicallySafe(client);
        if (g_startReturn[client] == StartDone && grounded) SetReadyFrozen(client, true);
        else if (GetEntityMoveType(client) == MOVETYPE_NONE) SetReadyFrozen(client, false);
    }
}
void StartArea_ClearRequest(int client)
{
    g_startReturn[client] = StartIdle;
    g_startBoundary[client] = false;
    g_startCounted[client] = false;
    g_startNotify[client] = false;
}
void StartArea_ResetClient(int client)
{
    StartArea_ClearRequest(client);
    g_startLimited[client] = false;
    g_startInput[client] = false;
    g_startLoopCount[client] = 0;
    g_startNextNotice[client] = 0.0;
}
void StartArea_CancelRequests()
{
    g_startEpoch++;
    g_startPlacement = false;
    for (int c = 1; c<=MaxClients; c++)
    {
        StartArea_ClearRequest(c);
        g_startLimited[c] = false;
        g_startLoopCount[c] = 0;
    }
}
void StartArea_ResetRound()
{
    StartArea_CancelRequests();
    g_startIntroPositions = false;
    for (int c = 1; c<=MaxClients; c++)StartArea_ResetClient(c);
}
void StartArea_ResetMap()
{
    g_readyWarp = true;
}
public void L4D_OnForceSurvivorPositions_Pre()
{
    g_startIntroPositions = true;
}
public void L4D_OnReleaseSurvivorPositions()
{
    g_startIntroPositions = false;
}
void StartArea_ObserveInput(int client, int buttons, const float velocity[3])
{
    g_startInput[client] = (buttons & (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT|IN_JUMP|IN_DUCK|IN_LEFT|IN_RIGHT))!=0 || velocity[0]!=0.0 || velocity[1]!=0.0 || velocity[2]!=0.0;
    if (g_startInput[client])g_startLoopCount[client] = 0;
}
void StartArea_Notice(int client)
{
    if (GetEngineTime()<g_startNextNotice[client])return;
    g_startNextNotice[client] = GetEngineTime()+30.0;
    LogMessage("[Ready start] client=%N reason=input-free boundary loop", client);
    if (!IsFakeClient(client))PrintToChat(client, "%t", "ReadyStartLoop");
}
void StartArea_RequestReturn(int client, bool notify = false, bool boundary = false)
{
    if (!IsReadySurvivor(client))return;
    if (boundary && (!g_readyWarp || StartArea_FreeNoclip(client) || g_startLimited[client] || g_startPlacement || g_countdownTimer!=null))return;
    if (g_startReturn[client]==StartRequested)return;
    StartArea_ClearRequest(client);
    g_startBoundary[client] = boundary;
    g_startNotify[client] = notify;
    g_startRequestedAt[client] = GetEngineTime();
    g_startReturn[client] = StartRequested;
}
void StartArea_Tick()
{
    for (int c = 1; c<=MaxClients; c++)
    {
        if (!IsReadySurvivor(c))continue;
        if (!g_startPlacement && g_countdownTimer==null && StartArea_PhysicallySafe(c) && L4D_IsInFirstCheckpoint(c))
        {
            g_startLimited[c] = false;
        }
        if ((g_startPlacement || g_countdownTimer!=null) && g_startReturn[c]==StartIdle)StartArea_RequestReturn(c);
        if (g_startReturn[c]!=StartRequested)continue;
        if (g_readyWarp && StartArea_IntroControlled(c))
        {
            if (GetEngineTime()-g_startRequestedAt[c]<3.0)continue;
            LogMessage("[Ready start] client=%N native warp skipped: intro timeout", c);
        }
        else if (g_readyWarp)
        {
            SetReadyFrozen(c, false);
            if (GetEntProp(c, Prop_Send, "m_isHangingFromLedge"))L4D_ReviveSurvivor(c);
            int flags = GetCommandFlags("warp_to_start_area");
            SetCommandFlags("warp_to_start_area", flags & ~FCVAR_CHEAT);
            FakeClientCommand(c, "warp_to_start_area");
            SetCommandFlags("warp_to_start_area", flags);
            if (!IsReadySurvivor(c))continue;
            float velocity[3];
            TeleportEntity(c, NULL_VECTOR, NULL_VECTOR, velocity);
            SetEntPropFloat(c, Prop_Send, "m_flFallVelocity", 0.0);
            StartArea_CountBoundaryTeleport(c);
            CreateTimer(1.0, StartArea_CheckLanding, GetClientSerial(c), TIMER_FLAG_NO_MAPCHANGE);
        }
        if (!g_readyWarp && !g_startBoundary[c]) SetReadyFrozen(c, false);
        g_startReturn[c] = StartDone;
        if (g_startNotify[c] && g_readyWarp)EmitSoundToClient(c, "ui/beep_error01.wav");
    }
    if (g_countdownTimer!=null)StartArea_FreezeLanded();
}
public Action CommandReadyWarp(int client, int args)
{
    bool enabled = !g_readyWarp;
    if (args>0)
    {
        char arg[16];
        GetCmdArg(1, arg, sizeof(arg));
        if (StrEqual(arg, "on", false))enabled = true;
        else if (StrEqual(arg, "off", false))enabled = false;
        else
        {
            ReplyToCommand(client, "!readywarp [on|off]");
            return Plugin_Handled;
        }
    }
    g_readyWarp = enabled;
    if (!enabled)for (int c = 1; c<=MaxClients; c++)
    {
        g_startLimited[c] = false;
        g_startLoopCount[c] = 0;
        // Pending requests complete without teleporting on the next tick.
    }
    char map[128];
    GetCurrentMap(map, sizeof(map));
    LogMessage("[Ready] admin=%L map=%s warp=%s%s", client, map, enabled?"on":"off", enabled?"":"; 管理员关闭了归位传送，需要检查本关是否需要独立修复");
    ReplyToCommand(client, "%t", enabled?"ReadyWarpOn":"ReadyWarpOff");
    return Plugin_Handled;
}
public Action StartArea_CheckLanding(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (!IsReadySurvivor(client) || !g_readyPhase) return Plugin_Stop;
    if (!StartArea_PhysicallySafe(client))
    {
        char map[128];
        float pos[3];
        GetCurrentMap(map, sizeof(map));
        GetClientAbsOrigin(client, pos);
        LogMessage("[Ready start] map=%s client=%N native return not grounded/safe after 1s; pos=(%.1f %.1f %.1f) ground=%d water=%d move=%d", map, client, pos[0], pos[1], pos[2], GetEntPropEnt(client, Prop_Send, "m_hGroundEntity"), GetEntProp(client, Prop_Send, "m_nWaterLevel"), GetEntityMoveType(client));
    }
    return Plugin_Stop;
}

public void StartArea_PlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_readyPhase) return;
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));
    if (!player || !bot) return;
    bool toPlayer = StrEqual(name, "bot_player_replace");
    int source = toPlayer ? bot : player;
    int target = toPlayer ? player : bot;
    bool limited = g_startLimited[source];
    StartArea_ResetClient(target);
    g_startLimited[target] = limited;
    StartArea_ResetClient(source);
}
