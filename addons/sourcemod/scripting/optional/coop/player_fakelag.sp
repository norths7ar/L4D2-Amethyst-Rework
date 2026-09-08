#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <custom_fakelag>

// ProdigySim custom_fakelag 1.0.0.0 wrapper, adapted for manual PVE use.
public Plugin myinfo =
{
    name = "Per-Player Fakelag",
    author = "ProdigySim, AstRedux maintainers",
    description = "Manual additional inbound packet latency; default zero.",
    version = "1.1.0",
    url = "https://github.com/ProdigySim/custom_fakelag"
};

ConVar g_maximum;

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    g_maximum = CreateConVar("sm_fakelag_max", "200", "手动追加延迟上限（毫秒）；不会自动给玩家追加延迟。", FCVAR_NONE, true, 0.0, true, 1000.0);
    g_maximum.AddChangeHook(MaximumChanged);
    RegConsoleCmd("sm_fakelag", CommandFakeLag, "!fakelag [毫秒]；管理员可用 !fakelag <玩家> <毫秒>");
    RegAdminCmd("sm_printlag", CommandPrintLag, ADMFLAG_CONFIG, "查询所有真人玩家的追加延迟");
    AutoExecConfig(true, "player_fakelag");
    ResetAll();
}

public void OnClientPutInServer(int client)
{
    if (!IsFakeClient(client)) CFakeLag_SetPlayerLatency(client, 0.0);
}

public void OnPluginEnd() { ResetAll(); }

void ResetAll()
{
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !IsFakeClient(client)) CFakeLag_SetPlayerLatency(client, 0.0);
}

public void MaximumChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client) && !IsFakeClient(client) && CFakeLag_GetPlayerLatency(client) > convar.FloatValue)
            CFakeLag_SetPlayerLatency(client, convar.FloatValue);
}

public Action CommandFakeLag(int client, int argc)
{
    int target = client;
    if (argc == 0 && client > 0 && IsClientInGame(client))
    {
        ReplyToCommand(client, "[延迟] 当前追加 %.0f 毫秒；!fakelag <毫秒> 设置，0 关闭。", CFakeLag_GetPlayerLatency(client));
        return Plugin_Handled;
    }
    if (argc < 1 || argc > 2 || (client == 0 && argc != 2))
    {
        ReplyToCommand(client, "[延迟] 用法：!fakelag <毫秒>；管理员：!fakelag <玩家> <毫秒>");
        return Plugin_Handled;
    }
    char input[64];
    if (argc == 2)
    {
        if (!CheckCommandAccess(client, "sm_fakelag_target", ADMFLAG_CONFIG))
        {
            ReplyToCommand(client, "[延迟] 只有管理员可以修改其他玩家的追加延迟。");
            return Plugin_Handled;
        }
        GetCmdArg(1, input, sizeof(input));
        target = FindTarget(client, input, true);
    }
    if (target <= 0 || !IsClientInGame(target) || IsFakeClient(target)) return Plugin_Handled;
    GetCmdArg(argc, input, sizeof(input));
    int amount;
    int consumed = StringToIntEx(input, amount);
    if (consumed == 0 || consumed != strlen(input) || amount < 0 || amount > g_maximum.IntValue)
    {
        ReplyToCommand(client, "[延迟] 请输入 0 至 %d 的整数毫秒值。", g_maximum.IntValue);
        return Plugin_Handled;
    }
    CFakeLag_SetPlayerLatency(target, float(amount));
    ReplyToCommand(client, "[延迟] %N 的追加延迟设为 %d 毫秒。", target, amount);
    if (target != client) PrintToChat(target, "[延迟] 管理员将你的追加延迟设为 %d 毫秒。", amount);
    return Plugin_Handled;
}

public Action CommandPrintLag(int client, int argc)
{
    for (int target = 1; target <= MaxClients; target++)
        if (IsClientInGame(target) && !IsFakeClient(target))
            ReplyToCommand(client, "[延迟] %N：追加 %.0f 毫秒", target, CFakeLag_GetPlayerLatency(target));
    return Plugin_Handled;
}
