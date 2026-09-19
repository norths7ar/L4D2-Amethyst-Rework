// Resolved kill bus. Damage hooks only record a candidate; a real death commits it.
GlobalForward g_KillForward;
ArrayList g_KillRecords;
int g_SkillEpoch;
int g_SurvivorLife[MAXPLAYERS + 1];
int g_PendingKill[MAXPLAYERS + 1];
int g_CandidateActor[MAXPLAYERS + 1];
CoopSkill g_CandidateSkill[MAXPLAYERS + 1];
int g_CandidateDamage[MAXPLAYERS + 1];

enum struct SkillKillRecord
{
    bool resolved;
    int actorUser;
    int actorLife;
    int victimUser;
    int zombieClass;
    int health;
    CoopSkill skill;
    int shots;
    int damage;
    int skillDamage;
    float lifetime;
    char weapon[64];
    char assists[256];
}

void SkillEventsStart()
{
    g_KillRecords = new ArrayList(sizeof(SkillKillRecord));
    SkillRoundReset();
}

void SkillRoundReset()
{
    g_SkillEpoch++;
    g_KillRecords.Clear();
    for (int client = 1; client <= MaxClients; client++) SkillSpawn(client);
}

void SkillSpawn(int client)
{
    g_SurvivorLife[client]++;
    g_PendingKill[client] = -1;
    g_CandidateActor[client] = 0;
    g_CandidateSkill[client] = Skill_None;
    g_CandidateDamage[client] = 0;
    g_iSpecialVictim[client] = -1;
    HunterReset(client);
}

int SkillRewardTier(CoopSkill skill, float lifetime = 0.0)
{
    switch (skill)
    {
        case Skill_None, Skill_HunterTeam, Skill_BoomerPop: return 0;
        case Skill_HunterSolo, Skill_WitchCrown: return 1;
        case Skill_ChargerFull: return 3;
        case Skill_BoomerFast:
        {
            if (lifetime <= 0.5) return 3;
            if (lifetime <= 1.4) return 2;
            return 1;
        }
    }
    return 2;
}

void RecordSkill(int actor, int victim, CoopSkill skill, int damage = 0)
{
    if (!IsValidSurvivor(actor) || !IsValidInfected(victim)) return;
    g_CandidateActor[victim] = GetClientUserId(actor);
    g_CandidateSkill[victim] = skill;
    g_CandidateDamage[victim] = damage;
    // Boomer explosion can arrive after player_death; update the same queued kill.
    int index = g_PendingKill[victim];
    if (index >= 0 && index < g_KillRecords.Length)
    {
        SkillKillRecord record;
        g_KillRecords.GetArray(index, record);
        if (!record.resolved && record.actorUser == GetClientUserId(actor))
        {
            record.skill = skill;
            record.skillDamage = damage;
            // Keep the spawn-to-death time captured by SkillDeath. The later
            // boomer explosion must not move a kill across a speed boundary.
            g_KillRecords.SetArray(index, record);
        }
    }
}

public any Native_ReportJockeySkeet(Handle plugin, int numParams)
{
    int actor = GetNativeCell(1), victim = GetNativeCell(2);
    if (IsValidInfected(victim) && IsPlayerAlive(victim)
        && GetEntProp(victim, Prop_Send, "m_zombieClass") == ZC_JOCKEY)
    {
        RecordSkill(actor, victim, Skill_JockeySkeet);
        RequestFrame(ClearUncommittedJockey, GetClientUserId(victim));
    }
    return 0;
}

void ClearUncommittedJockey(int userid)
{
    int victim = GetClientOfUserId(userid);
    if (IsValidInfected(victim) && IsPlayerAlive(victim) && g_CandidateSkill[victim] == Skill_JockeySkeet)
    {
        g_CandidateSkill[victim] = Skill_None;
        g_CandidateActor[victim] = 0;
    }
}

void SkillDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int actor = GetClientOfUserId(event.GetInt("attacker"));
    if (!IsValidInfected(victim) || !IsValidSurvivor(actor)) return;
    int cls = GetEntProp(victim, Prop_Send, "m_zombieClass");
    if (cls < 1 || cls > 6 || g_PendingKill[victim] >= 0) return;
    SkillKillRecord record;
    record.actorUser = GetClientUserId(actor);
    record.actorLife = g_SurvivorLife[actor];
    record.victimUser = GetClientUserId(victim);
    record.zombieClass = cls;
    record.health = GetClientHealth(actor);
    record.lifetime = GetGameTime() - g_fSpawnTime[victim];
    record.skill = g_CandidateActor[victim] == record.actorUser ? g_CandidateSkill[victim] : Skill_None;
    record.skillDamage = g_CandidateActor[victim] == record.actorUser ? g_CandidateDamage[victim] : 0;
    event.GetString("weapon", record.weapon, sizeof(record.weapon));
    record.shots = g_HunterHits[victim][actor];
    record.damage = g_HunterDamage[victim][actor];
    HunterAssistNames(victim, actor, record.assists, sizeof(record.assists));
    int index = g_KillRecords.PushArray(record);
    g_PendingKill[victim] = index;
    DataPack pack = new DataPack();
    pack.WriteCell(g_SkillEpoch);
    pack.WriteCell(index);
    if (cls == ZC_BOOMER)
        CreateTimer(0.2, SkillBoomerSettled, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    else
        RequestFrame(SkillFrameSettled, pack);
}

Action SkillBoomerSettled(Handle timer, DataPack pack)
{
    ResolveKill(pack);
    return Plugin_Stop;
}

void SkillFrameSettled(DataPack pack)
{
    ResolveKill(pack);
    delete pack;
}

void ResolveKill(DataPack pack)
{
    pack.Reset();
    int epoch = pack.ReadCell(), index = pack.ReadCell();
    if (epoch != g_SkillEpoch || index >= g_KillRecords.Length) return;
    SkillKillRecord record;
    g_KillRecords.GetArray(index, record);
    if (record.resolved) return;
    record.resolved = true;
    g_KillRecords.SetArray(index, record);
    int actor = GetClientOfUserId(record.actorUser);
    if (!IsValidSurvivor(actor) || record.actorLife != g_SurvivorLife[actor]) return;
    int victim = GetClientOfUserId(record.victimUser);
    ReportSkillKill(actor, record);
    PublishKill(actor, victim, record.skill, record.zombieClass, record.weapon, record.health, record.lifetime);
}

void PublishKill(int actor, int victim, CoopSkill skill, int cls, const char[] weapon, int health, float lifetime = 0.0)
{
    if (cls == 7)
    {
        SkillKillRecord record;
        record.skill = skill;
        ReportSkillKill(actor, record);
    }
    Call_StartForward(g_KillForward);
    Call_PushCell(actor);
    Call_PushCell(victim);
    Call_PushCell(skill);
    Call_PushCell(SkillRewardTier(skill, lifetime));
    Call_PushCell(cls);
    Call_PushString(weapon);
    Call_PushCell(health);
    Call_Finish();
}
