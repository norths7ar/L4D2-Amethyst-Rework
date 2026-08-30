#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PROFILE_CONFIG "configs/astredux_profiles.cfg"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

enum struct ProfileData
{
    char label[32];
    int tankHealth;
    float tankMeleeDamage;
    bool noWitch;
    bool autowipe;
    float smgReloadDuration;
    float silencedSmgReloadDuration;
    int waveSize;
    float waveInterval;
    int hunterLimit;
    int smokerLimit;
    int boomerLimit;
    int spitterLimit;
    int jockeyLimit;
    int chargerLimit;
    int preferredDirection;
}

public Plugin myinfo =
{
    name = "AstRedux Profile Controller",
    author = "norths7ar",
    description = "Applies declarative AstRedux player-count profiles.",
    version = "0.2.0"
};

ConVar g_cvCurrentProfile;
ConVar g_cvForcedProfile;
ConVar g_cvTankHealth;
ConVar g_cvTankMeleeDamage;
ConVar g_cvTankEngineScale;
ConVar g_cvNoWitch;
ConVar g_cvSIAutoWipe;
ConVar g_cvHunterLimit;
ConVar g_cvSmokerLimit;
ConVar g_cvBoomerLimit;
ConVar g_cvSpitterLimit;
ConVar g_cvJockeyLimit;
ConVar g_cvChargerLimit;
ConVar g_cvPreferredDirection;

Handle g_hPlayerCountTimer;
int g_iCurrentProfile;
int g_iTankHealth = 1200;
float g_fTankMeleeDamage = 300.0;
bool g_bNoWitch = true;

