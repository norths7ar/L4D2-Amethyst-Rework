#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <chat-processor>
#define TAG_CONFIG "configs/chat_tags.cfg"
#define CUSTOM_BYTES 49
#define CUSTOM_ID "__custom"

Handle g_cookie, g_customCookie, g_banCookie;
ArrayList g_ids, g_names, g_values, g_selectable;
char g_selected[MAXPLAYERS + 1][64], g_custom[MAXPLAYERS + 1][CUSTOM_BYTES];
bool g_visible[MAXPLAYERS + 1], g_loaded[MAXPLAYERS + 1], g_banned[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Chat Tags",
    author = "HexTags, AstRedux maintainers",
    description = "Configurable and custom chat tags using Chat Processor.",
    version = "1.1.0"
};

public void OnPluginStart()
{
    LoadTranslations("chat_tags.phrases");
    g_cookie = RegClientCookie("chat_tag", "Selected chat tag id; empty uses the configured default.", CookieAccess_Protected);
    g_customCookie = RegClientCookie("chat_tag_custom", "Saved plain-text custom tag.", CookieAccess_Private);
    g_banCookie = RegClientCookie("chat_tag_custom_ban", "Custom tag permission revoked.", CookieAccess_Private);
    g_ids = new ArrayList(ByteCountToCells(64));
    g_names = new ArrayList(ByteCountToCells(128));
    g_values = new ArrayList(ByteCountToCells(128));
    g_selectable = new ArrayList();
    RegConsoleCmd("sm_tag", CommandTag);
    RegConsoleCmd("sm_tags", CommandTag);
    LoadTags();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client)) continue;
        ResetClient(client);
        if (AreClientCookiesCached(client)) OnClientCookiesCached(client);
    }
}
void ResetClient(int client)
{
    g_selected[client][0] = '\0';
    g_custom[client][0] = '\0';
    g_banned[client] = false;
    g_loaded[client] = false;
    g_visible[client] = true;
}
public void OnClientConnected(int client) { ResetClient(client); }
public void OnClientDisconnect(int client) { ResetClient(client); }
public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client) || g_loaded[client]) return;
    char value[256], ban[16];
    GetClientCookie(client, g_cookie, g_selected[client], sizeof(g_selected[]));
    GetClientCookie(client, g_customCookie, value, sizeof(value));
    GetClientCookie(client, g_banCookie, ban, sizeof(ban));
    g_banned[client] = StringToInt(ban) != 0;
    if (!g_banned[client] && IsValidCustom(value))
        strcopy(g_custom[client], sizeof(g_custom[]), value);
    else
    {
        g_custom[client][0] = '\0';
        if (value[0]) SetClientCookie(client, g_customCookie, "");
    }
    g_loaded[client] = true;
    ValidateSelectedTag(client);
}
// Admin and cookie callbacks may arrive in either order. Resolve admin defaults
// live instead of reloading cookies and overwriting an in-session selection.
public void OnClientPostAdminCheck(int client)
{
    if (!g_loaded[client] && AreClientCookiesCached(client)) OnClientCookiesCached(client);
}
bool Ready(int client)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) return false;
    if (g_loaded[client] && AreClientCookiesCached(client)) return true;
    PrintToChat(client, "%t", "TagLoading");
    return false;
}
bool CanManage(int client)
{
    return CheckCommandAccess(client, "chat_tag_manage", ADMFLAG_GENERIC);
}
public Action CommandTag(int client, int args)
{
    if (!Ready(client)) return Plugin_Handled;
    char command[32];
    GetCmdArg(0, command, sizeof(command));
    if (args > 0 && StrEqual(command, "sm_tag", false))
    {
        if (g_banned[client])
        {
            PrintToChat(client, "%t", "TagCustomBanned");
            return Plugin_Handled;
        }
        char text[256];
        int length = GetCmdArgString(text, sizeof(text));
        // Reject a full buffer rather than accepting a truncated command.
        if (length >= sizeof(text) - 1)
        {
            PrintToChat(client, "%t", "TagInvalidCustom");
            return Plugin_Handled;
        }
        StripQuotes(text);
        if (!IsValidCustom(text))
        {
            PrintToChat(client, "%t", "TagInvalidCustom");
            return Plugin_Handled;
        }
        strcopy(g_custom[client], sizeof(g_custom[]), text);
        SetClientCookie(client, g_customCookie, text);
        SelectTag(client, CUSTOM_ID);
        return Plugin_Handled;
    }
    ShowTagMenu(client);
    return Plugin_Handled;
}
void ShowTagMenu(int client)
{
    Menu menu = new Menu(MenuHandlerTag);
    menu.SetTitle("%T", "TagMenuTitle", client);
    char option[128];
    FormatEx(option, sizeof(option), "%T", g_visible[client] ? "TagHideOption" : "TagShowOption", client);
    menu.AddItem("__toggle", option);
    FormatEx(option, sizeof(option), "%T", "TagDefaultOption", client);
    menu.AddItem("__default", option);
    FormatEx(option, sizeof(option), "%T", "TagCustomOption", client);
    menu.AddItem(CUSTOM_ID, option, !g_banned[client] && g_custom[client][0] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    FormatEx(option, sizeof(option), "%T", "TagClearOption", client);
    menu.AddItem("__clear", option, g_custom[client][0] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    if (CanManage(client))
    {
        FormatEx(option, sizeof(option), "%T", "TagManageOption", client);
        menu.AddItem("__manage", option);
    }
    char id[64], name[128];
    for (int i = 0; i < g_ids.Length; i++)
    {
        if (!g_selectable.Get(i)) continue;
        g_ids.GetString(i, id, sizeof(id));
        g_names.GetString(i, name, sizeof(name));
        menu.AddItem(id, name);
    }
    menu.Display(client, MENU_TIME_FOREVER);
}
public int MenuHandlerTag(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        if (!Ready(client)) return 0;
        char id[64]; menu.GetItem(item, id, sizeof(id));
        if (StrEqual(id, "__toggle"))
        {
            g_visible[client] = !g_visible[client];
            PrintToChat(client, "%t", g_visible[client] ? "TagShown" : "TagHidden");
        }
        else if (StrEqual(id, "__manage"))
        {
            if (CanManage(client)) ShowTargets(client);
            else PrintToChat(client, "%t", "TagManageDenied");
        }
        else if (StrEqual(id, "__clear"))
        {
            ClearCustom(client);
            PrintToChat(client, "%t", "TagCustomCleared");
        }
        else
        {
            if (StrEqual(id, CUSTOM_ID))
            {
                if (g_banned[client] || !IsValidCustom(g_custom[client]))
                {
                    PrintToChat(client, "%t", "TagCustomUnavailable");
                    return 0;
                }
            }
            else if (!StrEqual(id, "__default"))
            {
                int index = g_ids.FindString(id);
                if (index == -1 || !g_selectable.Get(index)) return 0;
            }
            if (StrEqual(id, "__default")) id[0] = '\0';
            SelectTag(client, id);
        }
    }
    else if (action == MenuAction_End) delete menu;
    return 0;
}
public Action CP_OnChatMessage(int &author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool &processcolors, bool &removecolors)
{
    if (author <= 0 || author > MaxClients || !IsClientInGame(author) || IsFakeClient(author))
        return Plugin_Continue;

    char tag[128];
    GetEffectiveTag(author, tag, sizeof(tag));
    if (!tag[0])
        return Plugin_Continue;

    // Chat Processor has already selected recipients and preserves its native
    // team/dead/mute behavior. Only change its author-name field.
    Format(name, MAXLENGTH_NAME, "[%s] %s", tag, name);
    processcolors = false;
    return Plugin_Changed;
}
void GetEffectiveTag(int client, char[] tag, int maxlength)
{
    tag[0] = '\0';
    if (!g_visible[client] || !g_loaded[client]) return;
    if (StrEqual(g_selected[client], CUSTOM_ID) && !g_banned[client] && IsValidCustom(g_custom[client]))
    {
        strcopy(tag, maxlength, g_custom[client]);
        return;
    }
    int index = g_ids.FindString(g_selected[client]);
    if (index == -1 || !g_selectable.Get(index))
    {
        index = CheckCommandAccess(client, "chat_tag_admin", ADMFLAG_GENERIC) ? g_ids.FindString("admin") : -1;
        if (index == -1) index = g_ids.FindString("default");
    }
    if (index != -1) g_values.GetString(index, tag, maxlength);
}
void SelectTag(int client, const char[] id)
{
    strcopy(g_selected[client], sizeof(g_selected[]), id);
    SetClientCookie(client, g_cookie, id);
    g_visible[client] = true;
    PrintToChat(client, "%t", "TagSelected");
}
void ValidateSelectedTag(int client)
{
    if (StrEqual(g_selected[client], CUSTOM_ID) && !g_banned[client] && IsValidCustom(g_custom[client])) return;
    int index = g_ids.FindString(g_selected[client]);
    if (index != -1 && g_selectable.Get(index)) return;
    g_selected[client][0] = '\0';
    SetClientCookie(client, g_cookie, "");
}
void ClearCustom(int client)
{
    g_custom[client][0] = '\0';
    SetClientCookie(client, g_customCookie, "");
    if (StrEqual(g_selected[client], CUSTOM_ID))
    {
        g_selected[client][0] = '\0';
        SetClientCookie(client, g_cookie, "");
    }
}
bool IsValidCustom(const char[] text)
{
    int length = strlen(text), count;
    if (!length || length >= CUSTOM_BYTES) return false;
    bool visible;
    for (int i = 0; i < length;)
    {
        int first = text[i] & 0xFF, code, bytes;
        if (first < 0x80) { code = first; bytes = 1; }
        else if (first >= 0xC2 && first <= 0xDF) { code = first & 0x1F; bytes = 2; }
        else if (first >= 0xE0 && first <= 0xEF) { code = first & 0x0F; bytes = 3; }
        else if (first >= 0xF0 && first <= 0xF4) { code = first & 0x07; bytes = 4; }
        else return false;
        if (i + bytes > length) return false;
        for (int j = 1; j < bytes; j++)
        {
            int next = text[i + j] & 0xFF;
            if ((next & 0xC0) != 0x80) return false;
            code = (code << 6) | (next & 0x3F);
        }
        if ((bytes == 3 && code < 0x800) || (bytes == 4 && code < 0x10000)
            || (code >= 0xD800 && code <= 0xDFFF) || code > 0x10FFFF) return false;
        // CP substitutes brace tokens even without color processing.
        if (code < 0x20 || (code >= 0x7F && code <= 0x9F)
            || code == '{' || code == '}' || code == 0xAD || code == 0x61C
            || code == 0x180E || (code >= 0x200B && code <= 0x200F)
            || (code >= 0x2028 && code <= 0x202E) || (code >= 0x2060 && code <= 0x206F)
            || code == 0xFEFF || (code >= 0xFFF9 && code <= 0xFFFB)
            || (code >= 0xE0000 && code <= 0xE007F)) return false;
        if (code != 0x20 && code != 0xA0 && code != 0x1680
            && !(code >= 0x2000 && code <= 0x200A) && code != 0x202F
            && code != 0x205F && code != 0x3000) visible = true;
        if (++count > 12) return false;
        i += bytes;
    }
    if (!visible) return false;
    int admin = g_ids.FindString("admin");
    if (admin != -1)
    {
        char reserved[128];
        g_values.GetString(admin, reserved, sizeof(reserved));
        TrimString(reserved);
        // Also reject padding and ASCII case variants of the reserved label.
        if (reserved[0] && StrContains(text, reserved, false) != -1) return false;
    }
    return true;
}
void ShowTargets(int client)
{
    Menu menu = new Menu(MenuHandlerTargets);
    menu.SetTitle("%T", "TagManageOption", client);
    char userid[16], name[MAX_NAME_LENGTH];
    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsClientInGame(target) || IsFakeClient(target) || !CanUserTarget(client, target)) continue;
        IntToString(GetClientUserId(target), userid, sizeof(userid));
        GetClientName(target, name, sizeof(name));
        menu.AddItem(userid, name, g_loaded[target] && AreClientCookiesCached(target) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}
bool ManageTarget(int client, int userid, int &target)
{
    if (!Ready(client)) return false;
    if (!CanManage(client))
    {
        PrintToChat(client, "%t", "TagManageDenied");
        return false;
    }
    target = GetClientOfUserId(userid);
    if (!target || !IsClientInGame(target) || IsFakeClient(target) || !CanUserTarget(client, target))
    {
        PrintToChat(client, "%t", "TagTargetUnavailable");
        return false;
    }
    if (!g_loaded[target] || !AreClientCookiesCached(target))
    {
        PrintToChat(client, "%t", "TagLoading");
        return false;
    }
    return true;
}
public int MenuHandlerTargets(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && Ready(client)) ShowTagMenu(client);
    else if (action == MenuAction_Select)
    {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        int target, userid = StringToInt(info);
        if (!ManageTarget(client, userid, target)) return 0;
        Menu actions = new Menu(MenuHandlerManage);
        actions.SetTitle("%T: %N", "TagManageOption", client, target);
        char key[32], label[128];
        FormatEx(key, sizeof(key), "%d clear", userid);
        FormatEx(label, sizeof(label), "%T", "TagClearOption", client);
        actions.AddItem(key, label);
        FormatEx(key, sizeof(key), "%d ban", userid);
        FormatEx(label, sizeof(label), "%T", "TagBanOption", client);
        actions.AddItem(key, label, g_banned[target] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
        FormatEx(key, sizeof(key), "%d restore", userid);
        FormatEx(label, sizeof(label), "%T", "TagRestoreOption", client);
        actions.AddItem(key, label, g_banned[target] ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
        actions.ExitBackButton = true;
        actions.Display(client, MENU_TIME_FOREVER);
    }
    return 0;
}
public int MenuHandlerManage(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End) delete menu;
    else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && Ready(client) && CanManage(client)) ShowTargets(client);
    else if (action == MenuAction_Select)
    {
        char info[32], parts[2][16];
        menu.GetItem(item, info, sizeof(info));
        if (ExplodeString(info, " ", parts, sizeof(parts), sizeof(parts[])) != 2) return 0;
        int target;
        if (!ManageTarget(client, StringToInt(parts[0]), target)) return 0;
        if (StrEqual(parts[1], "clear"))
        {
            ClearCustom(target);
            PrintToChat(target, "%t", "TagCustomCleared");
        }
        else if (StrEqual(parts[1], "ban"))
        {
            g_banned[target] = true;
            SetClientCookie(target, g_banCookie, "1");
            ClearCustom(target);
            PrintToChat(target, "%t", "TagCustomBanned");
        }
        else if (StrEqual(parts[1], "restore"))
        {
            if (!g_banned[target]) return 0;
            ClearCustom(target);
            g_banned[target] = false;
            SetClientCookie(target, g_banCookie, "0");
            PrintToChat(target, "%t", "TagCustomRestored");
        }
        else return 0;
        PrintToChat(client, "%t", "TagManageDone");
        ShowTargets(client);
    }
    return 0;
}
void LoadTags()
{
    g_ids.Clear(); g_names.Clear(); g_values.Clear(); g_selectable.Clear();
    KeyValues config = new KeyValues("ChatTags");
    char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), TAG_CONFIG);
    if (!config.ImportFromFile(path)) SetFailState("Missing tag config: %s", path);
    if (config.GotoFirstSubKey())
    {
        do
        {
            char id[64], name[128], value[128];
            config.GetSectionName(id, sizeof(id)); config.GetString("name", name, sizeof(name), id); config.GetString("tag", value, sizeof(value));
            g_ids.PushString(id); g_names.PushString(name); g_values.PushString(value); g_selectable.Push(config.GetNum("selectable", 0));
        } while (config.GotoNextKey());
    }
    delete config;
}
