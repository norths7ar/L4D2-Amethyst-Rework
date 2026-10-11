#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name = "SMG Reload Control",
    author = "norths7ar",
    description = "Controls SMG reload durations through weapon attributes.",
    version = "1.1.0"
};

ConVar g_cvReloadDuration;
ConVar g_cvSilencedReloadDuration;
ConVar g_cvMp5ReloadDuration;

public void OnPluginStart()
{
    g_cvReloadDuration = CreateConVar("smg_reload_duration", "1.4", "SMG reload duration for the active profile.", FCVAR_DONTRECORD, true, 0.1);
    g_cvSilencedReloadDuration = CreateConVar("smg_silenced_reload_duration", "1.5", "Silenced SMG reload duration for the active profile.", FCVAR_DONTRECORD, true, 0.1);
    g_cvMp5ReloadDuration = CreateConVar("smg_mp5_reload_duration", "1.45", "MP5 reload duration for the active profile.", FCVAR_DONTRECORD, true, 0.1);
    HookConVarChange(g_cvMp5ReloadDuration, ConVarChanged_Reload);
    HookConVarChange(g_cvReloadDuration, ConVarChanged_Reload);
    HookConVarChange(g_cvSilencedReloadDuration, ConVarChanged_Reload);
}

public void OnConfigsExecuted()
{
    ApplyReloadDurations();
}

void ConVarChanged_Reload(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ApplyReloadDurations();
}

void ApplyReloadDurations()
{
    if (GetCommandFlags("sm_weapon") == INVALID_FCVAR_FLAGS)
    {
        LogError("[SMG Reload Control] Required server command does not exist: sm_weapon.");
        return;
    }

    ServerCommand("sm_weapon smg reloadduration %.6f", g_cvReloadDuration.FloatValue);
    ServerCommand("sm_weapon smg_silenced reloadduration %.6f", g_cvSilencedReloadDuration.FloatValue);
    ServerCommand("sm_weapon smg_mp5 reloadduration %.6f", g_cvMp5ReloadDuration.FloatValue);
}
