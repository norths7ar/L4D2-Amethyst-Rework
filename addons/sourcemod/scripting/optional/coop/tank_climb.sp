#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

ConVar g_enable, g_lowRate, g_highRate;
bool g_boosted[MAXPLAYERS + 1];
float g_previousRate[MAXPLAYERS + 1], g_appliedRate[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Tank Climb",
	author = "OpenAI",
	description = "Accelerate AI Tank obstacle climbing without changing movement speed",
	version = "1.0.0",
	url = ""
};

public void OnPluginStart()
{
	// Playback-rate approach and defaults follow Anne's l4d2_ai_ladder_boost.
	g_enable = CreateConVar("tank_climb_enable", "1", "Accelerate AI Tank obstacle climbing", _, true, 0.0, true, 1.0);
	g_lowRate = CreateConVar("tank_climb_low_rate", "2.5", "Low obstacle climb animation rate", _, true, 1.0, true, 10.0);
	g_highRate = CreateConVar("tank_climb_high_rate", "3.5", "High obstacle climb animation rate", _, true, 1.0, true, 10.0);
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client)) OnClientPutInServer(client);
}

public void OnClientPutInServer(int client)
{
	g_boosted[client] = false;
	SDKHook(client, SDKHook_PostThinkPost, OnPostThink);
}

public void OnClientDisconnect(int client)
{
	g_boosted[client] = false;
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client)) RestoreRate(client);
}

public void OnPostThink(int client)
{
	if (!g_enable.BoolValue || !IsFakeClient(client) || !IsPlayerAlive(client)
		|| GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_zombieClass") != 8
		|| GetEntityMoveType(client) == MOVETYPE_LADDER)
	{
		RestoreRate(client);
		return;
	}

	// Built-in hulk models share anim_hulk, after their local ragdoll sequence.
	// These are model sequence numbers, NOT Source activity enum values.
	int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
	float rate = 1.0;
	if (sequence >= 16 && sequence <= 19) rate = g_lowRate.FloatValue;
	else if (sequence >= 20 && sequence <= 23) rate = g_highRate.FloatValue;
	if (rate <= 1.0)
	{
		RestoreRate(client);
		return;
	}

	if (!g_boosted[client])
		g_previousRate[client] = GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate");
	g_boosted[client] = true;
	g_appliedRate[client] = rate;
	SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", rate);
}

void RestoreRate(int client)
{
	if (!g_boosted[client]) return;
	// Do not overwrite a rate subsequently assigned by the game or another plugin.
	if (FloatAbs(GetEntPropFloat(client, Prop_Send, "m_flPlaybackRate") - g_appliedRate[client]) < 0.001)
		SetEntPropFloat(client, Prop_Send, "m_flPlaybackRate", g_previousRate[client]);
	g_boosted[client] = false;
}
