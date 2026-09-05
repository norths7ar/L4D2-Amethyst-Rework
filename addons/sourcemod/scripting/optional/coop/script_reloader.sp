#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

ConVar g_cvFilename;
GlobalForward g_fwdReloaded;

public Plugin myinfo =
{
    name = "VScript Reloader",
    author = "海洋空氣, norths7ar",
    description = "Owns VScript reload requests and publishes their completion.",
    version = "1.1.0",
    url = "https://github.com/Sglight/L4D2-AstMod-Scriptings/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax)
{
    RegPluginLibrary("script_reloader");
    CreateNative("VScript_Reload", Native_Reload);
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("script_reloader.phrases");
    g_cvFilename = CreateConVar("sm_vscript_filename", "", "Gamemode VScript filename.");
    RegConsoleCmd("sm_reloadscript", Command_Reload, "Reload the configured VScript file.");
    HookConVarChange(g_cvFilename, OnFilenameChange);
    g_fwdReloaded = new GlobalForward("VScript_OnReloaded", ET_Ignore, Param_String, Param_Cell);
}

public void OnPluginEnd()
{
    delete g_fwdReloaded;
}

public any Native_Reload(Handle plugin, int numParams)
{
    char filename[PLATFORM_MAX_PATH];
    if (numParams >= 1)
    {
        GetNativeString(1, filename, sizeof(filename));
    }
    ResolveFilename(filename, sizeof(filename));
    return ReloadScript(filename);
}

public Action Command_Reload(int client, int args)
{
    if (args > 1)
    {
        ReplyToCommand(client, "[SM] %t", "Usage");
        return Plugin_Handled;
    }

    char filename[PLATFORM_MAX_PATH];
    if (args == 1)
    {
        GetCmdArg(1, filename, sizeof(filename));
    }
    ResolveFilename(filename, sizeof(filename));

    if (!ReloadScript(filename))
    {
        ReplyToCommand(client, "[SM] %t", "ReloadFailed", filename);
    }
    return Plugin_Handled;
}

public void OnFilenameChange(ConVar convar, const char[] oldValue, const char[] newValue)
{
    char filename[PLATFORM_MAX_PATH];
    strcopy(filename, sizeof(filename), newValue);
    ResolveFilename(filename, sizeof(filename));
    ReloadScript(filename);
}

void ResolveFilename(char[] filename, int maxLength)
{
    if (filename[0] == '\0')
    {
        g_cvFilename.GetString(filename, maxLength);
    }
}

bool ReloadScript(const char[] filename)
{
    bool success;
    int entity = CreateEntityByName("logic_script");
    if (entity != -1)
    {
        DispatchSpawn(entity);
        SetVariantString(filename);
        success = AcceptEntityInput(entity, "RunScriptFile");
        RemoveEdict(entity);
    }

    Call_StartForward(g_fwdReloaded);
    Call_PushString(filename);
    Call_PushCell(success);
    Call_Finish();
    return success;
}
