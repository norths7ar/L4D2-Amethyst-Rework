#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PROFILE_CONFIG "configs/astredux_profiles.cfg"
#define MAX_PROFILES 4
#define TEAM_SURVIVOR 2

enum struct CachedProfile
{
    char label[32];
    ArrayList cvarNames;
    ArrayList cvarValues;
}

public Plugin myinfo =
{
    name = "AstRedux Profile Controller",
    author = "norths7ar",
    description = "Validates, selects, and applies declarative AstRedux player-count profiles.",
    version = "0.3.0"
};

CachedProfile g_profiles[MAX_PROFILES + 1];
ConVar g_cvCurrentProfile;
ConVar g_cvForcedProfile;
GlobalForward g_fwdProfileApplied;
Handle g_hPlayerCountTimer;
Handle g_hPlayerTeamTimer;
int g_iCurrentProfile;
bool g_bProfilesLoaded;

public void OnPluginStart()
{
    CreateConVar("astredux_profile_version", "0.3.0", "AstRedux profile controller version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvCurrentProfile = CreateConVar("astredux_profile_current", "1", "Currently applied AstRedux player profile.", FCVAR_NOTIFY, true, 1.0, true, 4.0);
    g_cvForcedProfile = CreateConVar("astredux_profile_forced", "0", "Force an AstRedux profile; 0 follows human survivor count.", FCVAR_NOTIFY, true, 0.0, true, 4.0);

    RegServerCmd("sm_astredux_profile_reapply", Command_ReapplyProfile);
    RegAdminCmd("sm_astredux_profile_status", Command_ProfileStatus, ADMFLAG_CONFIG, "Show the active AstRedux profile.");
    RegAdminCmd("sm_astredux_profile_force", Command_ForceProfile, ADMFLAG_CONFIG, "Force profile 1-4, or 0 for automatic selection.");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    g_fwdProfileApplied = new GlobalForward("AstRedux_OnProfileApplied", ET_Ignore, Param_Cell);
}

public void OnConfigsExecuted()
{
    if (!LoadProfiles())
    {
        SetFailState("Could not load valid AstRedux profiles from %s.", PROFILE_CONFIG);
        return;
    }

    ApplyEffectiveProfile("configs_executed", true);
    if (g_hPlayerCountTimer == null)
    {
        g_hPlayerCountTimer = CreateTimer(5.0, Timer_UpdateProfile, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnMapEnd()
{
    g_hPlayerCountTimer = null;
    g_hPlayerTeamTimer = null;
    g_iCurrentProfile = 0;
}

public void OnPluginEnd()
{
    ClearProfiles();
    delete g_fwdProfileApplied;
}

public Action Timer_UpdateProfile(Handle timer)
{
    if (timer != g_hPlayerCountTimer)
    {
        return Plugin_Stop;
    }

    ApplyEffectiveProfile("player_count", false);
    return Plugin_Continue;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    delete g_hPlayerTeamTimer;
    g_hPlayerTeamTimer = CreateTimer(0.2, Timer_DelayedProfileCheck, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelayedProfileCheck(Handle timer)
{
    if (timer != g_hPlayerTeamTimer)
    {
        return Plugin_Stop;
    }

    g_hPlayerTeamTimer = null;
    ApplyEffectiveProfile("player_team", false);
    return Plugin_Stop;
}

public Action Command_ReapplyProfile(int args)
{
    ApplyEffectiveProfile("manual_reapply", true);
    return Plugin_Handled;
}

public Action Command_ProfileStatus(int client, int args)
{
    char label[32] = "unavailable";
    if (g_iCurrentProfile >= 1 && g_iCurrentProfile <= MAX_PROFILES)
    {
        strcopy(label, sizeof(label), g_profiles[g_iCurrentProfile].label);
    }

    ReplyToCommand(
        client,
        "[AstRedux] profile=%d (%s) forced=%d humans=%d",
        g_iCurrentProfile,
        label,
        g_cvForcedProfile.IntValue,
        CountHumanSurvivors()
    );
    return Plugin_Handled;
}

public Action Command_ForceProfile(int client, int args)
{
    if (args != 1)
    {
        ReplyToCommand(client, "[AstRedux] Usage: sm_astredux_profile_force <0-4>");
        return Plugin_Handled;
    }

    char argument[8];
    GetCmdArg(1, argument, sizeof(argument));
    int profile;
    if (StringToIntEx(argument, profile) != strlen(argument) || profile < 0 || profile > MAX_PROFILES)
    {
        ReplyToCommand(client, "[AstRedux] Profile must be 0-4; 0 restores automatic selection.");
        return Plugin_Handled;
    }

    g_cvForcedProfile.IntValue = profile;
    ApplyEffectiveProfile("manual_force", true);
    return Plugin_Handled;
}

void ApplyEffectiveProfile(const char[] reason, bool force)
{
    if (!g_bProfilesLoaded)
    {
        return;
    }

    int profile = g_cvForcedProfile.IntValue;
    if (profile == 0)
    {
        profile = CountHumanSurvivors();
        if (profile < 1)
        {
            profile = 1;
        }
        else if (profile > MAX_PROFILES)
        {
            profile = MAX_PROFILES;
        }
    }

    if (!force && profile == g_iCurrentProfile)
    {
        return;
    }

    ApplyProfile(profile, reason);
}

bool ApplyProfile(int profile, const char[] reason)
{
    ArrayList cvarNames = g_profiles[profile].cvarNames;
    ArrayList cvarValues = g_profiles[profile].cvarValues;
    if (cvarNames == null || cvarValues == null || cvarNames.Length == 0)
    {
        LogError("[AstRedux] Profile players_%d is not loaded.", profile);
        return false;
    }

    for (int index = 0; index < cvarNames.Length; index++)
    {
        char cvarName[64];
        cvarNames.GetString(index, cvarName, sizeof(cvarName));
        if (FindConVar(cvarName) == null)
        {
            LogError("[AstRedux] Required profile cvar disappeared before apply: %s.", cvarName);
            return false;
        }
    }

    for (int index = 0; index < cvarNames.Length; index++)
    {
        char cvarName[64];
        char cvarValue[64];
        cvarNames.GetString(index, cvarName, sizeof(cvarName));
        cvarValues.GetString(index, cvarValue, sizeof(cvarValue));
        FindConVar(cvarName).SetString(cvarValue);
    }

    g_iCurrentProfile = profile;
    g_cvCurrentProfile.IntValue = profile;

    Call_StartForward(g_fwdProfileApplied);
    Call_PushCell(profile);
    Call_Finish();

    LogMessage("[AstRedux] Applied players_%d (%s), reason=%s, cvars=%d.", profile, g_profiles[profile].label, reason, cvarNames.Length);
    PrintToChatAll("\x04[AstRedux]\x01 Profile changed to \x03%s\x01.", g_profiles[profile].label);
    return true;
}

bool LoadProfiles()
{
    ClearProfiles();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), PROFILE_CONFIG);
    KeyValues profiles = new KeyValues("AstReduxProfiles");
    if (!profiles.ImportFromFile(path))
    {
        delete profiles;
        LogError("[AstRedux] Could not load %s.", path);
        return false;
    }

    for (int profile = 1; profile <= MAX_PROFILES; profile++)
    {
        profiles.Rewind();
        char section[32];
        FormatEx(section, sizeof(section), "players_%d", profile);
        if (!profiles.JumpToKey(section))
        {
            delete profiles;
            LogError("[AstRedux] Missing profile section %s.", section);
            ClearProfiles();
            return false;
        }

        profiles.GetString("label", g_profiles[profile].label, sizeof(g_profiles[].label), "");
        if (g_profiles[profile].label[0] == '\0')
        {
            delete profiles;
            LogError("[AstRedux] Missing label in %s.", section);
            ClearProfiles();
            return false;
        }

        g_profiles[profile].cvarNames = new ArrayList(ByteCountToCells(64));
        g_profiles[profile].cvarValues = new ArrayList(ByteCountToCells(64));
        if (!ReadProfileGroups(profiles, section, g_profiles[profile].cvarNames, g_profiles[profile].cvarValues))
        {
            delete profiles;
            ClearProfiles();
            return false;
        }
    }

    delete profiles;
    g_bProfilesLoaded = true;
    return true;
}

bool ReadProfileGroups(KeyValues profiles, const char[] section, ArrayList cvarNames, ArrayList cvarValues)
{
    if (!profiles.GotoFirstSubKey())
    {
        LogError("[AstRedux] Profile %s has no cvar groups.", section);
        return false;
    }

    do
    {
        if (!profiles.GotoFirstSubKey(false))
        {
            char group[64];
            profiles.GetSectionName(group, sizeof(group));
            LogError("[AstRedux] Empty cvar group in %s: %s.", section, group);
            return false;
        }

        do
        {
            char cvarName[64];
            char cvarValue[64];
            profiles.GetSectionName(cvarName, sizeof(cvarName));
            profiles.GetString(NULL_STRING, cvarValue, sizeof(cvarValue), "");
            if (!IsSafeCvarToken(cvarName) || !IsSafeNumericToken(cvarValue) || cvarNames.FindString(cvarName) != -1)
            {
                LogError("[AstRedux] Invalid or duplicate cvar in %s: %s=%s.", section, cvarName, cvarValue);
                return false;
            }
            if (FindConVar(cvarName) == null)
            {
                LogError("[AstRedux] Required profile cvar does not exist: %s.", cvarName);
                return false;
            }
            cvarNames.PushString(cvarName);
            cvarValues.PushString(cvarValue);
        }
        while (profiles.GotoNextKey(false));

        profiles.GoBack();
    }
    while (profiles.GotoNextKey());

    return cvarNames.Length > 0;
}

void ClearProfiles()
{
    for (int profile = 1; profile <= MAX_PROFILES; profile++)
    {
        delete g_profiles[profile].cvarNames;
        delete g_profiles[profile].cvarValues;
        g_profiles[profile].label[0] = '\0';
    }
    g_bProfilesLoaded = false;
}

int CountHumanSurvivors()
{
    int count;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR && !IsFakeClient(client) && !IsClientInKickQueue(client))
        {
            count++;
        }
    }
    return count;
}

bool IsSafeCvarToken(const char[] value)
{
    if (value[0] == '\0')
    {
        return false;
    }

    for (int index = 0; value[index] != '\0'; index++)
    {
        if (!IsCharAlpha(value[index]) && !IsCharNumeric(value[index]) && value[index] != '_')
        {
            return false;
        }
    }
    return true;
}

bool IsSafeNumericToken(const char[] value)
{
    float parsedValue;
    return value[0] != '\0' && StringToFloatEx(value, parsedValue) == strlen(value);
}
