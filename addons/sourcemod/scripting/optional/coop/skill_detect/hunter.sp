// Hunter flight tracking follows Rework Realtime Stats (Griffin/Philogl/Sir/A1m`).
// Damage/assists cover this life; hit counts count distinct weapon_fire sequences,
// never individual pellets. Resetting only on spawn prevents a grounded chip from
// masquerading as an unassisted one-shot when the Hunter subsequently jumps.
bool g_HunterPouncing[MAXPLAYERS + 1];
Handle g_HunterGroundTimer[MAXPLAYERS + 1];
// Contributions belong to a userid, not a reusable client slot. Each victim's
// list survives contributor disconnects and is released when that life resets.
enum struct HunterContribution
{
    int userid;
    int slot; // Preserve the original slot-ascending tie order in assist text.
    int damage;
    int shots;
    int lastShot;
    bool onlySmg;
}

ArrayList g_HunterContributions[MAXPLAYERS + 1];
int g_HunterShotSerial[MAXPLAYERS + 1];

void HunterReset(int victim)
{
    g_HunterPouncing[victim] = false;
    delete g_HunterGroundTimer[victim];
    delete g_HunterContributions[victim];
}

int HunterGetContribution(int victim, int userid, HunterContribution contribution)
{
    if (g_HunterContributions[victim] == null) return -1;
    int index = g_HunterContributions[victim].FindValue(userid, 0);
    if (index >= 0) g_HunterContributions[victim].GetArray(index, contribution);
    return index;
}

void HunterStartPounce(int client)
{
    g_HunterPouncing[client] = true;
    g_iSpecialVictim[client] = -1;
    delete g_HunterGroundTimer[client];
    g_HunterGroundTimer[client] = CreateTimer(0.5, HunterGroundedCheck, GetClientUserId(client), TIMER_REPEAT);
}

Action HunterGroundedCheck(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidInfected(client) || !IsPlayerAlive(client))
    {
        if (client > 0) g_HunterGroundTimer[client] = null;
        return Plugin_Stop;
    }
    if (!(GetEntityFlags(client) & FL_ONGROUND)) return Plugin_Continue;
    g_HunterPouncing[client] = false;
    g_HunterGroundTimer[client] = null;
    return Plugin_Stop;
}

void HunterWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int actor = GetClientOfUserId(event.GetInt("userid"));
    if (actor > 0) g_HunterShotSerial[actor]++;
}

void HunterHurt(Handle event, int victim, int actor)
{
    if (!IsValidSurvivor(actor)) return;
    int rawDamage = GetEventInt(event, "dmg_health");
    if (rawDamage <= 0) return;
    int damage = SIDamageStats_Consume(victim, rawDamage);
    HunterContribution contribution;
    int userid = GetClientUserId(actor);
    int index = HunterGetContribution(victim, userid, contribution);
    if (index < 0)
    {
        contribution.userid = userid;
        contribution.slot = actor;
        contribution.lastShot = -1;
        contribution.onlySmg = true;
        if (g_HunterContributions[victim] == null)
            g_HunterContributions[victim] = new ArrayList(sizeof(HunterContribution));
        index = g_HunterContributions[victim].PushArray(contribution);
    }
    contribution.damage += damage;
    char weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    if (StrContains(weapon, "smg") != 0) contribution.onlySmg = false;
    // A positive raw hit still counts when the remaining health budget is zero.
    if (contribution.lastShot != g_HunterShotSerial[actor])
    {
        contribution.shots++;
        contribution.lastShot = g_HunterShotSerial[actor];
    }
    g_HunterContributions[victim].SetArray(index, contribution);
}

void HunterAssistNames(int victim, int actor, char[] names, int maxlen)
{
    names[0] = '\0';
    ArrayList contributions = g_HunterContributions[victim];
    if (contributions == null) return;
    int actorUser = GetClientUserId(actor);
    // Slot reuse can leave more contributors than there are concurrent clients.
    int[] assisters = new int[contributions.Length];
    int count;
    HunterContribution other, previous;
    for (int i = 0; i < contributions.Length; i++)
    {
        contributions.GetArray(i, other);
        if (other.userid == actorUser || !other.damage) continue;
        int index = count++;
        while (index > 0)
        {
            contributions.GetArray(assisters[index - 1], previous);
            if (previous.damage > other.damage
                || (previous.damage == other.damage && previous.slot <= other.slot)) break;
            assisters[index] = assisters[index - 1];
            index--;
        }
        assisters[index] = i;
    }
    for (int i = 0; i < count; i++)
    {
        contributions.GetArray(assisters[i], other);
        int client = GetClientOfUserId(other.userid);
        char assist[128];
        if (client > 0) GetClientName(client, assist, sizeof(assist));
        else strcopy(assist, sizeof(assist), "disconnected");
        int shots = other.shots;
        Format(assist, sizeof(assist), "%s (%d/%d shot%s)", assist, other.damage, shots, shots == 1 ? "" : "s");
        if (names[0]) StrCat(names, maxlen, ", ");
        StrCat(names, maxlen, assist);
    }
}

void HunterDeath(Handle event, int victim, int actor)
{
    if (!IsValidSurvivor(actor) || !g_HunterPouncing[victim] || g_iSpecialVictim[victim] > 0) return;
    int actorUser = GetClientUserId(actor);
    HunterContribution contribution, other;
    HunterGetContribution(victim, actorUser, contribution);
    bool team;
    ArrayList contributions = g_HunterContributions[victim];
    if (contributions != null)
    {
        for (int i = 0; i < contributions.Length; i++)
        {
            contributions.GetArray(i, other);
            if (other.userid != actorUser && other.damage > 0) team = true;
        }
    }
    char weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    int shots = contribution.shots;
    CoopSkill skill = team ? Skill_HunterTeam : Skill_HunterSolo;
    // Recognize the finishing technique before assists. Earlier chip damage
    // does not invalidate a melee kill or a sniper/Magnum headshot; these are
    // not claims that this Hunter received only one hit during its whole life.
    if (StrEqual(weapon, "melee")) skill = Skill_HunterMelee;
    else if (GetEventBool(event, "headshot") && StrEqual(weapon, "pistol_magnum")) skill = Skill_HunterMagnum;
    else if (GetEventBool(event, "headshot") && (StrContains(weapon, "sniper_") == 0 || StrEqual(weapon, "hunting_rifle"))) skill = Skill_HunterSniper;
    // As in Skill Detect, only direct grenade hits qualify, not splash kills.
    else if (StrEqual(weapon, "grenade_launcher") && (GetEventInt(event, "type") & (DMG_BLAST | DMG_PLASMA))) skill = Skill_HunterGrenade;
    else if (!team)
    {
        if (shots == 1 && (StrEqual(weapon, "pumpshotgun") || StrEqual(weapon, "shotgun_chrome"))) skill = Skill_HunterShotgun;
        else if (shots > 0 && shots <= 3 && contribution.onlySmg && StrContains(weapon, "smg") == 0) skill = Skill_HunterSmg;
    }
    RecordSkill(actor, victim, skill);
    g_HunterPouncing[victim] = false;
}
