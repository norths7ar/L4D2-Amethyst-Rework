#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

static const char ScriptKeys[][] = {
	"CommonLimit",
	"MobMinSize",
	"MobMaxSize",
	"MegaMobSize"
};

ConVar Limits[sizeof(ScriptKeys)];

public Plugin myinfo =
{
	name = "Director-scripted population limit blocker",
	author = "Tabun",
	description = "Caps scripted common and horde sizes at their current cvar limits.",
	version = "0.5",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

public void OnPluginStart()
{
	Limits[0] = FindConVar("z_common_limit");
	Limits[1] = FindConVar("z_mob_spawn_min_size");
	Limits[2] = FindConVar("z_mob_spawn_max_size");
	Limits[3] = FindConVar("z_mega_mob_size");
}

public Action L4D_OnGetScriptValueInt(const char[] key, int &retVal)
{
	return CapScriptSize(key, retVal);
}

// The VM hook also covers reads inlined by the engine that bypass the older hook.
public Action L4D2_OnGetScriptValueInt(const char[] key, int &retVal, int hScope)
{
	// Only director scopes: unrelated entity script tables must remain untouched.
	for (int level = 0; level <= 4; level++) {
		if (hScope != 0 && hScope == L4D2_GetDirectorScriptScope(level)) {
			return CapScriptSize(key, retVal);
		}
	}
	return Plugin_Continue;
}

Action CapScriptSize(const char[] key, int &retVal)
{
	for (int i = 0; i < sizeof(ScriptKeys); i++) {
		if (strcmp(key, ScriptKeys[i]) != 0) continue;

		// Read live cvars so player-count profile changes apply immediately.
		int limit = Limits[i].IntValue;
		if (retVal > limit) {
			retVal = limit;
			return Plugin_Handled;
		}
		break;
	}
	return Plugin_Continue;
}
