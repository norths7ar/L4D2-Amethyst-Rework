#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <imatchext>
#undef REQUIRE_PLUGIN
#include <l4d2_skill_detect>
#include <readyup>

native bool IsInPause();

#define VERSION "0.1.0"
#define CONFIG_PATH "configs/coop_shop.txt"
#define MAX_PRODUCTS 22
#define MAX_LEDGER 2147483000

enum Award { AwardCommon, AwardSI, AwardTank, AwardWitch, AwardSkeet, AwardTongue, AwardRock, AwardCrown, AwardClear, AwardCount };

static const char g_awardKeys[AwardCount][] = {"common", "special", "tank_team", "witch", "skeet", "tongue_cut", "rock_skeet", "crown", "special_clear"};
static const char g_productKeys[MAX_PRODUCTS][] = {
    "ammo", "pills", "pump", "chrome", "smg_silenced", "smg", "scout", "pistol", "magnum",
    "fireaxe", "frying_pan", "machete", "baseball_bat", "crowbar", "cricket_bat", "tonfa",
    "electric_guitar", "katana", "knife", "pitchfork", "shovel", "defib"
};
static const char g_productNames[MAX_PRODUCTS][] = {
    "补充弹药", "止痛药", "木喷", "铁喷", "消音冲锋枪", "乌兹冲锋枪", "Scout", "手枪", "马格南",
    "消防斧", "平底锅", "砍刀", "棒球棍", "撬棍", "板球拍", "警棍", "电吉他", "武士刀", "小刀",
    "干草叉", "铁铲", "电击器"
};
static const char g_classNames[MAX_PRODUCTS][] = {
    "", "weapon_pain_pills", "weapon_pumpshotgun", "weapon_shotgun_chrome", "weapon_smg_silenced",
    "weapon_smg", "weapon_sniper_scout", "weapon_pistol", "weapon_pistol_magnum", "fireaxe", "frying_pan",
    "machete", "baseball_bat", "crowbar", "cricket_bat", "tonfa", "electric_guitar", "katana", "knife",
    "pitchfork", "shovel", "weapon_defibrillator"
};

public Plugin myinfo = { name = "Coop Campaign Shop", author = "Amethyst Rework", description = "Campaign-scoped points shop", version = VERSION, url = "https://github.com/Sglight/L4D2-Amethyst-Rework" };

