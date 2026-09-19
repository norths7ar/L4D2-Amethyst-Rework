#if defined _coop_skill_detect_included
    #endinput
#endif
#define _coop_skill_detect_included

enum CoopSkill
{
    Skill_None,
    Skill_HunterTeam,
    Skill_HunterSolo,
    Skill_HunterMelee,
    Skill_HunterMagnum,
    Skill_HunterSniper,
    Skill_HunterShotgun,
    Skill_HunterSmg,
    Skill_ChargerFull,
    Skill_ChargerHurt,
    Skill_SmokerSelf,
    Skill_JockeySkeet,
    Skill_BoomerFast,
    Skill_WitchCrown,
    Skill_WitchDraw,
    // Append new values so existing consumers keep their enum IDs.
    Skill_HunterGrenade,
    Skill_BoomerPop
};

// Called once per survivor-attributed SI/Witch kill, after skill confirmation.
// survivor/victim are current client indices (victim may be 0 after disconnect,
// and is always 0 for a Witch). weapon is the death event weapon, without weapon_.
// healthBefore is the killer's real health at the kill, before any reward.
// stars are the kill reward tier, not necessarily the chat prefix (Witch uses x3).
forward void OnSkillKillResolved(int survivor, int victim, CoopSkill skill, int stars,
    int zombieClass, const char[] weapon, int healthBefore);

// Mechanics plugins report a successful lethal attempt; the detector publishes
// it only when that same survivor actually kills this victim. No second threshold.
native void Skill_ReportJockeySkeet(int survivor, int jockey);

#if !defined COOP_SKILL_DETECT_IMPL
public SharedPlugin __pl_coop_skill_detect =
{
    name = "coop_skill_detect",
    file = "skill_detect.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_coop_skill_detect_SetNTVOptional()
{
    MarkNativeAsOptional("Skill_ReportJockeySkeet");
}
#endif

#endif
