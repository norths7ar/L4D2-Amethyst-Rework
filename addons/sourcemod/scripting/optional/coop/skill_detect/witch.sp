// Witch tracking (Tabun/Crox). Entity references and userids own combat records.
enum struct WitchContribution
{
    int userid;
    int raw;
    int actual;
    float shotStart;
    int shot;
    bool buckshot;
}
enum struct WitchRecord
{
    int reference;
    ArrayList contributions;
    int maxHealth;
    int remaining;
    int preHealth;
    bool inDamage;
    bool damaged;
    bool slashed;
    bool startled;
    bool printed;
    bool killed;
    bool resolved;
    int killerUser;
    int killerLife;
    int killerHealth;
    bool oneShot;
    int crownShot;
    bool crownType;
}
ArrayList g_Witches;
int g_WitchSlot[2049]; // record index + 1, checked against entref
bool g_WitchRoundLive;
ConVar g_WdaIncap, g_WdaMinimum, g_WdaMaxLines, g_WdaCombination;
ConVar g_WitchSkillHealth;

void WitchInit()
{
    g_Witches = new ArrayList(sizeof(WitchRecord));
    g_WitchSkillHealth = FindConVar("z_witch_health");
    g_WdaIncap = CreateConVar("l4d_wda_print_incap", "0", "Do we print the Witch's remaining health when she incapacitates a survivor?");
    g_WdaMinimum = CreateConVar("l4d_wda_print_minimum", "0", "What's the minimum percentage of damage we need to do to be listed? 0 = Disabled, everyone listed.");
    g_WdaMaxLines = CreateConVar("l4d_wda_print_max_lines", "0", "Maximum amount of damage lines we list (Survivors + Rest), 0 = Disabled, everyone listed.");
    g_WdaCombination = CreateConVar("l4d_wda_combination_name", "The Other Survivors", "What do we call the combined players? Character limit of 32.");
    HookEvent("player_death", WitchSurvivorDeath);
    HookEvent("player_incapacitated_start", WitchSurvivorIncap);
}

void WitchReset(bool live)
{
    WitchRecord record;
    for (int i; i < g_Witches.Length; i++)
    {
        g_Witches.GetArray(i, record);
        delete record.contributions;
    }
    g_Witches.Clear();
    for (int i; i < sizeof(g_WitchSlot); i++) g_WitchSlot[i] = 0;
    g_WitchRoundLive = live;
}

int WitchFind(int entity, WitchRecord record)
{
    if (entity <= MaxClients || entity >= sizeof(g_WitchSlot) || !IsValidEntity(entity)) return -1;
    int index = g_WitchSlot[entity] - 1;
    if (index < 0) return -1;
    g_Witches.GetArray(index, record);
    return record.reference == EntIndexToEntRef(entity) ? index : -1;
}

void WitchSpawnPost(int entity)
{
    if (!IsWitch(entity)) return;
    WitchRecord record;
    if (WitchFind(entity, record) >= 0) return;
    record.reference = EntIndexToEntRef(entity);
    record.maxHealth = GetEntProp(entity, Prop_Data, "m_iHealth");
    if (record.maxHealth <= 0) return;
    record.remaining = record.maxHealth;
    record.contributions = new ArrayList(sizeof(WitchContribution));
    g_WitchSlot[entity] = g_Witches.PushArray(record) + 1;
    SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Witch);
    SDKHook(entity, SDKHook_OnTakeDamagePost, OnTakeDamagePost_Witch);
}

Action Event_WitchSpawned(Handle event, const char[] name, bool dontBroadcast)
{
    WitchSpawnPost(GetEventInt(event, "witchid"));
    return Plugin_Continue;
}

Action Event_WitchHarasserSet(Handle event, const char[] name, bool dontBroadcast)
{
    WitchRecord record;
    int index = WitchFind(GetEventInt(event, "witchid"), record);
    if (index >= 0 && !record.killed)
    {
        record.startled = true; // harasser set
        g_Witches.SetArray(index, record);
    }
    return Plugin_Continue;
}

