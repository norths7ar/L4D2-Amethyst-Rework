#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

ConVar g_cvEnable;
int g_startTimeDelta;
int g_buttonRef[MAXPLAYERS + 1];
int g_startOffset[MAXPLAYERS + 1];
float g_originalStart[MAXPLAYERS + 1];
float g_adjustedStart[MAXPLAYERS + 1];
float g_originalDuration[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Coop Use Action Speed",
	author = "海洋空氣, norths7ar",
	description = "Adjusts Coop use-action duration for the active player-count profile.",
	version = "1.1.0"
};

public void OnPluginStart()
{
	GameData data = new GameData("use_action_speed");
	if (data == null) SetFailState("Missing use_action_speed gamedata.");
	g_startTimeDelta = data.GetOffset("CButtonTimed::StartTimeFromUseTime");
	delete data;
	if (g_startTimeDelta < 0) SetFailState("Missing CButtonTimed start-time offset.");
	g_cvEnable = CreateConVar("use_action_speed_enable", "1", "Enable Coop use-action speed control.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEnable.AddChangeHook(OnEnabledChanged);
	OnMapStart();
}

public void OnMapStart()
{
	for (int client = 1; client <= MaxClients; client++)
		g_buttonRef[client] = INVALID_ENT_REFERENCE;
}

public void L4D2_OnStartUseAction_Post(any action, int client, int entity)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client)) return;
	// A new native action has already reset its own timer. Never restore an old
	// attempt into it, even when the same button is being retried.
	g_buttonRef[client] = INVALID_ENT_REFERENCE;
	if (!g_cvEnable.BoolValue || action != L4D2UseAction_Button || entity <= MaxClients || !IsValidEntity(entity)) return;
	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (!StrEqual(classname, "func_button_timed")) return;

	float originalDuration = float(GetEntProp(entity, Prop_Data, "m_nUseTime"));
	if (originalDuration <= 0.0) return;
	float duration = originalDuration;
	ConVar profile = FindConVar("profile_current");
	if (profile == null) return;
	switch (profile.IntValue)
	{
		case 1: duration = 0.1;
		case 2: duration *= 0.25;
		case 3: duration *= 0.75;
	}
	if (duration == originalDuration) return;

	int offset = FindDataMapInfo(entity, "m_nUseTime") + g_startTimeDelta;
	float start = GetEntDataFloat(entity, offset);
	float barStart = GetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime");
	// The private field must still be the fresh native start time. Fail closed
	// if an engine update changes the layout, rather than writing unrelated data.
	if (FloatAbs(start - barStart) > 0.1 || FloatAbs(start - GetGameTime()) > 0.1)
	{
		LogError("Unexpected func_button_timed start time; leaving native timing unchanged.");
		return;
	}
	g_buttonRef[client] = EntIndexToEntRef(entity);
	g_startOffset[client] = offset;
	g_originalStart[client] = start;
	g_originalDuration[client] = originalDuration;
	g_adjustedStart[client] = start + duration - originalDuration;
	// Native completion compares start + integer use_time with curtime. Move
	// only the float start; leave map-authored use_time and the hold heartbeat
	// untouched, retaining native cancellation, OnUnpressed and OnTimeUp.
	SetEntDataFloat(entity, offset, g_adjustedStart[client]);
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", duration);
}

void RestoreAction(int client)
{
	int entity = EntRefToEntIndex(g_buttonRef[client]);
	g_buttonRef[client] = INVALID_ENT_REFERENCE;
	if (entity <= MaxClients || !IsClientInGame(client)
		|| GetEntPropEnt(client, Prop_Send, "m_useActionTarget") != entity) return;
	// Do not overwrite a subsequent user's action or a map/plugin timer change.
	if (GetEntDataFloat(entity, g_startOffset[client]) != g_adjustedStart[client]) return;
	SetEntDataFloat(entity, g_startOffset[client], g_originalStart[client]);
	SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", g_originalDuration[client]);
}

void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!convar.BoolValue)
		for (int client = 1; client <= MaxClients; client++) RestoreAction(client);
}

public void OnClientDisconnect(int client)
{
	RestoreAction(client);
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++) RestoreAction(client);
}
