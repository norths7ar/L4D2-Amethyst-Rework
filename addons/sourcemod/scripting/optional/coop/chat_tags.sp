#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <clientprefs>
#include <chat-processor>
#define TAG_CONFIG "configs/chat_tags.cfg"

Handle g_cookie;
ArrayList g_ids, g_names, g_values, g_selectable;
char g_selected[MAXPLAYERS + 1][64];
bool g_visible[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Chat Tags",
    author = "HexTags, AstRedux maintainers",
    description = "Basic configurable chat tags using Chat Processor.",
    version = "1.0.0"
};

public void OnPluginStart()
{
    LoadTranslations("chat_tags.phrases");
    g_cookie = RegClientCookie("chat_tag", "Selected chat tag id; empty uses the configured default.", CookieAccess_Protected);
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
        g_visible[client] = true;
        if (AreClientCookiesCached(client))
        {
            GetClientCookie(client, g_cookie, g_selected[client], sizeof(g_selected[]));
            ValidateSelectedTag(client);
        }
    }
}
public void OnClientPutInServer(int client) { g_visible[client] = true; }
public void OnClientCookiesCached(int client)
{
    GetClientCookie(client, g_cookie, g_selected[client], sizeof(g_selected[]));
    ValidateSelectedTag(client);
    g_visible[client] = true;
}
public void OnClientPostAdminCheck(int client)
{
    if (AreClientCookiesCached(client))
    {
        GetClientCookie(client, g_cookie, g_selected[client], sizeof(g_selected[]));
        ValidateSelectedTag(client);
        g_visible[client] = true;
    }
}
public void OnClientDisconnect(int client) { g_selected[client][0] = '\0'; g_visible[client] = true; }

public Action CommandTag(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
    Menu menu = new Menu(MenuHandlerTag);
    menu.SetTitle("%t", "TagMenuTitle");
    menu.AddItem("__toggle", g_visible[client] ? "隐藏当前称号" : "显示当前称号");
    menu.AddItem("__default", "恢复默认称号");
    char id[64], name[128];
    for (int i = 0; i < g_ids.Length; i++)
    {
        if (!g_selectable.Get(i)) continue;
        g_ids.GetString(i, id, sizeof(id));
        g_names.GetString(i, name, sizeof(name));
        menu.AddItem(id, name);
    }
    menu.Display(client, MENU_TIME_FOREVER);
    return Plugin_Handled;
}
public int MenuHandlerTag(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select)
    {
        char id[64]; menu.GetItem(item, id, sizeof(id));
        if (StrEqual(id, "__toggle"))
        {
            g_visible[client] = !g_visible[client];
            PrintToChat(client, "%t", g_visible[client] ? "TagShown" : "TagHidden");
        }
        else
        {
            if (StrEqual(id, "__default")) id[0] = '\0';
            strcopy(g_selected[client], sizeof(g_selected[]), id);
            SetClientCookie(client, g_cookie, id);
            g_visible[client] = true;
            PrintToChat(client, "%t", "TagSelected");
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
    Format(name, MAXLENGTH_NAME, "{green}[%s] {teamcolor}%s", tag, name);
    processcolors = true;
    return Plugin_Changed;
}
void GetEffectiveTag(int client, char[] tag, int maxlength)
{
    tag[0] = '\0';
    if (!g_visible[client]) return;
    int index = g_ids.FindString(g_selected[client]);
    if (index == -1 || !g_selectable.Get(index)) index = g_ids.FindString(CheckCommandAccess(client, "chat_tag_admin", ADMFLAG_GENERIC) ? "admin" : "default");
    if (index != -1) g_values.GetString(index, tag, maxlength);
}
void ValidateSelectedTag(int client)
{
    int index = g_ids.FindString(g_selected[client]);
    if (index != -1 && g_selectable.Get(index)) return;
    g_selected[client][0] = '\0';
    SetClientCookie(client, g_cookie, "");
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