ConVar g_enabled;
ConVar g_allowIncap;
ConVar g_allowPinned;
int g_awards[AwardCount];
int g_base[MAX_PRODUCTS], g_step[MAX_PRODUCTS];
bool g_productEnabled[MAX_PRODUCTS];
StringMap g_points;
StringMap g_purchases;
char g_campaign[64];
bool g_configLoaded;
int g_lastTankUserId;
float g_lastTankDeath;
StringMap g_skillKills;
bool g_campaignFinished;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int maxlen)
{
    MarkNativeAsOptional("IsInReady");
    MarkNativeAsOptional("IsInPause");
    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("coop_shop.phrases");
    g_points = new StringMap();
    g_purchases = new StringMap();
    g_skillKills = new StringMap();
    g_enabled = CreateConVar("coop_shop_enable", "1", "Enable the campaign shop.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_allowIncap = CreateConVar("coop_shop_allow_incapacitated", "0", "Allow purchases while incapacitated or hanging.", _, true, 0.0, true, 1.0);
    g_allowPinned = CreateConVar("coop_shop_allow_pinned", "0", "Allow purchases while pinned.", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "coop_shop");
    RegConsoleCmd("sm_buy", CommandBuy);
    RegConsoleCmd("sm_ammo", CommandAmmo);
    RegAdminCmd("sm_coopshop_reload", CommandReload, ADMFLAG_CONFIG);
    HookEvent("infected_death", EventCommonDeath);
    HookEvent("player_death", EventPlayerDeath);
    HookEvent("witch_killed", EventWitchKilled);
    HookEvent("finale_win", EventFinaleWin);
}

public void OnConfigsExecuted() { LoadShopConfig(true); RefreshCampaign(); }
public void EventFinaleWin(Event event, const char[] name, bool dontBroadcast) { g_campaignFinished = true; }
public void OnMapStart()
{
    g_skillKills.Clear();
    if (g_campaignFinished)
    {
        g_points.Clear();
        g_purchases.Clear();
        g_campaignFinished = false;
    }
    RequestFrame(FrameRefreshCampaign);
}
public void OnMissionCacheReload() { RequestFrame(FrameRefreshCampaign); }
void FrameRefreshCampaign() { RefreshCampaign(); }

void RefreshCampaign()
{
    char current[64];
    MissionSymbol mission = CurrentMission;
    if (MissionSymbol.IsValid(mission)) mission.GetName(current, sizeof(current));
    else return;
    if (g_campaign[0] && !StrEqual(g_campaign, current, false)) { g_points.Clear(); g_purchases.Clear(); }
    strcopy(g_campaign, sizeof(g_campaign), current);
}

public Action CommandReload(int client, int args)
{
    bool ok = LoadShopConfig(true);
    ReplyToCommand(client, "%t", ok ? "ReloadSuccess" : "ReloadFailed");
    return Plugin_Handled;
}

bool LoadShopConfig(bool logFailure)
{
    char path[PLATFORM_MAX_PATH]; BuildPath(Path_SM, path, sizeof(path), CONFIG_PATH);
    KeyValues kv = new KeyValues("CoopShop");
    if (!kv.ImportFromFile(path)) { delete kv; if (logFailure) LogError("Cannot parse %s; keeping prior shop configuration", path); return false; }
    int awards[AwardCount], base[MAX_PRODUCTS], step[MAX_PRODUCTS]; bool enabled[MAX_PRODUCTS]; bool valid = true;
    if (!kv.JumpToKey("awards")) valid = false;
    if (valid)
    {
        for (int i; i < view_as<int>(AwardCount); i++)
        {
            if (!ReadConfigInteger(kv, g_awardKeys[i], awards[i], false)) valid = false;
        }
    }
    kv.Rewind();
    if (!kv.JumpToKey("products")) valid = false;
    if (valid) for (int i; i < MAX_PRODUCTS; i++) {
        if (!kv.JumpToKey(g_productKeys[i])) { valid = false; break; }
        int raw;
        if (!ReadConfigInteger(kv, "enabled", raw, false)
            || !ReadConfigInteger(kv, "base", base[i], true)
            || !ReadConfigInteger(kv, "step", step[i], false)
            || (raw != 0 && raw != 1))
        {
            valid = false;
        }
        enabled[i] = raw == 1;
        kv.GoBack();
    }
    delete kv;
    if (!valid) { if (logFailure) LogError("Invalid %s; keeping prior shop configuration", path); return false; }
    for (int i; i < view_as<int>(AwardCount); i++) g_awards[i] = awards[i];
    for (int i; i < MAX_PRODUCTS; i++) { g_base[i] = base[i]; g_step[i] = step[i]; g_productEnabled[i] = enabled[i]; }
    g_configLoaded = true; return true;
}

bool ReadConfigInteger(KeyValues kv, const char[] key, int &value, bool positive)
{
    char raw[32];
    kv.GetString(key, raw, sizeof(raw), "");
    TrimString(raw);
    int length = strlen(raw);
    if (length == 0) return false;

    int parsed;
    for (int i; i < length; i++)
    {
        if (raw[i] < '0' || raw[i] > '9') return false;
        int digit = raw[i] - '0';
        if (parsed > (MAX_LEDGER - digit) / 10) return false;
        parsed = parsed * 10 + digit;
    }
    if (positive && parsed < 1) return false;
    value = parsed;
    return true;
}

public Action CommandAmmo(int client, int args) { return TryPurchase(client, 0); }
public Action CommandBuy(int client, int args)
{
    if (!CanOpenShop(client)) return Plugin_Handled;
    Menu menu = new Menu(MenuShop);
    char title[96]; Format(title, sizeof(title), "%T", "MenuTitle", client, GetPoints(client)); menu.SetTitle(title);
    for (int i; i < MAX_PRODUCTS; i++) if (g_productEnabled[i] && IsProductAvailable(i)) {
        int price = GetPrice(client, i); char info[8], display[96]; IntToString(i, info, sizeof(info)); Format(display, sizeof(display), "%s - %d 分", g_productNames[i], price); menu.AddItem(info, display);
    }
    menu.ExitButton = true; menu.Display(client, 20); return Plugin_Handled;
}

public int MenuShop(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_Select) { char info[8]; menu.GetItem(item, info, sizeof(info)); TryPurchase(client, StringToInt(info)); }
    else if (action == MenuAction_End) delete menu;
    return 0;
}

