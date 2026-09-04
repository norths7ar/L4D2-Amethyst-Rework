#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

ConVar g_cvEnable;

public Plugin myinfo =
{
	name = "Coop Use Action Speed",
	author = "海洋空氣, norths7ar",
	description = "Adjusts Coop use-action duration for the active player-count profile.",
	version = "1.0.0"
};

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("use_action_speed_enable", "1", "Enable Coop use-action speed control.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
}

public void L4D2_OnStartUseAction_Post(any action, int client, int entity)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	if (action == L4D2UseAction_Button)
	{
		float originalDuration = GetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0);
		float newDuration;

		switch (GetDifficulty())
		{
			case 1:
			{
				newDuration = 0.1;
			}
			case 2:
			{
				newDuration = originalDuration * 0.25;
			}
			case 3:
			{
				newDuration = originalDuration * 0.75;
			}
			case 4:
			{
				newDuration = originalDuration;
			}
		}

		DispatchKeyValueFloat(entity, "use_time", newDuration);
		SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", newDuration);
	}
}

int GetDifficulty()
{
	ConVar difficulty = FindConVar("profile_current");
	if (difficulty == null)
	{
		PrintToServer("[Coop Use Action Speed] profile_controller.smx is not loaded.");
		LogError("profile_controller.smx is not loaded");
		return 4;
	}
	return difficulty.IntValue;
}