Action OnTakeDamageByWitch(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    WitchRecord record;
    int index = WitchFind(attacker, record);
    // Not a crown if the Witch hit anyone for > 0 damage.
    if (index >= 0 && !record.killed && IsValidSurvivor(victim) && damage > 0.0)
    {
        record.slashed = true;
        g_Witches.SetArray(index, record);
    }
    return Plugin_Continue;
}

Action OnTakeDamage_Witch(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    WitchRecord record;
    int index = WitchFind(victim, record);
    if (index >= 0 && !record.killed)
    {
        record.preHealth = GetEntProp(victim, Prop_Data, "m_iHealth");
        record.inDamage = record.preHealth > 0;
        // Include per-instance map/plugin health overrides.
        if (!record.damaged || record.preHealth > record.maxHealth) record.maxHealth = record.preHealth;
        record.damaged = true;
        g_Witches.SetArray(index, record);
    }
    return Plugin_Continue; // Observation only: never modify gameplay damage.
}

void OnTakeDamagePost_Witch(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    WitchRecord record;
    int index = WitchFind(victim, record);
    if (index < 0 || !record.inDamage || record.resolved) return;
    record.inDamage = false;
    int health = GetEntProp(victim, Prop_Data, "m_iHealth");
    record.remaining = health > 0 ? health : 0;
    int actual = record.preHealth - record.remaining;
    if (actual < 0) actual = 0;
    int userid = IsValidSurvivor(attacker) ? GetClientUserId(attacker) : 0;
    WitchContribution contribution;
    int entry = record.contributions.FindValue(userid);
    if (entry >= 0) record.contributions.GetArray(entry, contribution);
    else contribution.userid = userid;
    // Raw overkill remains visible to skills; HP loss is report-only.
    contribution.raw += RoundToFloor(damage);
    contribution.actual += actual;
    if (userid != 0)
    {
        if (contribution.shotStart == 0.0 || GetGameTime() - contribution.shotStart > SHOTGUN_BLAST_TIME)
        {
            contribution.shotStart = GetGameTime();
            contribution.shot = 0;
            contribution.buckshot = (damagetype & DMG_BUCKSHOT) != 0; // only allow shotguns
        }
        contribution.shot += RoundToFloor(damage); // continued blast, add up
        record.crownShot = contribution.shot;
        record.crownType = contribution.buckshot;
    }
    if (entry < 0) record.contributions.PushArray(contribution);
    else record.contributions.SetArray(entry, contribution);
    g_Witches.SetArray(index, record);
}

Action Event_WitchKilled(Handle event, const char[] name, bool dontBroadcast)
{
    WitchRecord record;
    int index = WitchFind(GetEventInt(event, "witchid"), record);
    if (index < 0 || record.killed) return Plugin_Continue;
    record.killed = true;
    record.remaining = 0;
    record.killerUser = GetEventInt(event, "userid");
    record.oneShot = GetEventBool(event, "oneshot");
    int killer = GetClientOfUserId(record.killerUser);
    if (IsValidSurvivor(killer))
    {
        record.killerLife = g_SurvivorLife[killer];
        record.killerHealth = GetClientHealth(killer);
    }
    // Tank notice is independent of the one-time report and round gate.
    if (IsValidInfected(killer) && GetEntProp(killer, Prop_Send, "m_zombieClass") == ZC_TANK)
    {
        CPrintToChatAll("{default}[{green}!{default}] {red}Tank {default}({olive}%N{default}) killed the {red}Witch", killer);
        record.printed = true;
    }
    g_Witches.SetArray(index, record);
    // witch_killed can run inside TakeDamage, before its post hook. Let that
    // single in-flight hit settle before copying the complete death snapshot.
    DataPack pack = new DataPack();
    pack.WriteCell(g_SkillEpoch);
    pack.WriteCell(index);
    RequestFrame(WitchSnapshotDeath, pack);
    return Plugin_Continue;
}