bool CanOpenShop(int client)
{
    if (!g_enabled.BoolValue || !g_configLoaded) { if (client) PrintToChat(client, "%t", "Disabled"); return false; }
    if (!IsHumanSurvivor(client)) return false;
    if ((GetFeatureStatus(FeatureType_Native, "IsInPause") == FeatureStatus_Available && IsInPause()) || (GetFeatureStatus(FeatureType_Native, "IsInReady") == FeatureStatus_Available && IsInReady())) { PrintToChat(client, "%t", "UnavailableState"); return false; }
    if (!IsPlayerAlive(client)) { PrintToChat(client, "%t", "UnavailableState"); return false; }
    if (!g_allowIncap.BoolValue && (GetEntProp(client, Prop_Send, "m_isIncapacitated") || GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))) { PrintToChat(client, "%t", "UnavailableState"); return false; }
    if (!g_allowPinned.BoolValue && IsPinned(client)) { PrintToChat(client, "%t", "UnavailableState"); return false; }
    return true;
}

Action TryPurchase(int client, int product)
{
    if (!CanOpenShop(client) || product < 0 || product >= MAX_PRODUCTS || !g_productEnabled[product] || !IsProductAvailable(product)) return Plugin_Handled;
    int price = GetPrice(client, product), points = GetPoints(client);
    if (price < 1 || points < price) { PrintToChat(client, "%t", "NotEnough", price, points); return Plugin_Handled; }
    if (!GiveProduct(client, product)) { PrintToChat(client, "%t", "GiveFailed"); return Plugin_Handled; }
    SetPoints(client, points - price); IncrementPurchases(client, product); PrintToChat(client, "%t", "Purchased", g_productNames[product], price, points - price); return Plugin_Handled;
}

bool GiveProduct(int client, int product)
{
    if (product == 0)
    {
        int weapon = GetPlayerWeaponSlot(client, 0);
        if (weapon <= MaxClients || !HasEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType")) return false;
        int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
        return ammoType >= 0 && GivePlayerAmmo(client, 999, ammoType, true) > 0;
    }

    int slot = ProductSlot(product);
    int previous = GetPlayerWeaponSlot(client, slot);
    if (previous > MaxClients && (slot == 3 || slot == 4)) return false;
    bool secondPistol;
    if (previous > MaxClients && product == 7)
    {
        char classname[64];
        GetEntityClassname(previous, classname, sizeof(classname));
        if (StrEqual(classname, "weapon_pistol"))
        {
            if (GetEntProp(previous, Prop_Send, "m_isDualWielding")) return false;
            secondPistol = true;
        }
    }
    // Drop, do not destroy, the old weapon. Restore it if delivery fails.
    if (previous > MaxClients && !secondPistol)
    {
        SDKHooks_DropWeapon(client, previous);
        if (GetPlayerWeaponSlot(client, slot) == previous) return false;
    }

    int entity;
    if (product >= 9 && product <= 20)
    {
        entity = CreateEntityByName("weapon_melee");
        if (entity == -1)
        {
            if (previous > MaxClients && IsValidEntity(previous)) EquipPlayerWeapon(client, previous);
            return false;
        }
        DispatchKeyValue(entity, "melee_script_name", g_classNames[product]);
        if (!DispatchSpawn(entity))
        {
            RemoveEntity(entity);
            if (previous > MaxClients && IsValidEntity(previous)) EquipPlayerWeapon(client, previous);
            return false;
        }
        EquipPlayerWeapon(client, entity);
    }
    else
    {
        entity = GivePlayerItem(client, g_classNames[product]);
    }
    int equipped = GetPlayerWeaponSlot(client, slot);
    if (secondPistol)
        return equipped == previous && GetEntProp(previous, Prop_Send, "m_isDualWielding") != 0;
    if (entity > MaxClients && equipped == entity) return true;
    if (entity > MaxClients && IsValidEntity(entity)) RemoveEntity(entity);
    if (previous > MaxClients && IsValidEntity(previous) && equipped == -1) EquipPlayerWeapon(client, previous);
    return false;
}

int ProductSlot(int product)
{
    if (product == 1) return 4;
    if (product >= 2 && product <= 6) return 0;
    if (product >= 7 && product <= 20) return 1;
    return 3;
}

bool IsProductAvailable(int product)
{
    if (product < 9 || product > 20) return true;
    int table = FindStringTable("MeleeWeapons");
    return table != INVALID_STRING_TABLE && FindStringIndex(table, g_classNames[product]) != INVALID_STRING_INDEX;
}
int GetPrice(int client, int product)
{
    int count = GetPurchases(client, product);
    if (g_step[product] > 0 && count > (MAX_LEDGER - g_base[product]) / g_step[product]) return MAX_LEDGER;
    return g_base[product] + count * g_step[product];
}

public void EventCommonDeath(Event event, const char[] name, bool dontBroadcast) { AwardClient(GetClientOfUserId(event.GetInt("attacker")), g_awards[AwardCommon]); }
public void EventWitchKilled(Event event, const char[] name, bool dontBroadcast) { AwardClient(GetClientOfUserId(event.GetInt("userid")), g_awards[AwardWitch]); }
public void EventPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid")); if (victim < 1 || GetClientTeam(victim) != 3) return;
    int cls = GetEntProp(victim, Prop_Send, "m_zombieClass");
    if (cls == 8) { float now = GetGameTime(); int userid = event.GetInt("userid"); if (userid == g_lastTankUserId && now - g_lastTankDeath < 1.0) return; g_lastTankUserId = userid; g_lastTankDeath = now; for (int i = 1; i <= MaxClients; i++) if (IsHumanSurvivor(i)) AwardClient(i, g_awards[AwardTank]); }
    else if (cls >= 1 && cls <= 6) { DataPack pack = new DataPack(); pack.WriteCell(event.GetInt("userid")); pack.WriteCell(event.GetInt("attacker")); RequestFrame(FrameSpecialDeath, pack); }
}

