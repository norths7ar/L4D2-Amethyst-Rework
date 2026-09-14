#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

// Adapted from Visor / A1m`'s l4d2_sniper_bodyshot (Competitive Framework).
// TraceAttack runs before the engine's stomach multiplier: compensate without
// replacing the incoming damage, preserving falloff and other damage modifiers.
public Plugin myinfo = {
    name = "Coop Sniper Hunter Bodyshot", author = "Visor, A1m`, norths7ar",
    description = "Remove all sniper stomach bonuses against Hunters", version = "3.0.0"
};
public void OnPluginStart() {
    for (int client = 1; client <= MaxClients; client++)
        if (IsClientInGame(client)) OnClientPutInServer(client);
}
public void OnClientPutInServer(int client) { SDKHook(client, SDKHook_TraceAttack, TraceAttack); }
public Action TraceAttack(int victim, int &attacker, int &inflictor, float &damage,
    int &damageType, int &ammoType, int hitbox, int hitgroup) {
    if (hitgroup != 3 || !(damageType & DMG_BULLET) || victim < 1 || victim > MaxClients
        || !IsClientInGame(victim) || GetClientTeam(victim) != 3
        || GetEntProp(victim, Prop_Send, "m_zombieClass") != 3
        || attacker < 1 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2) return Plugin_Continue;
    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon)) return Plugin_Continue;
    char classname[64]; GetEntityClassname(weapon, classname, sizeof(classname));
    if (!StrEqual(classname, "weapon_hunting_rifle") && !StrEqual(classname, "weapon_sniper_military")
        && !StrEqual(classname, "weapon_sniper_scout") && !StrEqual(classname, "weapon_sniper_awp")) return Plugin_Continue;
    damage /= 1.25;
    return Plugin_Changed;
}
