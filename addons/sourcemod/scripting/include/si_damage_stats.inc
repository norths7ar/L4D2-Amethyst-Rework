#if defined _si_damage_stats_included
 #endinput
#endif
#define _si_damage_stats_included

#include <sdkhooks>

// Statistics only: never change damage, event fields or combat decisions.
// Each consumer owns its snapshot; neither plugin depends on the other.
static ArrayList g_SIDamageHealth[MAXPLAYERS + 1];

stock void SIDamageStats_Init()
{
    HookEvent("player_spawn", SIDamageStats_Spawn);
}

public void SIDamageStats_Spawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1) return;
    if (g_SIDamageHealth[client] == null) g_SIDamageHealth[client] = new ArrayList(2);
    else g_SIDamageHealth[client].Clear();
    // Spawn also covers existing clients after the framework's map change.
    // SDKHooks ignores duplicate registrations of the same callback.
    SDKHook(client, SDKHook_OnTakeDamage, SIDamageStats_Before);
    SDKHook(client, SDKHook_OnTakeDamagePost, SIDamageStats_After);
}

public Action SIDamageStats_Before(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
    int health = -1;
    if (GetClientTeam(victim) == 3)
    {
        int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
        if (zombieClass >= 1 && zombieClass <= 6)
        {
            health = GetClientHealth(victim);
            if (health < 0) health = 0;
        }
    }
    // One frame per damage call, including nested damage to the same victim.
    int hit[2];
    hit[0] = health; // Remaining event budget.
    hit[1] = health; // Original HP, independent of event consumption.
    g_SIDamageHealth[victim].PushArray(hit);
    return Plugin_Continue;
}

public void SIDamageStats_After(int victim, int attacker, int inflictor, float damage, int damageType)
{
    int count = g_SIDamageHealth[victim].Length;
    if (count == 0) return;
    int before = g_SIDamageHealth[victim].Get(count - 1, 1);
    g_SIDamageHealth[victim].Erase(count - 1);
    if (count > 1)
    {
        // Nested hits may be world damage and have no survivor statistic.
        // Subtract only the nested loss: current HP may already include the
        // outer hit whose player_hurt listener has not consumed its budget yet.
        int health = GetClientHealth(victim);
        if (health < 0) health = 0;
        int loss = before - health;
        int remaining = g_SIDamageHealth[victim].Get(count - 2);
        if (remaining >= 0 && loss > 0)
            g_SIDamageHealth[victim].Set(count - 2, remaining > loss ? remaining - loss : 0);
    }
}

stock int SIDamageStats_Consume(int victim, int damage)
{
    if (damage <= 0) return 0;
    if (victim < 1 || victim > MaxClients) return damage;
    ArrayList hits = g_SIDamageHealth[victim];
    if (hits == null || hits.Length == 0)
    {
        // A synthetic event has no observed health budget. Preserve its original
        // statistic rather than inventing zero damage or a default class HP.
        return damage;
    }
    int index = hits.Length - 1;
    int health = hits.Get(index);
    if (health < 0) return damage;
    int actual = damage < health ? damage : health;
    // Multiple events from one damage call share its remaining health budget.
    hits.Set(index, health - actual);
    return actual;
}