void FrameSpecialDeath(DataPack pack)
{
    pack.Reset(); int userid = pack.ReadCell(); int attacker = GetClientOfUserId(pack.ReadCell()); delete pack;
    char key[16];
    IntToString(userid, key, sizeof(key));
    int rewarded;
    if (g_skillKills.GetValue(key, rewarded)) { g_skillKills.Remove(key); return; }
    AwardClient(attacker, g_awards[AwardSI]);
}

public void OnSkeet(int survivor, int hunter) { AwardSkeetOnce(survivor, hunter); }
public void OnSkeetMelee(int survivor, int hunter) { AwardSkeetOnce(survivor, hunter); }
public void OnSkeetSniper(int survivor, int hunter) { AwardSkeetOnce(survivor, hunter); }

void AwardSkeetOnce(int survivor, int hunter)
{
    if (hunter <= 0 || hunter > MaxClients || !IsClientInGame(hunter)
        || !IsHumanSurvivor(survivor) || !g_enabled.BoolValue || !g_configLoaded || g_awards[AwardSkeet] <= 0) return;
    char key[16];
    IntToString(GetClientUserId(hunter), key, sizeof(key));
    int rewarded;
    if (g_skillKills.GetValue(key, rewarded)) return;
    g_skillKills.SetValue(key, 1);
    AwardClient(survivor, g_awards[AwardSkeet]);
}
public void OnTongueCut(int survivor, int smoker) { AwardClient(survivor, g_awards[AwardTongue]); }
public void OnTankRockSkeeted(int survivor, int tank) { AwardClient(survivor, g_awards[AwardRock]); }
public void OnWitchCrown(int survivor, int damage) { AwardClient(survivor, g_awards[AwardCrown]); }
public void OnSpecialClear(int clearer, int pinner, int pinvictim, int zombieClass, float timeA, float timeB, bool withShove) { AwardClient(clearer, g_awards[AwardClear]); }

void AwardClient(int client, int amount) { if (!g_enabled.BoolValue || !g_configLoaded || amount <= 0 || !IsHumanSurvivor(client)) return; int old = GetPoints(client); SetPoints(client, old > MAX_LEDGER - amount ? MAX_LEDGER : old + amount); }
bool IsHumanSurvivor(int client) { return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == 2; }
bool IsPinned(int client)
{
    return GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pounceAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker") > 0;
}

bool GetIdentity(int client, char[] key, int maxlen) { return GetClientAuthId(client, AuthId_Steam2, key, maxlen, true); }
int GetPoints(int client) { char key[64]; int value; if (GetIdentity(client, key, sizeof(key))) g_points.GetValue(key, value); return value; }
void SetPoints(int client, int value) { char key[64]; if (GetIdentity(client, key, sizeof(key))) g_points.SetValue(key, value, true); }
void LedgerKey(int client, int product, char[] key, int maxlen) { char auth[48]; if (!GetIdentity(client, auth, sizeof(auth))) auth[0] = 0; Format(key, maxlen, "%s|%s", auth, g_productKeys[product]); }
int GetPurchases(int client, int product) { char key[80]; int value; LedgerKey(client, product, key, sizeof(key)); if (key[0]) g_purchases.GetValue(key, value); return value; }
void IncrementPurchases(int client, int product) { char key[80]; LedgerKey(client, product, key, sizeof(key)); if (key[0]) g_purchases.SetValue(key, GetPurchases(client, product) + 1, true); }