public void OnPluginStart()
{
    CreateConVar("astredux_profile_version", "0.2.0", "AstRedux profile controller version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvCurrentProfile = CreateConVar("astredux_profile_current", "1", "Currently applied AstRedux player profile.", FCVAR_NOTIFY, true, 1.0, true, 4.0);
    g_cvForcedProfile = CreateConVar("astredux_profile_forced", "0", "Force an AstRedux profile; 0 follows human survivor count.", FCVAR_NOTIFY, true, 0.0, true, 4.0);
    g_cvTankHealth = CreateConVar("astredux_tank_spawn_health", "1200", "Final health assigned to newly spawned Tanks.", FCVAR_NOTIFY, true, 1.0);
    g_cvTankMeleeDamage = CreateConVar("astredux_tank_melee_damage", "300.0", "Fixed damage dealt to Tanks by weapon_melee attacks.", FCVAR_NOTIFY, true, 1.0);
    g_cvTankEngineScale = CreateConVar("astredux_tank_engine_scale", "1.5", "Current mutation's engine Tank health multiplier.", FCVAR_DONTRECORD, true, 0.1);
    g_cvNoWitch = CreateConVar("astredux_no_witch", "1", "Block future Witch spawns for the active profile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvSIAutoWipe = CreateConVar("astredux_autowipe_enable", "0", "Enable the AstRedux AutoWipe adapter.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvHunterLimit = CreateConVar("astredux_si_hunter_limit", "1", "Hunter limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvSmokerLimit = CreateConVar("astredux_si_smoker_limit", "1", "Smoker limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvBoomerLimit = CreateConVar("astredux_si_boomer_limit", "0", "Boomer limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvSpitterLimit = CreateConVar("astredux_si_spitter_limit", "0", "Spitter limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvJockeyLimit = CreateConVar("astredux_si_jockey_limit", "1", "Jockey limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvChargerLimit = CreateConVar("astredux_si_charger_limit", "1", "Charger limit for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);
    g_cvPreferredDirection = CreateConVar("astredux_si_preferred_direction", "4", "Preferred special direction for the AstRedux VScript.", FCVAR_DONTRECORD, true, 0.0);

    RegServerCmd("sm_astredux_profile_reapply", Command_ReapplyProfile);
    RegAdminCmd("sm_astredux_profile_status", Command_ProfileStatus, ADMFLAG_CONFIG, "Show the active AstRedux profile.");
    RegAdminCmd("sm_astredux_profile_force", Command_ForceProfile, ADMFLAG_CONFIG, "Force profile 1-4, or 0 for automatic selection.");

    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_Post);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
        }
    }
}

public void OnConfigsExecuted()
{
    ApplyEffectiveProfile("configs_executed", true);

    if (g_hPlayerCountTimer == null)
    {
        g_hPlayerCountTimer = CreateTimer(1.0, Timer_UpdateProfile, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnMapEnd()
{
    g_hPlayerCountTimer = null;
    g_iCurrentProfile = 0;
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, Hook_TankMeleeDamage);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_bNoWitch)
    {
        return;
    }

    if (StrEqual(classname, "witch") || StrEqual(classname, "witch_bride"))
    {
        RequestFrame(Frame_RemoveWitch, EntIndexToEntRef(entity));
    }
}

public void Frame_RemoveWitch(any entityReference)
{
    int entity = EntRefToEntIndex(entityReference);
    if (g_bNoWitch && entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Kill");
    }
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
    CreateTimer(0.2, Timer_DelayedProfileCheck, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelayedProfileCheck(Handle timer)
{
    ApplyEffectiveProfile("player_team", false);
    return Plugin_Stop;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int tank = GetClientOfUserId(event.GetInt("userid"));
    if (tank > 0)
    {
        RequestFrame(Frame_ApplyTankHealth, GetClientUserId(tank));
    }
}

public void Frame_ApplyTankHealth(any userId)
{
    int tank = GetClientOfUserId(userId);
    if (tank <= 0 || !IsClientInGame(tank) || GetClientTeam(tank) != TEAM_INFECTED || GetEntProp(tank, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
    {
        return;
    }

    SetEntProp(tank, Prop_Data, "m_iMaxHealth", g_iTankHealth);
    SetEntityHealth(tank, g_iTankHealth);
}

public Action Hook_TankMeleeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (damage <= 0.0 || victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED || GetEntProp(victim, Prop_Send, "m_zombieClass") != ZOMBIECLASS_TANK)
    {
        return Plugin_Continue;
    }

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
    {
        return Plugin_Continue;
    }

    int weaponEntity = weapon;
    if (weaponEntity <= MaxClients || !IsValidEntity(weaponEntity))
    {
        weaponEntity = inflictor;
    }

    if (weaponEntity <= MaxClients || !IsValidEntity(weaponEntity))
    {
        return Plugin_Continue;
    }

    char classname[64];
    GetEntityClassname(weaponEntity, classname, sizeof(classname));
    if (!StrEqual(classname, "weapon_melee"))
    {
        return Plugin_Continue;
    }

    damage = g_fTankMeleeDamage;
    return Plugin_Changed;
}

public Action Command_ReapplyProfile(int args)
{
    ApplyEffectiveProfile("manual_reapply", true);
    return Plugin_Handled;
}

public Action Command_ProfileStatus(int client, int args)
{
    ReplyToCommand(
        client,
        "[AstRedux] profile=%d forced=%d humans=%d tank=%d melee=%.1f no_witch=%d autowipe=%d",
        g_iCurrentProfile,
        g_cvForcedProfile.IntValue,
        CountHumanSurvivors(),
        g_iTankHealth,
        g_fTankMeleeDamage,
        g_bNoWitch,
        g_cvSIAutoWipe.BoolValue
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
    int profile = StringToInt(argument);
    if (profile < 0 || profile > 4)
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
    int profile = g_cvForcedProfile.IntValue;
    if (profile == 0)
    {
        profile = CountHumanSurvivors();
        if (profile < 1)
        {
            profile = 1;
        }
        else if (profile > 4)
        {
            profile = 4;
        }
    }

    if (!force && profile == g_iCurrentProfile)
    {
        return;
    }

    ApplyProfile(profile, reason);
}

bool ApplyProfile(int players, const char[] reason)
{
    ProfileData profile;
    ArrayList cvarNames = new ArrayList(ByteCountToCells(64));
    ArrayList cvarValues = new ArrayList(ByteCountToCells(64));

    if (!LoadProfile(players, profile, cvarNames, cvarValues) || !ValidateCvars(cvarNames) || !ValidateRuntimeCvars())
    {
        delete cvarNames;
        delete cvarValues;
        LogError("[AstRedux] Profile players_%d was not applied.", players);
        return false;
    }

    for (int index = 0; index < cvarNames.Length; index++)
    {
        char cvarName[64];
        char cvarValue[64];
        cvarNames.GetString(index, cvarName, sizeof(cvarName));
        cvarValues.GetString(index, cvarValue, sizeof(cvarValue));
        ApplyCvar(cvarName, cvarValue);
    }

    g_iTankHealth = profile.tankHealth;
    g_fTankMeleeDamage = profile.tankMeleeDamage;
    g_bNoWitch = profile.noWitch;
    g_iCurrentProfile = players;

    g_cvTankHealth.IntValue = profile.tankHealth;
    g_cvTankMeleeDamage.FloatValue = profile.tankMeleeDamage;
    g_cvNoWitch.BoolValue = profile.noWitch;
    g_cvSIAutoWipe.BoolValue = profile.autowipe;
    g_cvHunterLimit.IntValue = profile.hunterLimit;
    g_cvSmokerLimit.IntValue = profile.smokerLimit;
    g_cvBoomerLimit.IntValue = profile.boomerLimit;
    g_cvSpitterLimit.IntValue = profile.spitterLimit;
    g_cvJockeyLimit.IntValue = profile.jockeyLimit;
    g_cvChargerLimit.IntValue = profile.chargerLimit;
    g_cvPreferredDirection.IntValue = profile.preferredDirection;

    SetExistingConVarFloat("ast_sitimer_new", profile.waveInterval);
    SetExistingConVarInt("ast_silimit_new", profile.waveSize);
    ApplyWeaponAttributes(profile);

    float engineScale = g_cvTankEngineScale.FloatValue;
    int engineTankHealth = RoundToNearest(float(profile.tankHealth) / engineScale);
    SetExistingConVarInt("z_tank_health", engineTankHealth);

    g_cvCurrentProfile.IntValue = players;
    ServerCommand("sm_reloadscript");

    LogMessage(
        "[AstRedux] Applied players_%d (%s), reason=%s, tank=%d, melee=%.1f, wave=%d/%.1fs.",
        players,
        profile.label,
        reason,
        profile.tankHealth,
        profile.tankMeleeDamage,
        profile.waveSize,
        profile.waveInterval
    );
    PrintToChatAll("\x04[AstRedux]\x01 Profile changed to \x03%s\x01: Tank %d HP, SI %d every %.1fs.", profile.label, profile.tankHealth, profile.waveSize, profile.waveInterval);

    delete cvarNames;
    delete cvarValues;
    return true;
}

bool LoadProfile(int players, ProfileData profile, ArrayList cvarNames, ArrayList cvarValues)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), PROFILE_CONFIG);

    KeyValues profiles = new KeyValues("AstReduxProfiles");
    if (!profiles.ImportFromFile(path))
    {
        delete profiles;
        LogError("[AstRedux] Could not load %s.", path);
        return false;
    }

    char section[32];
    FormatEx(section, sizeof(section), "players_%d", players);
    if (!profiles.JumpToKey(section))
    {
        delete profiles;
        LogError("[AstRedux] Missing profile section %s.", section);
        return false;
    }

    profiles.GetString("label", profile.label, sizeof(profile.label), "");

    if (!profiles.JumpToKey("tank"))
    {
        delete profiles;
        LogError("[AstRedux] Missing tank block in %s.", section);
        return false;
    }
    profile.tankHealth = profiles.GetNum("spawn_health", -1);
    profile.tankMeleeDamage = profiles.GetFloat("melee_damage", -1.0);
    profiles.GoBack();

    if (!profiles.JumpToKey("features"))
    {
        delete profiles;
        LogError("[AstRedux] Missing features block in %s.", section);
        return false;
    }
    profile.noWitch = profiles.GetNum("no_witch", -1) == 1;
    profile.autowipe = profiles.GetNum("autowipe", -1) == 1;
    profiles.GoBack();

    if (!profiles.JumpToKey("weapons"))
    {
        delete profiles;
        LogError("[AstRedux] Missing weapons block in %s.", section);
        return false;
    }
    profile.smgReloadDuration = profiles.GetFloat("smg_reload_duration", -1.0);
    profile.silencedSmgReloadDuration = profiles.GetFloat("smg_silenced_reload_duration", -1.0);
    profiles.GoBack();

    if (!profiles.JumpToKey("special_infected"))
    {
        delete profiles;
        LogError("[AstRedux] Missing special_infected block in %s.", section);
        return false;
    }
    profile.waveSize = profiles.GetNum("wave_size", -1);
    profile.waveInterval = profiles.GetFloat("wave_interval", -1.0);
    profile.hunterLimit = profiles.GetNum("hunter_limit", -1);
    profile.smokerLimit = profiles.GetNum("smoker_limit", -1);
    profile.boomerLimit = profiles.GetNum("boomer_limit", -1);
    profile.spitterLimit = profiles.GetNum("spitter_limit", -1);
    profile.jockeyLimit = profiles.GetNum("jockey_limit", -1);
    profile.chargerLimit = profiles.GetNum("charger_limit", -1);
    profile.preferredDirection = profiles.GetNum("preferred_direction", -1);
    profiles.GoBack();

    if (!ValidateProfileData(profile, section) || !profiles.JumpToKey("cvars") || !profiles.GotoFirstSubKey(false))
    {
        delete profiles;
        LogError("[AstRedux] Invalid profile data or missing cvars in %s.", section);
        return false;
    }

    do
    {
        char cvarName[64];
        char cvarValue[64];
        profiles.GetSectionName(cvarName, sizeof(cvarName));
        profiles.GetString(NULL_STRING, cvarValue, sizeof(cvarValue), "");
        if (!IsSafeCvarToken(cvarName) || !IsSafeNumericToken(cvarValue))
        {
            delete profiles;
            LogError("[AstRedux] Unsafe cvar entry in %s: %s=%s.", section, cvarName, cvarValue);
            return false;
        }
        cvarNames.PushString(cvarName);
        cvarValues.PushString(cvarValue);
    }
    while (profiles.GotoNextKey(false));

    delete profiles;
    return cvarNames.Length > 0;
}

bool ValidateProfileData(ProfileData profile, const char[] section)
{
    if (profile.label[0] == '\0' || profile.tankHealth <= 0 || profile.tankMeleeDamage <= 0.0 || profile.smgReloadDuration <= 0.0 || profile.silencedSmgReloadDuration <= 0.0 || profile.waveSize < 0 || profile.waveInterval < 0.0)
    {
        LogError("[AstRedux] Invalid core values in %s.", section);
        return false;
    }

    if (profile.hunterLimit < 0 || profile.smokerLimit < 0 || profile.boomerLimit < 0 || profile.spitterLimit < 0 || profile.jockeyLimit < 0 || profile.chargerLimit < 0 || profile.preferredDirection < 0)
    {
        LogError("[AstRedux] Invalid special infected limits in %s.", section);
        return false;
    }
    return true;
}

bool ValidateCvars(ArrayList cvarNames)
{
    for (int index = 0; index < cvarNames.Length; index++)
    {
        char cvarName[64];
        cvarNames.GetString(index, cvarName, sizeof(cvarName));
        if (FindConVar(cvarName) == null)
        {
            LogError("[AstRedux] Required profile cvar does not exist: %s.", cvarName);
            return false;
        }
    }
    return true;
}

bool ValidateRuntimeCvars()
{
    if (GetCommandFlags("sm_weapon") == INVALID_FCVAR_FLAGS)
    {
        LogError("[AstRedux] Required server command does not exist: sm_weapon.");
        return false;
    }

    static const char requiredCvars[][] =
    {
        "ast_sitimer_new",
        "ast_silimit_new",
        "z_tank_health"
    };

    for (int index = 0; index < sizeof(requiredCvars); index++)
    {
        if (FindConVar(requiredCvars[index]) == null)
        {
            LogError("[AstRedux] Required runtime cvar does not exist: %s.", requiredCvars[index]);
            return false;
        }
    }
    return true;
}

void ApplyWeaponAttributes(ProfileData profile)
{
    ServerCommand("sm_weapon smg reloadduration %.6f", profile.smgReloadDuration);
    ServerCommand("sm_weapon smg_silenced reloadduration %.6f", profile.silencedSmgReloadDuration);
}

void ApplyCvar(const char[] cvarName, const char[] cvarValue)
{
    ConVar cvar = FindConVar(cvarName);
    cvar.SetString(cvarValue);
}

void SetExistingConVarInt(const char[] name, int value)
{
    ConVar cvar = FindConVar(name);
    if (cvar == null)
    {
        LogError("[AstRedux] Required cvar does not exist: %s.", name);
        return;
    }
    cvar.IntValue = value;
}

void SetExistingConVarFloat(const char[] name, float value)
{
    ConVar cvar = FindConVar(name);
    if (cvar == null)
    {
        LogError("[AstRedux] Required cvar does not exist: %s.", name);
        return;
    }
    cvar.FloatValue = value;
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
    if (value[0] == '\0')
    {
        return false;
    }

    for (int index = 0; value[index] != '\0'; index++)
    {
        if (!IsCharNumeric(value[index]) && value[index] != '.' && value[index] != '-')
        {
            return false;
        }
    }
    return true;
}
