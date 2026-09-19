#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <coop_skill_detect>
/**
 * 装逼是游戏第一动力。
 * 受落子视频的启发，爆 ht 带嘟嘟音效，实际打起来也非常带感。
 * Historical name retained; Jockey skeets share the same sound.
 */
public Plugin myinfo =
{
    name = "HunterSkeetSound",
    author = "norths7ar",
    description = "Hunter and Jockey skeet sound from resolved skill events.",
    version = "2.1.0"
};
public void OnMapStart()
{
    PrecacheSound("ui/bigreward.wav");
}
public void OnSkillKillResolved(int survivor, int victim, CoopSkill skill, int stars,
    int zombieClass, const char[] weapon, int healthBefore)
{
    bool hunter = (skill >= Skill_HunterSolo && skill <= Skill_HunterSmg) || skill == Skill_HunterGrenade;
    if (!hunter && skill != Skill_JockeySkeet) return;
    if (survivor > 0 && survivor <= MaxClients && IsClientInGame(survivor))
        EmitSoundToClient(survivor, "ui/bigreward.wav", survivor);
}
