/*
*	First Map - Skip Intro Cutscenes
*	Copyright (C) 2022 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION		"1.14.0"

/*======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] First Map - Skip Intro Cutscenes
*	Author	:	SilverShot
*	Descrp	:	Makes players skip seeing the intro cutscene on first maps, so they can move right away.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=321993
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.13 (10-Apr-2022)
	- Fixed the "l4d_skip_intro_modes_tog" cvar always turning off the plugin. Thanks to "Thefollors" for reporting.

1.12 (01-Dec-2021)
	- Changes to fix warnings when compiling on SourceMod 1.11.
	- Minor change to fix bad coding practice.

1.11 (11-Jul-2021)
	- Slight optimization and change to fix the unhook event errors.

1.10 (21-Jun-2021)
	- Changes to fix the last update potentially not working for all maps.

1.9 (20-Jun-2021)
	- Changed some code to prevent adding multiple identical outputs.

1.8 (15-Feb-2021)
	- Blocked working on finale maps when not using left4dhooks. Thanks to "Zheldorg" for reporting.

1.7 (10-Oct-2020)
	- Minor change again to hopefully fix unhook event errors.

1.6 (05-Oct-2020)
	- Changes to hopefully fix unhook event errors.

1.5 (01-Oct-2020)
	- Changes to support "The Last Stand" update.
	- Fixed lateload not enabling the plugin.

1.4 (10-May-2020)
	- Added cvars: "l4d_skip_intro_allow", "l4d_skip_intro_modes", "l4d_skip_intro_modes_off" and "l4d_skip_intro_modes_tog".
	- Cvar config saved as "l4d_skip_intro.cfg" in "cfgs/sourcemod" folder.
	- Extra checks to skip intro on some addon maps that use a different entity.
	- Thanks to "TiTz" for reporting.

1.3 (29-Apr-2020)
	- Increased the timer delay from 0.1 to 1.0 due to some conditions failing to skip intro. Thanks to "TiTz" for reporting.

1.2 (08-Apr-2020)
	- Added a check incase the director entity was not found. Thanks to "TiTz" for reporting.

1.1 (16-Mar-2020)
	- Fixed not working on all maps when info_director is named differently.

1.0 (10-Mar-2020)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define CVAR_FLAGS			FCVAR_NOTIFY


ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog;
ConVar g_readyPolicy, g_playCount;
Handle g_watchTimer;
ArrayList g_skippedCameras;
char g_chapter[64];
int g_attempts;
bool g_roundOpen, g_roundLive, g_lateLoad, g_directorReleased;

bool g_bCvarAllow, g_bMapStarted, g_bLeft4DHooks, g_bFaded, g_bOutput1, g_bOutput2;



// ====================================================================================================
//					PLUGIN INFO / START
// ====================================================================================================
native bool IsInReady();
native bool L4D_IsFirstMapInScenario(); // So it compiles on forum, optional native.

public Plugin myinfo =
{
	name = "[L4D & L4D2] Skip Intro Cutscenes",
	author = "SilverShot",
	description = "Skips intros, with optional per-chapter attempt policy during ready-up.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=321993"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test != Engine_Left4Dead && test != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	MarkNativeAsOptional("L4D_IsFirstMapInScenario");
	MarkNativeAsOptional("IsInReady");
	g_lateLoad = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	g_bLeft4DHooks = GetFeatureStatus(FeatureType_Native, "L4D_IsFirstMapInScenario") == FeatureStatus_Available;
}

public void OnPluginStart()
{
	g_skippedCameras = new ArrayList();
	g_readyPolicy = CreateConVar("l4d_skip_intro_ready", "0", "Use per-chapter attempt policy during ready-up; 0 retains legacy first-map behavior.", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_playCount = CreateConVar("l4d_skip_intro_play_count", "0", "Ready policy: attempts to play before skipping; -1 always plays, 0 always skips.", CVAR_FLAGS, true, -1.0);
	g_readyPolicy.AddChangeHook(ConVarChanged_Allow);
	g_playCount.AddChangeHook(ConVarChanged_Allow);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	g_hCvarAllow = CreateConVar(	"l4d_skip_intro_allow",			"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes = CreateConVar(	"l4d_skip_intro_modes",			"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff = CreateConVar(	"l4d_skip_intro_modes_off",		"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog = CreateConVar(	"l4d_skip_intro_modes_tog",		"0",			"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	CreateConVar(					"l4d_skip_intro_version",		PLUGIN_VERSION,	"Skip Intro plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,			"l4d_skip_intro");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);

	HookEvent("gameinstructor_nodraw", Event_NoDraw, EventHookMode_PostNoCopy); // Because round_start can be too early when clients are not in-game. This triggers when the cutscene starts.
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
	if (g_lateLoad) { BeginAttempt(); g_lateLoad = false; }
	StartReadyWatch();
}

public void OnMapStart()
{
	g_bMapStarted = true;
	UpdateChapter();
}

public void OnMapEnd()
{
	g_bMapStarted = false;
	StopReadyWatch();
	g_roundOpen = false;
	g_roundLive = false;
}

void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
	StartReadyWatch();
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		g_bCvarAllow = true;
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		g_bCvarAllow = false;
	}
}

int g_iCurrentMode;
bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == null )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog != 0 )
	{
		if( g_bMapStarted == false )
			return false;

		g_iCurrentMode = 0;

		int entity = CreateEntityByName("info_gamemode");
		if( IsValidEntity(entity) )
		{
			DispatchSpawn(entity);
			HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
			ActivateEntity(entity);
			AcceptEntityInput(entity, "PostSpawnActivate");
			if( IsValidEntity(entity) ) // Because sometimes "PostSpawnActivate" seems to kill the ent.
				RemoveEdict(entity); // Because multiple plugins creating at once, avoid too many duplicate ents in the same frame
		}

		if( g_iCurrentMode == 0 )
			return false;

		if( !(iCvarModesTog & g_iCurrentMode) )
			return false;
	}

	char sGameModes[64], sGameMode[64];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	Format(sGameMode, sizeof(sGameMode), ",%s,", sGameMode);

	g_hCvarModes.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) == -1 )
			return false;
	}

	g_hCvarModesOff.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) != -1 )
			return false;
	}

	return true;
}

void OnGamemode(const char[] output, int caller, int activator, float delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
	else if( strcmp(output, "OnScavenge") == 0 )
		g_iCurrentMode = 8;
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
void Event_NoDraw(Event event, const char[] name, bool dontBroadcast)
{
	if (g_readyPolicy.BoolValue) { StartReadyWatch(); return; }
	if( g_bCvarAllow && (!g_bLeft4DHooks || L4D_IsFirstMapInScenario()) )
	{
		// Block finale
		if( !g_bLeft4DHooks && FindEntityByClassname(-1, "trigger_finale") != INVALID_ENT_REFERENCE )
			return;

		g_bFaded = false;
		g_bOutput1 = false;
		g_bOutput2 = false;

		// Multiple times to make sure it works
		CreateTimer(1.0, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(5.0, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(6.0, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(6.5, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(7.0, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(8.0, TimerStart, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action TimerStart(Handle timer)
{
	if (!g_bCvarAllow || g_readyPolicy.BoolValue) return Plugin_Stop;
	char buffer[128]; // 128 should be long enough, 3rd party maps could be longer than Valves ~52 chars (including OnUser1 below)?

	char director[32];
	int entity = FindEntityByClassname(-1, "info_director"); // Every map should have a director, but apparently some still throw -1 error.
	if( entity != -1 )
	{
		GetEntPropString(entity, Prop_Data, "m_iName", director, sizeof(director));

		for( int i = 0; i < 2; i++ )
		{
			entity = -1;
			while( (entity = FindEntityByClassname(entity, i == 0 ? "point_viewcontrol_survivor" : "point_viewcontrol_multiplayer")) != INVALID_ENT_REFERENCE )
			{
				// ALLOW CONTROL
				if( (i == 0 && !g_bOutput1) || (i == 1 && !g_bOutput2) )
				{
					// Testing outputs
					// static int tester;
					// FormatEx(buffer, sizeof(buffer), "OnUser1 silvers_point_cmd:Command:say test%d:0:-1", tester++);
					// SetVariantString(buffer);
					// AcceptEntityInput(entity, "AddOutput");

					// ALLOW MOVEMENT
					FormatEx(buffer, sizeof(buffer), "OnUser1 %s:ReleaseSurvivorPositions::0:-1", director);
					SetVariantString(buffer);
					AcceptEntityInput(entity, "AddOutput");

					FormatEx(buffer, sizeof(buffer), "OnUser1 %s:FinishIntro::0:-1", director);
					SetVariantString(buffer);
					AcceptEntityInput(entity, "AddOutput");

					AcceptEntityInput(entity, "FireUser1");

					if( i == 0 )			g_bOutput1 = true;
					else if( i == 1 )		g_bOutput2 = true;
				} else {
					AcceptEntityInput(entity, "FireUser1");
				}

				// STOP SCENE
				SetVariantString("!self");
				AcceptEntityInput(entity, "StartMovement");

				// RemoveEntity(entity); // Kill works good, but maybe some 3rd party maps use this for other scenes, so better to not kill.. especially if no left4dhooks and checking every map.
			}
		}

		// FADE IN
		if( (g_bOutput1 || g_bOutput2 ) && !g_bFaded )
		{
			g_bFaded = true;

			entity = CreateEntityByName("env_fade");
			DispatchKeyValue(entity, "spawnflags", "1");
			DispatchKeyValue(entity, "rendercolor", "0 0 0");
			DispatchKeyValue(entity, "renderamt", "255");
			DispatchKeyValue(entity, "holdtime", "1");
			DispatchKeyValue(entity, "duration", "1");
			DispatchSpawn(entity);
			AcceptEntityInput(entity, "Fade");

			SetVariantString("OnUser1 !self:Kill::2.5:-1");
			AcceptEntityInput(entity, "AddOutput");
			AcceptEntityInput(entity, "FireUser1");

			// Testing outputs
			// entity = CreateEntityByName("point_servercommand");
			// DispatchKeyValue(entity, "targetname", "silvers_point_cmd");
			// DispatchSpawn(entity);
		}
	}

	return Plugin_Continue;
}
// Ready policy is opt-in so shared competitive configurations retain the
// upstream first-map behavior. Round boundaries, not ready forwards, count.
void UpdateChapter()
{
	char map[64];
	GetCurrentMap(map, sizeof(map));
	if (!StrEqual(map, g_chapter))
	{
		strcopy(g_chapter, sizeof(g_chapter), map);
		g_attempts = 0;
		g_roundOpen = false;
		g_roundLive = false;
	}
}

void BeginAttempt()
{
	UpdateChapter();
	if (g_roundOpen) return;
	g_roundOpen = true;
	g_roundLive = false;
	g_attempts++;
	g_directorReleased = false;
	g_skippedCameras.Clear();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	BeginAttempt();
	StartReadyWatch();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	StopReadyWatch();
	g_roundOpen = false;
	g_roundLive = true;
}

public void OnReadyUpInitiate()
{
	// May fire several times during one round, or before round_start.
	StartReadyWatch();
}

public void OnRoundIsLive()
{
	g_roundLive = true;
	StopReadyWatch();
}

public void OnPluginEnd()
{
	StopReadyWatch();
}

bool CanWatchReadyIntro()
{
	return g_bCvarAllow && g_readyPolicy.BoolValue && g_roundOpen && !g_roundLive
		&& g_playCount.IntValue >= 0 && g_attempts > g_playCount.IntValue
		&& GetFeatureStatus(FeatureType_Native, "IsInReady") == FeatureStatus_Available
		&& IsInReady();
}

void StopReadyWatch()
{
	delete g_watchTimer;
	g_watchTimer = null;
}

void StartReadyWatch()
{
	if (!CanWatchReadyIntro()) { StopReadyWatch(); return; }
	if (g_watchTimer == null)
		g_watchTimer = CreateTimer(0.5, TimerReadyIntro, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action TimerReadyIntro(Handle timer)
{
	if (!CanWatchReadyIntro()) { g_watchTimer = null; return Plugin_Stop; }
	bool found;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client)) continue;
		int camera = GetEntPropEnt(client, Prop_Send, "m_hViewEntity");
		if (camera <= MaxClients || !IsValidEntity(camera)) continue;
		char classname[64];
		GetEntityClassname(camera, classname, sizeof(classname));
		bool survivorCamera = StrEqual(classname, "point_viewcontrol_survivor");
		if (!survivorCamera && !StrEqual(classname, "point_viewcontrol_multiplayer")
			&& !StrEqual(classname, "point_viewcontrol")) continue;
		found = true;
		int reference = EntIndexToEntRef(camera);
		if (g_skippedCameras.FindValue(reference) == -1)
		{
			g_skippedCameras.Push(reference);
			// Keep the map's existing camera output, but never repeatedly fire it.
			AcceptEntityInput(camera, "FireUser1");
		}
		camera = EntRefToEntIndex(reference);
		if (camera <= MaxClients) continue;
		// Preserve upstream survivor-camera movement/finish handling. Other
		// cameras expose Disable. Never delete cameras reused later by the map.
		if (survivorCamera)
		{
			SetVariantString("!self");
			AcceptEntityInput(camera, "StartMovement");
		}
		else AcceptEntityInput(camera, "Disable");
	}
	if (found && !g_directorReleased)
	{
		g_directorReleased = true;
		int director = FindEntityByClassname(-1, "info_director");
		if (director != -1)
		{
			AcceptEntityInput(director, "ReleaseSurvivorPositions");
			AcceptEntityInput(director, "FinishIntro");
		}
		// Do not clear player flags: ready-up owns its own movement protection.
		int fade = CreateEntityByName("env_fade");
		if (fade != -1)
		{
			DispatchKeyValue(fade, "spawnflags", "1");
			DispatchKeyValue(fade, "rendercolor", "0 0 0");
			DispatchKeyValue(fade, "renderamt", "255");
			DispatchKeyValue(fade, "holdtime", "0");
			DispatchKeyValue(fade, "duration", "0.5");
			DispatchSpawn(fade);
			AcceptEntityInput(fade, "Fade");
			SetVariantString("OnUser1 !self:Kill::1:-1");
			AcceptEntityInput(fade, "AddOutput");
			AcceptEntityInput(fade, "FireUser1");
		}
	}
	return Plugin_Continue;
}
