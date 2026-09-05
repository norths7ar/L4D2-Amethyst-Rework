#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

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
    name = "Profile Controller",
    author = "norths7ar",
    description = "Validates, selects, and applies declarative player-count profiles.",
    version = "0.4.0"
};

CachedProfile g_profiles[MAX_PROFILES + 1];
ArrayList g_defaultCvarNames;
ArrayList g_defaultCvarValues;
ConVar g_cvCurrentProfile;
ConVar g_cvForcedProfile;
ConVar g_cvProfileConfig;
GlobalForward g_fwdProfileApplied;
GlobalForward g_fwdProfilePreApply;
Handle g_hPlayerCountTimer;
Handle g_hPlayerTeamTimer;
int g_iCurrentProfile;
bool g_bProfilesLoaded;

public void OnPluginStart()
{
    LoadTranslations("profile_controller.phrases");
    CreateConVar("profile_controller_version", "0.4.0", "Profile Controller version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvCurrentProfile = CreateConVar("profile_current", "1", "Currently applied player profile.", FCVAR_NOTIFY, true, 1.0, true, 4.0);
    g_cvForcedProfile = CreateConVar("profile_forced", "0", "Force a profile; 0 follows human survivor count.", FCVAR_NOTIFY, true, 0.0, true, 4.0);
    g_cvProfileConfig = CreateConVar("profile_controller_config", "", "Path_SM-relative KeyValues profile configuration.", FCVAR_DONTRECORD);
    HookConVarChange(g_cvProfileConfig, OnProfileConfigChanged);

    RegServerCmd("sm_profile_reapply", Command_ReapplyProfile);
    RegAdminCmd("sm_profile_status", Command_ProfileStatus, ADMFLAG_CONFIG, "Show the active profile.");
    RegAdminCmd("sm_profile_force", Command_ForceProfile, ADMFLAG_CONFIG, "Force profile 1-4, or 0 for automatic selection.");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    g_fwdProfileApplied = new GlobalForward("ProfileController_OnProfileApplied", ET_Ignore, Param_Cell);
    g_fwdProfilePreApply = new GlobalForward("ProfileController_OnProfilePreApply", ET_Ignore, Param_Cell);
    RegPluginLibrary("profile_controller");
    CreateNative("ProfileController_GetCurrentProfile", Native_GetCurrentProfile);
    CreateNative("ProfileController_Reapply", Native_Reapply);
    CreateNative("ProfileController_GetDefaultValue", Native_GetDefaultValue);
}

public void OnConfigsExecuted()
{
    TryInitializeProfiles();
}

public void OnProfileConfigChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    TryInitializeProfiles();
}