void WitchSnapshotDeath(DataPack request)
{
    request.Reset();
    int epoch = request.ReadCell(), index = request.ReadCell();
    delete request;
    if (epoch != g_SkillEpoch) return;
    WitchRecord record;
    g_Witches.GetArray(index, record);
    if (record.resolved) return;
    record.resolved = true;
    WitchPrintDamage(record, false);
    int raw[MAXPLAYERS + DMGARRAYEXT];
    WitchContribution contribution;
    // Snapshot killer raw damage and all other chip, without slot attribution.
    for (int i; i < record.contributions.Length; i++)
    {
        record.contributions.GetArray(i, contribution);
        raw[contribution.userid != 0 && contribution.userid == record.killerUser ? 1 : 0] += contribution.raw;
    }
    raw[MAXPLAYERS + WTCH_GOTSLASH] = record.slashed;
    raw[MAXPLAYERS + WTCH_STARTLED] = record.startled;
    raw[MAXPLAYERS + WTCH_CROWNSHOT] = record.crownShot;
    raw[MAXPLAYERS + WTCH_CROWNTYPE] = record.crownType;
    DataPack snapshot = new DataPack();
    snapshot.WriteCell(epoch);
    snapshot.WriteCell(record.killerUser);
    snapshot.WriteCell(record.killerLife);
    snapshot.WriteCell(record.killerHealth);
    snapshot.WriteCell(record.reference);
    snapshot.WriteCell(record.oneShot);
    for (int i; i < sizeof(raw); i++) snapshot.WriteCell(raw[i]);
    delete record.contributions;
    g_Witches.SetArray(index, record);
    CreateTimer(WITCH_CHECK_TIME, Timer_CheckWitchCrown, snapshot, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

Action Timer_CheckWitchCrown(Handle timer, DataPack snapshot)
{
    snapshot.Reset();
    int epoch = snapshot.ReadCell();
    int attacker = GetClientOfUserId(snapshot.ReadCell());
    int life = snapshot.ReadCell(), health = snapshot.ReadCell();
    int reference = snapshot.ReadCell();
    bool oneShot = view_as<bool>(snapshot.ReadCell());
    int raw[MAXPLAYERS + DMGARRAYEXT];
    for (int i; i < sizeof(raw); i++) raw[i] = snapshot.ReadCell();
    if (epoch != g_SkillEpoch || !IsValidSurvivor(attacker) || life != g_SurvivorLife[attacker]) return Plugin_Stop;
    int killerRaw = raw[1];
    raw[1] = 0;
    raw[attacker] = killerRaw;
    CoopSkill skill = CheckWitchCrown(reference, attacker, raw, oneShot);
    PublishKill(attacker, 0, skill, 7, "", health);
    return Plugin_Stop;
}

void WitchDestroyed(int entity)
{
    if (entity <= MaxClients || entity >= sizeof(g_WitchSlot)) return;
    int index = g_WitchSlot[entity] - 1;
    g_WitchSlot[entity] = 0;
    if (index < 0) return;
    WitchRecord record;
    g_Witches.GetArray(index, record);
    // Deletion is not death. True death owns pending data independent of the
    // entity slot; no delayed .15-second trie cleanup is needed.
    if (!record.killed)
    {
        delete record.contributions;
        g_Witches.SetArray(index, record);
    }
}

void WitchSurvivorDeath(Event event, const char[] name, bool dontBroadcast)
{
    WitchReportSurvivor(event);
}
void WitchSurvivorIncap(Event event, const char[] name, bool dontBroadcast)
{
    if (g_WdaIncap.BoolValue) WitchReportSurvivor(event);
}
void WitchReportSurvivor(Event event)
{
    if (!IsValidSurvivor(GetClientOfUserId(event.GetInt("userid")))) return;
    WitchRecord record;
    int entity = event.GetInt("attackerentid");
    int index = WitchFind(entity, record);
    if (index < 0 || record.killed) return;
    int health = GetEntProp(entity, Prop_Data, "m_iHealth");
    record.remaining = health > 0 ? health : 0;
    WitchPrintDamage(record, record.remaining > 0);
    // Preserve WDA's one-time live report even outside the live-round gate.
    if (record.remaining > 0) record.printed = true;
    g_Witches.SetArray(index, record);
}
