// Hunter flight tracking follows Rework Realtime Stats (Griffin/Philogl/Sir/A1m`).
// Damage/assists cover this life; hit counts count distinct weapon_fire sequences,
// never individual pellets. Resetting only on spawn prevents a grounded chip from
// masquerading as an unassisted one-shot when the Hunter subsequently jumps.
bool g_HunterPouncing[MAXPLAYERS + 1];
Handle g_HunterGroundTimer[MAXPLAYERS + 1];
int g_HunterDamage[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_HunterHits[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_HunterLastShot[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_HunterShotSerial[MAXPLAYERS + 1];
int g_HunterAssistUser[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_HunterOnlySmg[MAXPLAYERS + 1][MAXPLAYERS + 1];

void HunterReset(int victim)
{
    g_HunterPouncing[victim] = false;
    delete g_HunterGroundTimer[victim];
    for (int actor = 1; actor <= MaxClients; actor++)
    {
        g_HunterDamage[victim][actor] = 0;
        g_HunterHits[victim][actor] = 0;
        g_HunterLastShot[victim][actor] = -1;
        g_HunterAssistUser[victim][actor] = 0;
        g_HunterOnlySmg[victim][actor] = true;
    }
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
    int damage = GetEventInt(event, "dmg_health");
    if (damage <= 0) return;
    g_HunterDamage[victim][actor] += damage;
    g_HunterAssistUser[victim][actor] = GetClientUserId(actor);
    char weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    if (StrContains(weapon, "smg") != 0) g_HunterOnlySmg[victim][actor] = false;
    if (g_HunterLastShot[victim][actor] != g_HunterShotSerial[actor])
    {
        g_HunterHits[victim][actor]++;
        g_HunterLastShot[victim][actor] = g_HunterShotSerial[actor];
    }
}

void HunterAssistNames(int victim, int actor, char[] names, int maxlen)
{
    names[0] = '\0';
    int assisters[MAXPLAYERS + 1], count;
    for (int other = 1; other <= MaxClients; other++)
    {
        if (other == actor || !g_HunterDamage[victim][other]) continue;
        // Keep the original damage-descending assist order.
        int index = count++;
        while (index > 0 && g_HunterDamage[victim][assisters[index - 1]] < g_HunterDamage[victim][other])
        {
            assisters[index] = assisters[index - 1];
            index--;
        }
        assisters[index] = other;
    }
    for (int i = 0; i < count; i++)
    {
        int other = assisters[i];
        int client = GetClientOfUserId(g_HunterAssistUser[victim][other]);
        char assist[128];
        if (client > 0) GetClientName(client, assist, sizeof(assist));
        else strcopy(assist, sizeof(assist), "disconnected");
        int shots = g_HunterHits[victim][other];
        Format(assist, sizeof(assist), "%s (%d/%d shot%s)", assist, g_HunterDamage[victim][other], shots, shots == 1 ? "" : "s");
        if (names[0]) StrCat(names, maxlen, ", ");
        StrCat(names, maxlen, assist);
    }
}

void HunterDeath(Handle event, int victim, int actor)
{
    if (!IsValidSurvivor(actor) || !g_HunterPouncing[victim] || g_iSpecialVictim[victim] > 0) return;
    bool team;
    for (int other = 1; other <= MaxClients; other++)
        if (other != actor && g_HunterDamage[victim][other] > 0) team = true;
    char weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    int shots = g_HunterHits[victim][actor];
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
        else if (shots > 0 && shots <= 3 && g_HunterOnlySmg[victim][actor] && StrContains(weapon, "smg") == 0) skill = Skill_HunterSmg;
    }
    RecordSkill(actor, victim, skill);
    g_HunterPouncing[victim] = false;
}
