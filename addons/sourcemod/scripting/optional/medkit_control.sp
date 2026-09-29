#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

int g_targetUserId[MAXPLAYERS + 1];
float g_tempHealth[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Coop medkit control",
	author = "norths7ar",
	description = "Retains temporary health not replaced by medkit healing.",
	version = "1.0.0"
};

public void OnPluginStart()
{
	HookEvent("heal_begin", EventHealBegin, EventHookMode_Pre);
	HookEvent("heal_end", EventHealEnd, EventHookMode_Pre);
	HookEvent("heal_success", EventHealSuccess);
}

public void OnClientPutInServer(int client)
{
	g_targetUserId[client] = 0;
	g_tempHealth[client] = 0.0;
}

void EventHealBegin(Event event, const char[] name, bool dontBroadcast)
{
	int healer = GetClientOfUserId(event.GetInt("userid"));
	if (!healer) return;
	g_targetUserId[healer] = event.GetInt("subject");
	g_tempHealth[healer] = 0.0;
}

void EventHealEnd(Event event, const char[] name, bool dontBroadcast)
{
	int healer = GetClientOfUserId(event.GetInt("userid"));
	if (!healer) return;
	// heal_end's subject is unreliable; use heal_begin's target, as godframes_control does.
	int target = GetClientOfUserId(g_targetUserId[healer]);
	if (!target || !IsPlayerAlive(target)) return;
	g_tempHealth[healer] = L4D_GetTempHealth(target);
}

void EventHealSuccess(Event event, const char[] name, bool dontBroadcast)
{
	int healer = GetClientOfUserId(event.GetInt("userid"));
	if (!healer) return;
	int targetUserId = event.GetInt("subject");
	float remaining = g_tempHealth[healer] - float(event.GetInt("health_restored"));
	bool matches = g_targetUserId[healer] == targetUserId;
	g_targetUserId[healer] = 0;
	g_tempHealth[healer] = 0.0;
	int target = GetClientOfUserId(targetUserId);
	if (!matches || !target || !IsPlayerAlive(target) || remaining <= 0.0) return;
	float room = float(GetEntProp(target, Prop_Data, "m_iMaxHealth") - GetClientHealth(target));
	if (remaining > room) remaining = room;
	if (remaining > 0.0) L4D_SetTempHealth(target, remaining);
}
