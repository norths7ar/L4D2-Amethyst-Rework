#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sourcescramble>

public Plugin myinfo =
{
    name = "SI bile-neutral targeting",
    author = "norths7ar",
    description = "Removes bile-only victim retention without replacing engine target selection.",
    version = "1.0.0"
};

static const char PATCH_NAMES[][] = {
    "ChooseVictim", "BoomerContact", "ChargerContact", "HunterContact",
    "JockeyContact", "SmokerContact", "TankContact"
};
MemoryPatch g_patches[sizeof(PATCH_NAMES)];
int g_enabledCount;
ConVar g_neutral;

public void OnPluginStart()
{
    GameData data = new GameData("si_targeting");
    if (data == null) SetFailState("Missing si_targeting gamedata.");
    if (data.GetOffset("SupportedPlatform") != 1)
    {
        delete data;
        SetFailState("si_targeting currently requires the verified 32-bit Linux L4D2 server build.");
    }
    // Validate every site before changing any instruction. Engine updates or
    // overlapping patches must fail visibly, never leave a partial policy.
    for (int i = 0; i < sizeof(PATCH_NAMES); i++)
    {
        g_patches[i] = MemoryPatch.CreateFromConf(data, PATCH_NAMES[i]);
        if (g_patches[i] == null || !g_patches[i].Validate())
        {
            delete data;
            SetFailState("Bile retention patch validation failed: %s", PATCH_NAMES[i]);
        }
    }
    delete data;
    g_neutral = CreateConVar("si_bile_neutral", "0", "Ignore bile-only victim retention for SI and Tank; preserve actual bile effects.", _, true, 0.0, true, 1.0);
    g_neutral.AddChangeHook(OnNeutralChanged);
    ApplyPolicy();
}

public void OnNeutralChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    ApplyPolicy();
}

void ApplyPolicy()
{
    if (!g_neutral.BoolValue)
    {
        RestorePolicy();
        return;
    }
    if (g_enabledCount != 0) return;
    for (int i = 0; i < sizeof(PATCH_NAMES); i++)
    {
        if (!g_patches[i].Enable())
        {
            RestorePolicy();
            SetFailState("Could not enable bile retention patch: %s", PATCH_NAMES[i]);
        }
        g_enabledCount++;
    }
}

void RestorePolicy()
{
    while (g_enabledCount > 0) g_patches[--g_enabledCount].Disable();
}

public void OnPluginEnd()
{
    RestorePolicy();
}