bool TryInitializeProfiles()
{
    if (!g_bProfilesLoaded)
    {
        char configPath[PLATFORM_MAX_PATH];
        g_cvProfileConfig.GetString(configPath, sizeof(configPath));
        if (configPath[0] == '\0')
        {
            return false;
        }

        char resolvedPath[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, resolvedPath, sizeof(resolvedPath), configPath);
        if (!FileExists(resolvedPath))
        {
            LogError("[Profile Controller] profile_controller_config points to missing file: %s (resolved %s).", configPath, resolvedPath);
            return false;
        }
        if (!LoadProfiles())
        {
            LogError("[Profile Controller] Could not load valid profiles from profile_controller_config=%s.", configPath);
            return false;
        }
    }

    if (g_hPlayerCountTimer == null)
    {
        ApplyEffectiveProfile("configs_executed", true);
        g_hPlayerCountTimer = CreateTimer(5.0, Timer_UpdateProfile, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
    return true;
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
    delete g_fwdProfilePreApply;
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
        "[%t] %t",
        "ProfileTag",
        "Status",
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
        ReplyToCommand(client, "[%t] %t", "ProfileTag", "Usage");
        return Plugin_Handled;
    }

    char argument[8];
    GetCmdArg(1, argument, sizeof(argument));
    int profile;
    if (StringToIntEx(argument, profile) != strlen(argument) || profile < 0 || profile > MAX_PROFILES)
    {
        ReplyToCommand(client, "[%t] %t", "ProfileTag", "InvalidProfile");
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
        LogError("[Profile Controller] Profile players_%d is not loaded.", profile);
        return false;
    }

    if (g_defaultCvarNames != null && g_defaultCvarValues != null)
    {
        for (int index = 0; index < g_defaultCvarNames.Length; index++)
        {
            char cvarName[64];
            g_defaultCvarNames.GetString(index, cvarName, sizeof(cvarName));
            if (FindConVar(cvarName) == null)
            {
                LogError("[Profile Controller] Required defaults cvar disappeared before apply: %s.", cvarName);
                return false;
            }
        }
    }

    for (int index = 0; index < cvarNames.Length; index++)
    {
        char cvarName[64];
        cvarNames.GetString(index, cvarName, sizeof(cvarName));
        if (FindConVar(cvarName) == null)
        {
            LogError("[Profile Controller] Required profile cvar disappeared before apply: %s.", cvarName);
            return false;
        }
    }

    Call_StartForward(g_fwdProfilePreApply);
    Call_PushCell(profile);
    Call_Finish();

    if (g_defaultCvarNames != null && g_defaultCvarValues != null)
    {
        for (int index = 0; index < g_defaultCvarNames.Length; index++)
        {
            char cvarName[64];
            char cvarValue[64];
            g_defaultCvarNames.GetString(index, cvarName, sizeof(cvarName));
            g_defaultCvarValues.GetString(index, cvarValue, sizeof(cvarValue));
            FindConVar(cvarName).SetString(cvarValue);
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

    LogMessage("[Profile Controller] Applied players_%d (%s), reason=%s, cvars=%d.", profile, g_profiles[profile].label, reason, cvarNames.Length);
    PrintToChatAll("\x04[%t]\x01 %t", "ProfileTag", "Changed", g_profiles[profile].label);
    return true;
}

public int Native_GetCurrentProfile(Handle plugin, int numParams)
{
    return g_iCurrentProfile;
}

public int Native_GetDefaultValue(Handle plugin, int numParams)
{
    if (!g_bProfilesLoaded || g_iCurrentProfile < 1 || g_iCurrentProfile > MAX_PROFILES) return false;
    char name[64], value[64];
    GetNativeString(1, name, sizeof(name));
    // Profile-specific values take precedence over the shared defaults, as during apply.
    int index = g_profiles[g_iCurrentProfile].cvarNames.FindString(name);
    if (index >= 0) g_profiles[g_iCurrentProfile].cvarValues.GetString(index, value, sizeof(value));
    else
    {
        if (g_defaultCvarNames == null) return false;
        index = g_defaultCvarNames.FindString(name);
        if (index < 0) return false;
        g_defaultCvarValues.GetString(index, value, sizeof(value));
    }
    SetNativeCellRef(2, view_as<int>(StringToFloat(value)));
    return true;
}

public int Native_Reapply(Handle plugin, int numParams)
{
    if (!g_bProfilesLoaded || g_iCurrentProfile < 1 || g_iCurrentProfile > MAX_PROFILES)
    {
        return false;
    }
    return ApplyProfile(g_iCurrentProfile, "native_reapply");
}

bool LoadProfiles()
{
    ClearProfiles();

    char path[PLATFORM_MAX_PATH];
    char configPath[PLATFORM_MAX_PATH];
    g_cvProfileConfig.GetString(configPath, sizeof(configPath));
    BuildPath(Path_SM, path, sizeof(path), configPath);
    KeyValues profiles = new KeyValues("Profiles");
    if (!profiles.ImportFromFile(path))
    {
        delete profiles;
        LogError("[Profile Controller] Could not load %s.", path);
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
            LogError("[Profile Controller] Missing profile section %s.", section);
            ClearProfiles();
            return false;
        }

        profiles.GetString("label", g_profiles[profile].label, sizeof(g_profiles[].label), "");
        if (g_profiles[profile].label[0] == '\0')
        {
            delete profiles;
            LogError("[Profile Controller] Missing label in %s.", section);
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

    profiles.Rewind();
    if (profiles.JumpToKey("defaults"))
    {
        g_defaultCvarNames = new ArrayList(ByteCountToCells(64));
        g_defaultCvarValues = new ArrayList(ByteCountToCells(64));
        if (!ReadProfileGroups(profiles, "defaults", g_defaultCvarNames, g_defaultCvarValues))
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
        LogError("[Profile Controller] Profile %s has no cvar groups.", section);
        return false;
    }

    do
    {
        if (!profiles.GotoFirstSubKey(false))
        {
            char group[64];
            profiles.GetSectionName(group, sizeof(group));
            LogError("[Profile Controller] Empty cvar group in %s: %s.", section, group);
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
                LogError("[Profile Controller] Invalid or duplicate cvar in %s: %s=%s.", section, cvarName, cvarValue);
                return false;
            }
            if (FindConVar(cvarName) == null)
            {
                LogError("[Profile Controller] Required profile cvar does not exist: %s.", cvarName);
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
    delete g_defaultCvarNames;
    delete g_defaultCvarValues;
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
