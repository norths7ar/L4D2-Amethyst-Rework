/*
*	Hats
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



#define PLUGIN_VERSION 		"1.47.0"

/*======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Hats
*	Author	:	SilverShot
*	Descrp	:	Attaches specified models to players above their head.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=153781
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.47.0 (23-Aug-2026)
	- All five player settings persist: hat type, wear toggle, first-person view, third-person view, and other-players visibility.
	- clientprefs cookies always mirror those settings and load even when l4d_hats_save is 0.
	- Added preference natives/forwards, including a cookie-ready handshake for safe MySQL migration.
	- Hats_SetClientHat no longer forces wearing back on, so a saved "hat off" survives restore.
	- Hook_SetTransmit stays on every hat entity; hiding other hats is no longer lost after round rebuild.

1.46.1 (13-Aug-2026)
	- Added natives "Hats_SetClientHat" and "Hats_GetClientHat" so other plugins can restore hats without going through sm_hatclient.
	- L4D_OnHatLoadSave now reports -1 when a hat is removed, instead of 0 (which collided with the first hat index).
	- Restoring saved hats no longer requires l4d_hats_make flags; cookie deletion now follows menu access (including top-100) and waits for rank data.

1.46 (13-Jun-2022)
	- Added forward "L4D_OnHatLoadSave" to report when loading or saving a clients hat type cookies. Requested by "morzlee".

1.45 (29-May-2022)
	- Added public command "sm_hats" to display a menu of hat options. Thanks to "pan0s" for writing.
	- Added public command "sm_hatall" to toggle the visibility of everyone's hats. Requested by "LordVGames".
	- Added admin command "sm_hatallc" to toggle a clients visibility hats. Requested by "Krevik".

	- Added saving a players visibility of all hats from the new commands above.
	- Added changes by "pan0s" to save the first and third person view of hats status.
	- Added a new colors stock for printing text, supports {RED} and {BLUE} colors. Thanks to "pan0s" for providing.
	- Added support for the "Ready-Up" plugin to hide or show the panel when using the Hats menu. Requested by "Krevik".

	- Changed commands "sm_hatshow", "sm_hatshowon" and "sm_hatshowoff" to only affect 1st person view, and 3rd person view with an optional argument "tp".
	- Fixed crashing if a model was missing. Plugin now fails to load forcing a config fix. Thanks to "Dragokas" for reporting.
	- Fixed hats not saving depending on the "l4d_hats_make" cvar value.

	- Thanks to "Krevik" and "pan0s" for help lots of help and testing.
	- Thanks to "pan0s" for updating the Chinese translations.
	- Thanks to "Impact" for updating the German translations.
	- Thanks to "Dragokas" for updating the Russian and Ukrainian translations.

	- Translation files have updated. Please update or errors will occur and the plugin won't work.

1.44 (15-Apr-2022)
	- Changed command "sm_hat" to accept 3 letter or smaller words for partial matching, e.g. "sm_hat saw".
	- Fixed command "sm_hatdel" not deleting the whole entry.
	- Fixed command "sm_hat" changing other players hats after using "sm_hatc" command. Thanks to "kot4404" for reporting.
	- Removed the "Big Helicopter" model from the data config. Too many reports of client-side glowing sprites remaining behind.

1.43 (06-Feb-2022)
	- Added a hackish fix for L4D2 not precaching models properly which has been causing stutter when using a model for the first time.
	- Fixed menus closing when selecting a player with a userid greater than 999. Thanks to "Electr000999" for reporting.

1.42 (16-Dec-2021)
	- Fixed simple mistake from last update causing wrong menu listing when not using a "hatnames" translation. Thanks to "Mi.Cura" for reporting.

1.41 (14-Dec-2021)
	- Fixed spawning and respawning with a hat when it was turned off. Thanks to "kot4404" for reporting.

	- Changed the "hatnames.phrases.txt" translation file format for better modifications when adding or removing hats from the data config.
	- Now supports adding hats and breaking the plugin when missing from the "hatnames.phrases.txt" translations file.
	- New "hatnames" translations no longer uses indexes and only model names.
	- Still supports the old version but suggest upgrading to the new.
	- Included the script for converting the translation file based on the config. Search for "TRANSLATE CODE" in the source.

1.40 (11-Dec-2021)
	- Fixed not saving hat angles and origins correctly when "l4d_hats_wall" was set to "0". Thanks to "NoroHime" for reporting.
	- Now saves when a hat was removed, if saving is enabled. Requested by "kot4404".

1.39 (09-Dec-2021)
	- Changed command "sm_hat" to accept "rand" or "random" as a parameter option to give a random hat.
	- Updated the "chi" and "zho" translation "hatnames.phrases.txt" files to be correct. Thanks to "NoroHime".

1.38 (03-Dec-2021)
	- Added "Hat_Off" option to the menu. Requested by "kot4404".
	- Fixed command "sm_hatadd" from not adding new entries. Thanks to "swiftswing1" for reporting.
	- Changes to fix warnings when compiling on SourceMod 1.11.

1.37 (09-Sep-2021)
	- Plugin now deletes the client cookie and hat if they no longer have access to use hats. Requested by "Darkwob".

1.36 (20-Jul-2021)
	- Removed cvar "l4d_hats_view" - recommended to use "ThirdPersonShoulder_Detect" plugin to turn on/off the hat view when in 3rd/1st person view.

1.35 (10-Jul-2021)
	- Fixed giving random hats to players when the "l4d_hats_random" cvar was set to "0". Thanks to "XYZC" for reporting.

1.34 (05-Jul-2021)
	- Fixed giving random hats on round_start when "l4d_hats_save" cvar was set to "1".

1.33 (04-Jul-2021)
	- Fixed "sm_hatrand" and "sm_hatrandom" from not giving random hats. Not sure when this broke.

1.32 (01-Jul-2021)
	- Added a warning message to suggest installing the "Attachments API" and "Use Priority Patch" plugins if missing.

1.31 (03-May-2021)
	- Added Simplified Chinese (zho) and Traditional Chinese (chi) translations. Thanks to "pan0s" for providing.
	- Fixed not giving random hats to clients who have no saved hats. Thanks to "pan0s" for reporting.

1.30 (28-Apr-2021)
	- Fixed client not in-game errors. Thanks to "HarryPotter" for reporting.

1.29 (10-Apr-2021)
	- Added cvar "l4d_hats_bots" to allow or disallow bots from spawning with hats.
	- Added cvar "l4d_hats_make" to allow players with specific flags only to auto spawn with hats.

1.28 (20-Mar-2021)
	- Added cvar "l4d_hats_wall" to prevent hats glowing through walls. Thanks to "Marttt" for the method and "Dragokas" for requesting.
	- Fixed personal hats not showing when changing hat in external view.

1.27 (01-Mar-2021)
	- Fixed invalid client errors due to the last update. Thanks to "ur5efj" for reporting.

1.26 (01-Mar-2021)
	- Now blocks showing hats when spectating someone in first person view. Thanks to "Alex101192" for reporting.

1.25 (23-Feb-2021)
	- Fixed hats not hiding after being revived. Thanks to "Alex101192" for reporting.

1.24 (01-Oct-2020)
	- Changed "l4d_hats_precache" cvar default value to blank.
	- Changed the way "l4d_hats_detect" works. Now also detects if reviving someone (events were unreliable and causing bugs).
	- Fixed 1st and 3rd person view of hats wrongfully toggling under certain conditions. Thanks to "Alex101192" for reporting.
	- Fixed some spelling mistakes in the "data/l4d_hats.cfg" hat names.

1.23 (16-Jun-2020)
	- Added Russian and Ukrainian translations - Thanks to "Dragokas" for providing.
	- Fixed changing hats when "l4d_hats_save" and "l4d_hats_random" were set. Random is superseded by saved if present.
	- Fixed command "sm_hatclient" throwing an error when only a client was specified.
	- Fixed hat view "ThirdPersonShoulder_Detect" and "Survivor Thirdperson" plugins clashing.

1.22 (10-May-2020)
	- Extra checks to prevent "IsAllowedGameMode" throwing errors.
	- Fixed not always loading client cookies before creating hats. Thanks to "Alex101192" for reporting.
	- Fixed potentially not translating some strings.
	- Fixed some functions not working for more than 100 hats.
	- Fixed hats affecting Survivor Thirdperson view under certain conditions.
	- Various changes to tidy up code.
	- Various optimizations and fixes.

1.21 (30-Apr-2020)
	- Added cvar "l4d_hats_detect" to enable clients to see their own hat when 3rd person view is detected.
	- Optionally uses "ThirdPersonShoulder_Detect" plugin by "Lux" and "MasterMind420", if available.

	- Added bunch of maps to the default value of "l4d_hats_precache". Thanks to "Alex101192" for providing.
	- Increased "l4d_hats_precache" cvar length, max usable length 490 (due to game limitations).

1.20 (01-Apr-2020)
	- Fixed "IsAllowedGameMode" from throwing errors when the "_tog" cvar was changed before MapStart.
	- Removed "colors.inc" dependency.
	- Updated these translation file encodings to UTF-8 (to display all characters correctly): German (de).

1.19 (19-Dec-2019)
	- Added command "sm_hatclient" to set a clients hat, requested by "foxhound27".

1.18 (23-Oct-2019)
	- Added commands "sm_hatshowon" and "sm_hatshowoff" to turn on/off personal hat visibility.
	- Fixed cvar "l4d_hats_precache" from modifying the allow cvar. Now correctly disables on blocked maps.

1.17 (10-Sep-2019)
	- Added cvar "l4d_hats_precache" to prevent pre-caching models on specified maps.

1.17b (19-Aug-2019)
	- Fixed ghosts from having hats.

1.16 (02-Aug-2019)
	- Fixed "m_TimeForceExternalView not found" error for L4D1 - Thanks to "Ja-Forces" for reporting.

1.15 (05-May-2018)
	- Converted plugin source to the latest syntax utilizing methodmaps. Requires SourceMod 1.8 or newer.
	- Changed cvar "l4d_hats_modes_tog" now supports L4D1.

1.14 (25-Jun-2017)
	- Added "Reset" option to the ang/pos/size menus, requested by "ZBzibing".
	- Fixed depreciated FCVAR_PLUGIN and GetClientAuthString.
	- Increased MAX_HATS value and added many extra L4D2 hats thanks to "Munch".

1.13 (29-Mar-2015)
	- Fixed the plugin not working in L4D1 due to a SetEntPropFloat property not found error.

1.12 (07-Oct-2012)
	- Fixed hats blocking players +USE by adding a single line of code - Thanks to "Machine".

1.11 (02-Jul-2012)
	- Fixed cvar "l4d_hats_random" from not working properly - Thanks to "Don't Fear The Reaper" for reporting.

1.10 (20-Jun-2012)
	- Added German translations - Thanks to "Don't Fear The Reaper".
	- Small fixes.

1.9.0 (22-May-2012)
	- Fixed multiple hat changes only showing the first hat to players.
	- Changing hats will no longer return the player to firstperson if thirdperson was already on.

1.8.0 (21-May-2012)
	- Fixed command "sm_hatc" making the client thirdpeson and not the target.

1.7.0 (20-May-2012)
	- Added cvar "l4d_hats_change" to put the player into thirdperson view when they select a hat, requested by "disawar1".

1.6.1 (15-May-2012)
	- Fixed a bug when printing to chat after changing someones hat.
	- Fixed cvar "l4d_hats_menu" not allowing access if it was empty.

1.6.0 (15-May-2012)
	- Fixed the allow cvars not affecting everything.

1.5.0 (10-May-2012)
	- Added translations, required for the commands and menu title.
	- Added optional translations for the hat names as requested by disawar1.
	- Added cvar "l4d_hats_allow" to turn on/off the plugin.
	- Added cvar "l4d_hats_modes" to control which game modes the plugin works in.
	- Added cvar "l4d_hats_modes_off" same as above.
	- Added cvar "l4d_hats_modes_tog" same as above, but only works for L4D2.
	- Added cvar "l4d_hats_save" to save a players hat for next time they spawn or connect.
	- Added command "sm_hatsize" to change the scale/size of hats as suggested by worminater.
	- Fixed "l4d_hats_menu" flags not setting correctly.
	- Optimized the plugin by hooking cvar changes.
	- Selecting a hat from the menu no longer returns to the first page.

1.4.3 (07-May-2011)
	- Added "name" key to the config for reading hat names.

1.4.2 (16-Apr-2011)
	- Changed the way models are checked to exist and precached.

1.4.1 (16-Apr-2011)
	- Added new hat models to the config. Deleted and repositioned models blocking the "use" function.
	- Changed the hat entity from prop_dynamic to prop_dynamic_override (allows physics models to be attached).
	- Fixed command "sm_hatadd" causing crashes due to models not being pre-cached, cannot cache during a round, causes crash.
	- Fixed pre-caching models which are missing (logs an error telling you an incorrect model is specified).

1.4.0 (11-Apr-2011)
	- Added cvar "l4d_hats_opaque" to set hat transparency.
	- Changed cvar "l4d_hats_random" to create a random hat when survivors spawn. 0=Never. 1=On round start. 2=Only first spawn (keeps the same hat next round).
	- Fixed hats changing when returning from idle.
	- Replaced underscores (_) with spaces in the menu.

1.3.4 (09-Apr-2011)
	- Fixed hooking L4D2 events in L4D1.

1.3.3 (07-Apr-2011)
	- Fixed command "sm_hatc" not displaying for admins when they are dead/infected team.
	- Minor bug fixes.

1.3.2 (06-Apr-2011)
	- Fixed command "sm_hatc" displaying invalid player.

1.3.1 (05-Apr-2011)
	- Fixed the fix of command "sm_hat" flags not applying.

1.3.0 (05-Apr-2011)
	- Fixed command "sm_hat" flags not applying.

1.2.0 (03-Apr-2011)
	- Added command "sm_hatoffc" for admins to disable hats on specific clients.
	- Added cvar "l4d_hats_third" to control the previous update's addition.

1.1.1a (03-Apr-2011)
	- Added events to show / hide the hat when in third / first person view.

1.1.1 (02-Apr-2011)
	- Added cvar "l4d_hats_view" to toggle if a players hat is visible by default when they join.
	- Resets variables for clients when they connect.

1.1.0 (01-Apr-2011)
	- Added command "sm_hatoff" - Toggle to turn on or off the ability of wearing hats.
	- Added command "sm_hatadd" - To add models into the config.
	- Added command "sm_hatdel" - To remove a model from the config.
	- Added command "sm_hatlist" - To display a list of all models (for use with sm_hatdel).

1.0.0 (29-Mar-2011)
	- Initial release.

======================================================================================*/

#pragma semicolon 1

#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#undef REQUIRE_PLUGIN

#define CVAR_FLAGS			FCVAR_NONE
#define CONFIG_SPAWNS		"data/l4d_hats.cfg"
#define	MAX_HATS			128
#define HATS_PREF_ENABLED      (1 << 0)
#define HATS_PREF_VIEW_FIRST   (1 << 1)
#define HATS_PREF_VIEW_THIRD   (1 << 2)
#define HATS_PREF_SHOW_OTHERS  (1 << 3)



//////////////////////////////////
// Updated by pan0s
// #include <pan0s>
Handle g_hCookie_ThirdView, g_hCookie_FirstView, g_hCookie_Wear;
bool g_bIsThirdPerson[MAXPLAYERS+1];	// View on TP
bool g_bHatViewTP[MAXPLAYERS+1];		// View on TP
//////////////////////////////////

ConVar g_hCvarAllow, g_hCvarBots, g_hCvarChange, g_hCvarDetect, g_hCvarMake, g_hCvarMenu, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarOpaq, g_hCvarPrecache, g_hCvarRand, g_hCvarSave, g_hCvarThird, g_hCvarWall;
ConVar g_hCvarMPGameMode, g_hPluginReadyUp;
Handle g_hCookie_Hat, g_hCookie_All;
Menu g_hMenu;
bool g_bCvarAllow, g_bMapStarted, g_bCvarBots, g_bCvarWall, g_bLeft4Dead2, g_bTranslation, g_bViewHooked, g_bValidMap;
int g_iCount, g_iCvarMake, g_iCvarMenu, g_iCvarOpaq, g_iCvarRand, g_iCvarSave, g_iCvarThird;
float g_fCvarChange, g_fCvarDetect;

float g_fSize[MAX_HATS], g_vAng[MAX_HATS][3], g_vPos[MAX_HATS][3];
char g_sModels[MAX_HATS][64], g_sNames[MAX_HATS][64];
char g_sFlagsMake[32];
char g_sFlagsMenu[32];
int g_iHatIndex[MAXPLAYERS+1];			// Player hat entity reference
int g_iHatWalls[MAXPLAYERS+1];			// Hidden hat entity reference
int g_iType[MAXPLAYERS+1];				// Stores selected hat to give players
bool g_bHatAll[MAXPLAYERS+1] = {true, ...};			// Visibility of everyones hats (personal setting)
bool g_bHatView[MAXPLAYERS+1];			// Player view of hat on/off (personal setting)
bool g_bHatOff[MAXPLAYERS+1];			// Lets players turn their hats on/off
bool g_bExternalCvar[MAXPLAYERS+1];		// If thirdperson view was detected (thirdperson_shoulder cvar)
bool g_bExternalProp[MAXPLAYERS+1];		// If thirdperson view was detected (netprop or revive actions)
bool g_bExternalState[MAXPLAYERS+1];	// If thirdperson view was detected
bool g_bExternalChange[MAXPLAYERS+1];	// When changing hats, show in 3rd person
bool g_bCookieAuth[MAXPLAYERS+1];		// When cookies cached and client is authorized
bool g_bHatTypeExternal[MAXPLAYERS+1];	// Hat type restored by Hats_SetClientHat; ignore late cookies
bool g_bHatPrefsExternal[MAXPLAYERS+1];	// Prefs restored by Hats_SetClientPrefs; ignore late cookies
bool g_bHatCookiesReady[MAXPLAYERS+1];	// clientprefs resolved for this connection
bool g_bHatTypeDirtyLocal[MAXPLAYERS+1];	// Player changed type before cookies resolved
bool g_bHatPrefsDirtyLocal[MAXPLAYERS+1];	// Player changed prefs before cookies resolved
Handle g_hTimerView[MAXPLAYERS+1];		// Thirdperson view when selecting hat
Handle g_hTimerDetect;

GlobalForward g_hForwardLoadSave;
GlobalForward g_hForwardPrefsChanged;
GlobalForward g_hForwardPrefsReady;

// ReadyUP plugin
native bool ToggleReadyPanel(bool show, int target = 0);

// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Hats",
	author = "SilverShot",
	description = "Attaches specified models to players above their head.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=153781"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test == Engine_Left4Dead ) g_bLeft4Dead2 = false;
	else if( test == Engine_Left4Dead2 ) g_bLeft4Dead2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}

	RegPluginLibrary("l4d_hats");

	g_hForwardLoadSave = new GlobalForward("L4D_OnHatLoadSave", ET_Ignore, Param_Cell, Param_Cell);
	g_hForwardPrefsChanged = new GlobalForward("L4D_OnHatPrefsChanged", ET_Ignore, Param_Cell, Param_Cell);
	g_hForwardPrefsReady = new GlobalForward("L4D_OnHatPrefsReady", ET_Ignore, Param_Cell, Param_Cell);
	CreateNative("Hats_SetClientHat", Native_SetClientHat);
	CreateNative("Hats_GetClientHat", Native_GetClientHat);
	CreateNative("Hats_GetClientPrefs", Native_GetClientPrefs);
	CreateNative("Hats_SetClientPrefs", Native_SetClientPrefs);
	CreateNative("Hats_AreClientPrefsReady", Native_AreClientPrefsReady);

	MarkNativeAsOptional("ToggleReadyPanel");

	return APLRes_Success;
}

void FireHatLoadSave(int client, int index)
{
	Call_StartForward(g_hForwardLoadSave);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_Finish();
}

void FireHatPrefsChanged(int client)
{
	Call_StartForward(g_hForwardPrefsChanged);
	Call_PushCell(client);
	Call_PushCell(HatsPackPrefs(client));
	Call_Finish();
}

void FireHatPrefsReady(int client)
{
	Call_StartForward(g_hForwardPrefsReady);
	Call_PushCell(client);
	Call_PushCell(HatsPackPrefs(client));
	Call_Finish();
}

int HatsPackPrefs(int client)
{
	int flags = 0;
	if( !g_bHatOff[client] )
		flags |= HATS_PREF_ENABLED;
	if( g_bHatView[client] )
		flags |= HATS_PREF_VIEW_FIRST;
	if( g_bHatViewTP[client] )
		flags |= HATS_PREF_VIEW_THIRD;
	if( g_bHatAll[client] )
		flags |= HATS_PREF_SHOW_OTHERS;
	return flags;
}

void HatsResetClientState(int client)
{
	g_iType[client] = 0;
	g_iHatIndex[client] = 0;
	g_iHatWalls[client] = 0;
	g_bHatAll[client] = true;
	g_bHatViewTP[client] = true;
	g_bHatView[client] = false;
	g_bHatOff[client] = false;
	g_bHatTypeExternal[client] = false;
	g_bHatPrefsExternal[client] = false;
	g_bHatCookiesReady[client] = false;
	g_bHatTypeDirtyLocal[client] = false;
	g_bHatPrefsDirtyLocal[client] = false;
}

bool HatsCanUseCookies(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && AreClientCookiesCached(client);
}

bool HatsClientPrefsReady(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && (IsFakeClient(client) || g_bHatCookiesReady[client]);
}

void HatsWriteHatTypeCookie(int client)
{
	if( !HatsCanUseCookies(client) )
		return;

	char sNum[8];
	IntToString(g_iType[client], sNum, sizeof(sNum));
	SetClientCookie(client, g_hCookie_Hat, sNum);
}

void HatsWritePrefCookies(int client)
{
	if( !HatsCanUseCookies(client) )
		return;

	SetClientCookie(client, g_hCookie_Wear, g_bHatOff[client] ? "0" : "1");
	SetClientCookie(client, g_hCookie_FirstView, g_bHatView[client] ? "1" : "0");
	SetClientCookie(client, g_hCookie_ThirdView, g_bHatViewTP[client] ? "1" : "0");
	SetClientCookie(client, g_hCookie_All, g_bHatAll[client] ? "1" : "0");
}

void HatsCommitPrefs(int client, bool notify)
{
	g_bHatPrefsDirtyLocal[client] = true;
	HatsWritePrefCookies(client);
	if( notify )
		FireHatPrefsChanged(client);
}

void HatsCommitHatType(int client, int index)
{
	g_iType[client] = index < 0 ? -1 : index + 1;
	g_bHatTypeDirtyLocal[client] = true;
	HatsWriteHatTypeCookie(client);
	FireHatLoadSave(client, index);
}

void HatsEnableWear(int client)
{
	if( !g_bHatOff[client] )
		return;

	g_bHatOff[client] = false;
	HatsCommitPrefs(client, true);
}

void HatsApplyPrefFlags(int client, int flags, bool recreate)
{
	bool wantOn = (flags & HATS_PREF_ENABLED) != 0;
	bool wasOff = g_bHatOff[client];

	g_bHatOff[client] = !wantOn;
	g_bHatView[client] = (flags & HATS_PREF_VIEW_FIRST) != 0;
	g_bHatViewTP[client] = (flags & HATS_PREF_VIEW_THIRD) != 0;
	g_bHatAll[client] = (flags & HATS_PREF_SHOW_OTHERS) != 0;

	if( !wantOn )
	{
		RemoveHat(client);
	}
	else if( recreate && wasOff && g_iType[client] > 0 )
	{
		CreateHat(client, g_iType[client] - 1, false);
	}
}

bool HatsShouldShowOwnHat(int client)
{
	if( g_bExternalChange[client] )
		return true;
	if( g_bIsThirdPerson[client] || g_bExternalProp[client] || g_bExternalCvar[client] )
		return g_bHatViewTP[client];
	return g_bHatView[client];
}

void HatsLoadCookies(int client)
{
	if( client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) || !AreClientCookiesCached(client) )
		return;
	if( g_bHatCookiesReady[client] )
		return;

	char sCookie[8];

	if( !g_bHatPrefsExternal[client] && !g_bHatPrefsDirtyLocal[client] )
	{
		GetClientCookie(client, g_hCookie_All, sCookie, sizeof(sCookie));
		if( sCookie[0] != 0 )
			g_bHatAll[client] = StringToInt(sCookie) == 1;

		GetClientCookie(client, g_hCookie_FirstView, sCookie, sizeof(sCookie));
		if( sCookie[0] != 0 )
			g_bHatView[client] = StringToInt(sCookie) == 1;

		GetClientCookie(client, g_hCookie_ThirdView, sCookie, sizeof(sCookie));
		if( sCookie[0] != 0 )
			g_bHatViewTP[client] = StringToInt(sCookie) == 1;

		GetClientCookie(client, g_hCookie_Wear, sCookie, sizeof(sCookie));
		if( sCookie[0] != 0 )
			g_bHatOff[client] = StringToInt(sCookie) != 1;
	}

	if( !g_bHatTypeExternal[client] && !g_bHatTypeDirtyLocal[client] )
	{
		GetClientCookie(client, g_hCookie_Hat, sCookie, sizeof(sCookie));
		if( sCookie[0] == 0 )
			g_iType[client] = 0;
		else
			g_iType[client] = StringToInt(sCookie);
	}

	g_bHatCookiesReady[client] = true;
	if( g_bHatPrefsExternal[client] || g_bHatPrefsDirtyLocal[client] )
		HatsWritePrefCookies(client);
	if( g_bHatTypeExternal[client] || g_bHatTypeDirtyLocal[client] )
		HatsWriteHatTypeCookie(client);

	CookieAuthTest(client);
	FireHatPrefsReady(client);

	if( IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) )
	{
		RemoveHat(client);
		CreateTimer(0.1, TimerDelayCreate, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

bool HatsRankDataReady(int client)
{
    return client >= 0;
}

bool HatsClientHasMenuAccess(int client) { return client > 0 && IsClientInGame(client) && !IsFakeClient(client); }

any Native_SetClientHat(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	if( client < 1 || client > MaxClients || !IsClientInGame(client) )
		return false;

	g_bHatTypeExternal[client] = true;
	RemoveHat(client);

	if( index < 0 )
	{
		g_iType[client] = -1;
		HatsWriteHatTypeCookie(client);
		return true;
	}

	if( index >= g_iCount )
		return false;

	g_iType[client] = index + 1;
	HatsWriteHatTypeCookie(client);

	if( g_bHatOff[client] )
		return true;

	return CreateHat(client, index, false);
}

any Native_GetClientHat(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if( client < 1 || client > MaxClients )
		return -1;
	if( g_iType[client] <= 0 )
		return -1;
	return g_iType[client] - 1;
}

any Native_GetClientPrefs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if( client < 1 || client > MaxClients )
		return 0;
	return HatsPackPrefs(client);
}

any Native_SetClientPrefs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int flags = GetNativeCell(2);
	if( client < 1 || client > MaxClients || !IsClientInGame(client) )
		return false;

	g_bHatPrefsExternal[client] = true;
	HatsApplyPrefFlags(client, flags, false);
	HatsWritePrefCookies(client);
	return true;
}

any Native_AreClientPrefsReady(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return client > 0 && client <= MaxClients && g_bHatCookiesReady[client];
}

public void OnAllPluginsLoaded()
{
	// Attachments API
	if( FindConVar("attachments_api_version") == null && (FindConVar("l4d2_swap_characters_version") != null || FindConVar("l4d_csm_version") != null) )
	{
		LogMessage("\n==========\nWarning: You should install \"[ANY] Attachments API\" to fix model attachments when changing character models: https://forums.alliedmods.net/showthread.php?t=325651\n==========\n");
	}

	// Use Priority Patch
	if( FindConVar("l4d_use_priority_version") == null )
	{
		LogMessage("\n==========\nWarning: You should install \"[L4D & L4D2] Use Priority Patch\" to fix attached models blocking +USE action: https://forums.alliedmods.net/showthread.php?t=327511\n==========\n");
	}

	g_hPluginReadyUp = FindConVar("l4d_ready_enabled");
}

public void OnPluginStart()
{
	// Load config
	KeyValues hFile = OpenConfig();
	char sTemp[64];
	bool message;

	for( int i = 0; i < MAX_HATS; i++ )
	{
		IntToString(i+1, sTemp, sizeof(sTemp));
		if( hFile.JumpToKey(sTemp) )
		{
			hFile.GetString("mod", sTemp, sizeof(sTemp));

			TrimString(sTemp);
			if( sTemp[0] == 0 )
				break;

			if( FileExists(sTemp, true) )
			{
				hFile.GetVector("ang", g_vAng[i]);
				hFile.GetVector("loc", g_vPos[i]);
				g_fSize[i] = hFile.GetFloat("size", 1.0);
				g_iCount++;

				strcopy(g_sModels[i], sizeof(g_sModels[]), sTemp);

				hFile.GetString("name", g_sNames[i], sizeof(g_sNames[]));

				if( strlen(g_sNames[i]) == 0 )
					GetHatName(g_sNames[i], i);
			}
			else
			{
				message = true;
				LogError("Cannot find the model '%s'.", sTemp);
			}

			hFile.Rewind();
		}
	}

	if( message )
	{
		SetFailState("\n==========\nWarning: Please fix your \"%s\" config. Missing models detected.\n==========\n", CONFIG_SPAWNS);
	}

	delete hFile;

	if( g_iCount == 0 )
		SetFailState("No models wtf?!");



	// Transactions
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/hatnames.phrases.txt");
	g_bTranslation = FileExists(sPath);

	if( g_bTranslation )
		LoadTranslations("hatnames.phrases");
	LoadTranslations("hats.phrases");
	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");



	// Hats menu
	if( g_bTranslation == false )
	{
		g_hMenu = new Menu(HatMenuHandler);
		g_hMenu.AddItem("HAT_DISABLED", "HAT_DISABLED");

		for( int i = 0; i < g_iCount; i++ )
			g_hMenu.AddItem(g_sModels[i], g_sNames[i]);
		g_hMenu.SetTitle("%t", "Hat_Menu_Title");
		g_hMenu.ExitBackButton = true;
		g_hMenu.ExitButton = true;
	}



	// Cvars
	g_hCvarAllow = CreateConVar(		"l4d_hats_allow",		"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarBots = CreateConVar(			"l4d_hats_bots",		"0",			"0=Disallow bots from spawning with Hats. 1=Allow bots to spawn with hats.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarChange = CreateConVar(		"l4d_hats_change",		"1.3",			"0=Off. Other value puts the player into thirdperson for this many seconds when selecting a hat.", CVAR_FLAGS );
	g_hCvarDetect = CreateConVar(		"l4d_hats_detect",		"0.3",			"0.0=Off. How often to detect thirdperson view. Also uses ThirdPersonShoulder_Detect plugin if available.", CVAR_FLAGS );
	g_hCvarMake = CreateConVar(			"l4d_hats_make", "",				"Specify admin flags or blank to allow all players to spawn with a hat, requires the l4d_hats_random cvar to spawn.", CVAR_FLAGS );
	g_hCvarMenu = CreateConVar(			"l4d_hats_menu", "",				"Specify admin flags or blank to allow all players access to the hats menu.", CVAR_FLAGS );
	g_hCvarModes = CreateConVar(		"l4d_hats_modes",		"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff = CreateConVar(		"l4d_hats_modes_off",	"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog = CreateConVar(		"l4d_hats_modes_tog",	"",				"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarOpaq = CreateConVar(			"l4d_hats_opaque",		"255", 			"How transparent or solid should the hats appear. 0=Translucent, 255=Opaque.", CVAR_FLAGS, true, 0.0, true, 255.0 );
	g_hCvarPrecache = CreateConVar(		"l4d_hats_precache",	"",				"Prevent pre-caching models on these maps, separate by commas (no spaces). Enabling plugin on these maps will crash the server.", CVAR_FLAGS );
	g_hCvarRand = CreateConVar(			"l4d_hats_random",		"0", 			"Attach a random hat when survivors spawn. 0=Never. 1=On round start. 2=Only first spawn (keeps the same hat next round).", CVAR_FLAGS, true, 0.0, true, 3.0 );
	g_hCvarSave = CreateConVar(			"l4d_hats_save", "1", 			"0=Off, 1=Save the players selected hats and attach when they spawn or rejoin the server. Overrides the random setting.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarThird = CreateConVar(		"l4d_hats_third",		"1", 			"0=Off, 1=When a player is in third person view, display their hat. Hide when in first person view.", CVAR_FLAGS, true, 0.0, true, 1.0 );
	g_hCvarWall = CreateConVar(			"l4d_hats_wall",		"1",			"0=Show hats glowing through walls, 1=Hide hats glowing when behind walls (creates 1 extra entity per hat).", CVAR_FLAGS, true, 0.0, true, 1.0 );
	CreateConVar(						"l4d_hats_version",		PLUGIN_VERSION,	"Hats plugin version.",	FCVAR_NONE|FCVAR_DONTRECORD);
	//AutoExecConfig(true,				"l4d_hats");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarBots.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarChange.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarDetect.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarMake.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarMenu.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarRand.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarSave.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarWall.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarOpaq.AddChangeHook(CvarChangeOpac);
	g_hCvarThird.AddChangeHook(CvarChangeThird);



	// Commands
	RegConsoleCmd("sm_hats",		CmdHatMain,							"Displays a menu to customize various settings for hats.");

	g_hCookie_Hat = RegClientCookie("l4d_hats", "Hat Type", CookieAccess_Protected);
	g_hCookie_All = RegClientCookie("l4d_hats_all", "General Hats Visibility", CookieAccess_Protected);
	g_hCookie_Wear = RegClientCookie("l4d_hats_wear", "Hats Wear Enabled", CookieAccess_Protected);

	// Updated by pan0s
	g_hCookie_FirstView = RegClientCookie("l4d_hats_fv", "Hats First person View", CookieAccess_Protected);
	g_hCookie_ThirdView = RegClientCookie("l4d_hats_tv", "Hats Third person View", CookieAccess_Protected);
}

public void OnPluginEnd()
{
	for( int i = 1; i <= MaxClients; i++ )
		RemoveHat(i);
}



// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
}

void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_hCvarMake.GetString(g_sFlagsMake, sizeof(g_sFlagsMake));
	g_iCvarMake = ReadFlagString(g_sFlagsMake);
	g_hCvarMenu.GetString(g_sFlagsMenu, sizeof(g_sFlagsMenu));
	g_iCvarMenu = ReadFlagString(g_sFlagsMenu);
	g_bCvarBots = g_hCvarBots.BoolValue;
	g_fCvarChange = g_hCvarChange.FloatValue;
	g_fCvarDetect = g_hCvarDetect.FloatValue;
	g_iCvarOpaq = g_hCvarOpaq.IntValue;
	g_iCvarRand = g_hCvarRand.IntValue;
	g_iCvarSave = g_hCvarSave.IntValue;
	g_iCvarThird = g_hCvarThird.IntValue;
	g_bCvarWall = g_hCvarWall.BoolValue;
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true && g_bValidMap == true )
	{
		g_bCvarAllow = true;

		if( g_iCvarThird )
			HookViewEvents();
		HookEvents();
		SpectatorHatHooks();

		int clientID;
		for( int i = 1; i <= MaxClients; i++ )
		{
			if( !IsClientInGame(i) || GetClientTeam(i) != 2 )
				continue;

			clientID = GetClientUserId(i);
			if( !IsFakeClient(i) )
			{
				HatsLoadCookies(i);
				CreateTimer(0.3, TimerDelayCreate, clientID);
			}
			else if( g_iCvarRand )
			{
				CreateTimer(0.3, TimerDelayCreate, clientID);
			}
		}

		// if( g_bLeft4Dead2 && g_fCvarDetect )
		if( g_fCvarDetect )
		{
			delete g_hTimerDetect;
			g_hTimerDetect = CreateTimer(g_fCvarDetect, TimerDetect, _, TIMER_REPEAT);
		}
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false || g_bValidMap == false) )
	{
		g_bCvarAllow = false;

		UnhookViewEvents();
		UnhookEvents();

		for( int i = 1; i <= MaxClients; i++ )
		{
			RemoveHat(i);

			if( IsValidEntRef(g_iHatIndex[i]) )
			{
				for( int x = 1; x <= MaxClients; x++ )
				{
					if( IsClientInGame(x) )
					{
						SDKUnhook(g_iHatIndex[i], SDKHook_SetTransmit, Hook_SetSpecTransmit);
					}
				}
			}
		}
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
//					OTHER BITS
// ====================================================================================================
public void OnMapStart()
{
	g_bMapStarted = true;
	g_bValidMap = true;

	char sCvar[512];
	g_hCvarPrecache.GetString(sCvar, sizeof(sCvar));

	if( sCvar[0] != '\0' )
	{
		char sMap[64];
		GetCurrentMap(sMap, sizeof(sMap));

		Format(sMap, sizeof(sMap), ",%s,", sMap);
		Format(sCvar, sizeof(sCvar), ",%s,", sCvar);

		if( StrContains(sCvar, sMap, false) != -1 )
			g_bValidMap = false;
	}

	if( g_bValidMap )
	{
		for( int i = 0; i < g_iCount; i++ )
		{
			PrecacheModel(g_sModels[i]);
		}

		// Hackish precache since L4D2 does not cache models properly (client side?) any more since recent updates
		if( g_bLeft4Dead2 )
		{
			RequestFrame(OnFramePrecache);
		}
	}
}

void OnFramePrecache()
{
	int entity;
	for( int i = 0; i < g_iCount; i++ )
	{
		entity = CreateEntityByName("prop_dynamic");
		SetEntityModel(entity, g_sModels[i]);
		DispatchSpawn(entity);
		RemoveEdict(entity);
	}
}

public void OnMapEnd()
{
	g_bMapStarted = false;
}

public void OnClientPutInServer(int client)
{
	HatsResetClientState(client);
	if( AreClientCookiesCached(client) )
		HatsLoadCookies(client);
}

public void OnClientPostAdminCheck(int client)
{
	CookieAuthTest(client);
}

public void OnClientCookiesCached(int client)
{
	if( client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client) )
		return;

	HatsLoadCookies(client);
}

void CookieAuthTest(int client)
{
	// Check if clients allowed to use hats otherwise delete cookie/hat
	if( g_iCvarMake && g_bCookieAuth[client] && !IsFakeClient(client) )
	{
		if( HatsClientHasMenuAccess(client) )
			return;

		// Rank data may not be ready yet; keep the cookie until we know they lost access.
		if( !HatsRankDataReady(client) )
			return;

		g_iType[client] = 0;
		RemoveHat(client);
		g_bHatTypeDirtyLocal[client] = true;
		HatsWriteHatTypeCookie(client);
		FireHatLoadSave(client, -1);
	} else {
		g_bCookieAuth[client] = true;
	}
}

public void OnClientDisconnect(int client)
{
	RemoveHat(client);
	g_bExternalProp[client] = false;
	g_bIsThirdPerson[client] = false;
	g_bExternalCvar[client] = false;
	g_bExternalChange[client] = false;
	g_bCookieAuth[client] = false;
	HatsResetClientState(client);
	delete g_hTimerView[client];
}

KeyValues OpenConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_SPAWNS);
	if( !FileExists(sPath) )
		SetFailState("Cannot find the file: \"%s\"", CONFIG_SPAWNS);

	KeyValues hFile = new KeyValues("models");
	if( !hFile.ImportFromFile(sPath) )
	{
		delete hFile;
		SetFailState("Cannot load the file: \"%s\"", CONFIG_SPAWNS);
	}
	return hFile;
}

void GetHatName(char sTemp[64], int index)
{
	strcopy(sTemp, sizeof(sTemp), g_sModels[index]);
	ReplaceString(sTemp, sizeof(sTemp), "_", " ");
	int pos = FindCharInString(sTemp, '/', true) + 1;
	int len = strlen(sTemp) - pos - 3;
	strcopy(sTemp, len, sTemp[pos]);
}

bool HatsValidClient(int client)
{
	if( HatsClientPrefsReady(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) )
		return true;
	return false;
}

void SetReadyUpPlugin(int client, bool show)
{
	// Readyup plugin, show or hide panel
	if( client > 0 && g_hPluginReadyUp && g_hPluginReadyUp.BoolValue && HatsValidClient(client) )
	{
		ToggleReadyPanel(show, client);
	}
}




// ====================================================================================================
//					CVAR CHANGES
// ====================================================================================================
void CvarChangeOpac(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_iCvarOpaq = g_hCvarOpaq.IntValue;

	if( g_bCvarAllow )
	{
		int entity;
		for( int i = 1; i <= MaxClients; i++ )
		{
			entity = g_iHatIndex[i];
			if( HatsValidClient(i) && IsValidEntRef(entity) )
			{
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				SetEntityRenderColor(entity, 255, 255, 255, g_iCvarOpaq);
			}
		}
	}
}

void CvarChangeThird(Handle convar, const char[] oldValue, const char[] newValue)
{
	g_iCvarThird = g_hCvarThird.IntValue;

	if( g_bCvarAllow )
	{
		if( g_iCvarThird )
			HookViewEvents();
		else
			UnhookViewEvents();
	}
}



// ====================================================================================================
//					EVENTS
// ====================================================================================================
void HookEvents()
{
	HookEvent("round_start",		Event_Start);
	HookEvent("round_end",			Event_RoundEnd);
	HookEvent("player_death",		Event_PlayerDeath);
	HookEvent("player_spawn",		Event_PlayerSpawn);
	HookEvent("player_team",		Event_PlayerTeam);
}

void UnhookEvents()
{
	UnhookEvent("round_start",		Event_Start);
	UnhookEvent("round_end",		Event_RoundEnd);
	UnhookEvent("player_death",		Event_PlayerDeath);
	UnhookEvent("player_spawn",		Event_PlayerSpawn);
	UnhookEvent("player_team",		Event_PlayerTeam);
}

void HookViewEvents()
{
	if( g_bViewHooked == false )
	{
		g_bViewHooked = true;

		HookEvent("revive_success",			Event_First2);
		HookEvent("player_ledge_grab",		Event_Third1);
		HookEvent("lunge_pounce",			Event_Third2);
		HookEvent("pounce_end",				Event_First1);
		HookEvent("tongue_grab",			Event_Third2);
		HookEvent("tongue_release",			Event_First1);

		if( g_bLeft4Dead2 )
		{
			HookEvent("charger_pummel_start",		Event_Third2);
			HookEvent("charger_carry_start",		Event_Third2);
			HookEvent("charger_carry_end",			Event_First1);
			HookEvent("charger_pummel_end",			Event_First1);
		}
	}
}

void UnhookViewEvents()
{
	if( g_bViewHooked == false )
	{
		g_bViewHooked = true;

		UnhookEvent("revive_success",		Event_First2);
		UnhookEvent("player_ledge_grab",	Event_Third1);
		UnhookEvent("lunge_pounce",			Event_Third2);
		UnhookEvent("pounce_end",			Event_First1);
		UnhookEvent("tongue_grab",			Event_Third2);
		UnhookEvent("tongue_release",		Event_First1);

		if( g_bLeft4Dead2 )
		{
			UnhookEvent("charger_pummel_start",		Event_Third2);
			UnhookEvent("charger_carry_start",		Event_Third2);
			UnhookEvent("charger_carry_end",		Event_First1);
			UnhookEvent("charger_pummel_end",		Event_First1);
		}
	}
}

void Event_Start(Event event, const char[] name, bool dontBroadcast)
{
	if( g_iCvarRand == 1 )
		CreateTimer(0.5, TimerRand, _, TIMER_FLAG_NO_MAPCHANGE);

	// if( g_bLeft4Dead2 && g_fCvarDetect )
	if( g_fCvarDetect )
	{
		delete g_hTimerDetect;
		g_hTimerDetect = CreateTimer(g_fCvarDetect, TimerDetect, _, TIMER_REPEAT);
	}
}

Action TimerRand(Handle timer)
{
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( HatsValidClient(i) && g_iType[i] != -1 )
		{
			CreateHat(i, g_iType[i] ? g_iType[i] - 1 : -1);
		}
	}

	return Plugin_Continue;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for( int i = 1; i <= MaxClients; i++ )
		RemoveHat(i);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if( !client || GetClientTeam(client) != 2 )
		return;

	RemoveHat(client);
	SpectatorHatHooks();
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int clientID = event.GetInt("userid");
	int client = GetClientOfUserId(clientID);

	if( client && (g_iCvarRand == 2 || g_iCvarSave || !IsFakeClient(client)) )
	{
		RemoveHat(client);
		CreateTimer(0.5, TimerDelayCreate, clientID);
	}

	SpectatorHatHooks();
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int clientID = event.GetInt("userid");
	int client = GetClientOfUserId(clientID);

	RemoveHat(client);
	SpectatorHatHooks();

	if( client && (g_iCvarRand || !IsFakeClient(client)) )
		CreateTimer(0.1, TimerDelayCreate, clientID);
}

Action TimerDelayCreate(Handle timer, any client)
{
	client = GetClientOfUserId(client);

	if( HatsValidClient(client) )
	{
		bool fake = IsFakeClient(client);
		if( !g_bCvarBots && fake )
		{
			return Plugin_Continue;
		}

		if( g_iCvarRand == 2 )
			CreateHat(client, -2);
		else if( !fake )
		{
			if( !HatsClientHasMenuAccess(client) && HatsRankDataReady(client) )
				return Plugin_Continue;

			CreateHat(client, -3);
		}
		else if( g_iCvarRand )
		{
			if( !fake && g_iCvarMake != 0 )
			{
				int flags = GetUserFlagBits(client);
				if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarMake) )
					return Plugin_Continue;
			}

			CreateHat(client, -1);
		}
	}

	return Plugin_Continue;
}

void Event_First1(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("victim")), false);
}

void Event_First2(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("subject")), false);
}

void Event_Third1(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("userid")), true);
}

void Event_Third2(Event event, const char[] name, bool dontBroadcast)
{
	EventView(GetClientOfUserId(event.GetInt("victim")), true);
}

void EventView(int client, bool bIsThirdPerson)
{
	if( HatsValidClient(client) )
	{
		g_bIsThirdPerson[client] = bIsThirdPerson;
		SetHatView(client, bIsThirdPerson);
	}
}

// Show hat when thirdperson view
Action TimerDetect(Handle timer)
{
	if( g_bCvarAllow == false )
	{
		g_hTimerDetect = null;
		return Plugin_Stop;
	}

	for( int i = 1; i <= MaxClients; i++ )
	{
		if( g_bExternalCvar[i] == false && g_iHatIndex[i] && IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) )
		{
			if( (g_bLeft4Dead2 && GetEntPropFloat(i, Prop_Send, "m_TimeForceExternalView") > GetGameTime()) || GetEntPropEnt(i, Prop_Send, "m_reviveTarget") != -1 )
			{
				g_bIsThirdPerson[i] = true;

				if( g_bExternalProp[i] == false )
				{
					g_bExternalProp[i] = true;

					if( g_bHatViewTP[i] )
					{
						SetHatView(i, true);
					} else {
						SetHatView(i, false);
					}
				}
			}
			else
			{
				g_bIsThirdPerson[i] = false;

				if( g_bExternalProp[i] == true )
				{
					g_bExternalProp[i] = false;

					if( !g_bHatView[i] )
					{
						SetHatView(i, false);
					}
					else
					{
						SetHatView(i, true);
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public void TP_OnThirdPersonChanged(int client, bool bIsThirdPerson)
{
	g_bIsThirdPerson[client] = bIsThirdPerson;

	if( g_fCvarDetect )
	{
		if( bIsThirdPerson && g_bExternalCvar[client] )
		{
			SetHatView(client, false);
		}
		else if( bIsThirdPerson && !g_bExternalCvar[client] )
		{
			g_bExternalCvar[client] = true;
			if( g_bHatViewTP[client] ) SetHatView(client, true);
			else SetHatView(client, false);
		}
		else if( !bIsThirdPerson && g_bExternalCvar[client] )
		{
			g_bExternalCvar[client] = false;
			SetHatView(client, false);
		}
	}
}

void SetHatView(int client, bool bShowHat)
{
	// Own-hat and other-players visibility are both decided in Hook_SetTransmit.
	// Do not unhook that shared filter; round rebuild must keep it attached.
	if( bShowHat && !g_bExternalState[client] )
		g_bExternalState[client] = true;
	else if( !bShowHat && g_bExternalState[client] && !g_bExternalChange[client] && !HatsShouldShowOwnHat(client) )
		g_bExternalState[client] = false;
}



// ====================================================================================================
//					BLOCK HATS - WHEN SPECTATING IN 1ST PERSON VIEW
// ====================================================================================================
// Loop through hats, find valid ones, loop through for each client and add transmit hook for spectators
// Could be better instead of unhooking and hooking everyone each time, but quick and dirty addition...
void SpectatorHatHooks()
{
	for( int index = 1; index <= MaxClients; index++ )
	{
		if( IsValidEntRef(g_iHatIndex[index]) )
		{
			for( int i = 1; i <= MaxClients; i++ )
			{
				if( IsClientInGame(i) )
				{
					SDKUnhook(g_iHatIndex[index], SDKHook_SetTransmit, Hook_SetSpecTransmit);

					if( !IsPlayerAlive(i) )
					{
						// Must hook 1 frame later because SDKUnhook first and then SDKHook doesn't work, it won't be hooked for some reason.
						DataPack dPack = new DataPack();
						dPack.WriteCell(GetClientUserId(i));
						dPack.WriteCell(index);
						RequestFrame(OnFrameHooks, dPack);
					}
				}
			}
		}
	}
}

void OnFrameHooks(DataPack dPack)
{
	dPack.Reset();

	int client = dPack.ReadCell();
	client = GetClientOfUserId(client);

	if( client && IsClientInGame(client) && !IsPlayerAlive(client) )
	{
		int index = dPack.ReadCell();
		SDKHook(EntRefToEntIndex(g_iHatIndex[index]), SDKHook_SetTransmit, Hook_SetSpecTransmit);
	}

	delete dPack;
}

Action Hook_SetSpecTransmit(int entity, int client)
{
	// Hook_SetTransmit owns per-viewer visibility. This hook only handles
	// first-person spectators, otherwise it could also hide their own hat.
	if( !IsPlayerAlive(client) && GetEntProp(client, Prop_Send, "m_iObserverMode") == 4 )
	{
		int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		if( target > 0 && target <= MaxClients && g_iHatIndex[target] == EntIndexToEntRef(entity) )
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}



// ====================================================================================================
//					COMMANDS
// ====================================================================================================
//					sm_hats
// ====================================================================================================
// Updated by pan0s
Action CmdHatMain(int client, int args)
{
	if( !g_bCvarAllow || !HatsValidClient(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "HAT_NOT_RIGHT_NOW", client);
		return Plugin_Handled;
	}
	SetReadyUpPlugin(client, false);


	Menu menu = new Menu(HandleCmdHatMain);
	menu.SetTitle("%T", "HAT_MAIN", client);

	char option [64];
	char optionName [10];
	bool bEnabled[4];
	bEnabled[0] = !g_bHatOff[client];
	bEnabled[1] = g_bHatView[client];
	bEnabled[2] = g_bHatViewTP[client];
	bEnabled[3] = g_bHatAll[client];

	char options[][] = {"HAT_MENU", "HAT_WORE", "HAT_VIEWABLE", "HAT_VIEWABLE_TP", "HAT_VISIBILITY"};

	Format(option, sizeof(option), "%T", options[0], client);
	menu.AddItem("option0", option);

	for( int i=0; i < sizeof(bEnabled); i++ )
	{
		Format(option, sizeof(option), "%T: %T", options[i+1], client, bEnabled[i] ? "HAT_ENABLED" : "HAT_DISABLED", client);
		Format(optionName, sizeof(optionName),"option%d", i);
		menu.AddItem(optionName, option);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

// Handles the existing personal hat settings.
int HandleCmdHatMain(Handle menu, MenuAction action, int client, int itemNum)
{
	if( action == MenuAction_Select )
	{
		switch (itemNum)
		{
			case 0:
			{
				OpenHatMenu(client);
				return 0;
			}
			case 1: ToggleHatWear(client);
			case 2: ToggleHatView(client, false);
			case 3: ToggleHatView(client, true);
			case 4: ToggleOtherHats(client);
		}

		CmdHatMain(client, 0);
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
	else if( action == MenuAction_Cancel )
	{
		if( client == MenuCancel_Exit )
		{
			SetReadyUpPlugin(client, true);
		}
	}

	return 0;
}

// ====================================================================================================
//					HAT SELECTION
// ====================================================================================================
void OpenHatMenu(int client)
{
	if( !g_bCvarAllow || !HatsValidClient(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "HAT_NOT_RIGHT_NOW", client);
		return;
	}

	if( g_iCvarMenu != 0 && !HatsClientHasMenuAccess(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "No Access", client);
		return;
	}

	SetReadyUpPlugin(client, false);
	ShowMenu(client);
}

int HatMenuHandler(Menu menu, MenuAction action, int client, int index)
{
	if( action == MenuAction_End && client != 0 )
	{
		delete menu;
	}
	else if( action == MenuAction_Select )
	{
		if( index != 0 )
			HatsEnableWear(client);

		RemoveHat(client);

		if( index == 0 )
		{
			HatsCommitHatType(client, -1);
			CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Off", client);
		}
		else if( CreateHat(client, index - 1) )
		{
			ExternalView(client);
		}

		int menupos = menu.Selection;
		menu.DisplayAt(client, menupos, MENU_TIME_FOREVER);
	}
	else if( action == MenuAction_Cancel )
	{
		if( index == MenuCancel_ExitBack )
		{
			CmdHatMain(client, 0);
		}
		else if( index == MenuCancel_Exit )
		{
			SetReadyUpPlugin(client, true);
		}
	}

	return 0;
}

void ShowMenu(int client)
{
	SetReadyUpPlugin(client, false);

	if( g_bTranslation == false )
	{
		g_hMenu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		static char sMsg[128];
		Menu hTemp = new Menu(HatMenuHandler);
		hTemp.SetTitle("%T", "Hat_Menu_Title", client);
		FormatEx(sMsg, sizeof(sMsg), "%T", "HAT_DISABLED", client);
		hTemp.AddItem("HAT_DISABLED", sMsg);

		for( int i = 0; i < g_iCount; i++ )
		{
			FormatEx(sMsg, sizeof(sMsg), "%s", g_sModels[i]);
			int lang = GetClientLanguage(client);

			if( IsTranslatedForLanguage(sMsg, lang) == true )
			{
				Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
				hTemp.AddItem(g_sModels[i], sMsg);
			} else {
				FormatEx(sMsg, sizeof(sMsg), "Hat %d", i + 1);
				if( IsTranslatedForLanguage(sMsg, lang) == true )
				{
					Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
					hTemp.AddItem(g_sModels[i], sMsg);
				} else {
					hTemp.AddItem(g_sModels[i], g_sNames[i]);
				}
			}
		}

		hTemp.ExitBackButton = true;
		hTemp.Display(client, MENU_TIME_FOREVER);

	}
}

// ====================================================================================================
//					WEAR PREFERENCE
// ====================================================================================================
void ToggleHatWear(int client)
{
	if( !g_bCvarAllow || !HatsClientPrefsReady(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "HAT_NOT_RIGHT_NOW", client);
		return;
	}

	g_bHatOff[client] = !g_bHatOff[client];

	if( g_bHatOff[client] )
	{
		RemoveHat(client);
	}
	else if( g_iType[client] > 0 )
	{
		CreateHat(client, g_iType[client] - 1, false);
	}

	HatsCommitPrefs(client, true);

	char sTemp[64];
	FormatEx(sTemp, sizeof(sTemp), "%T", g_bHatOff[client] ? "Hat_Off" : "Hat_On", client);
	CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Ability", client, sTemp);

	return;
}

// ====================================================================================================
//					OWN HAT VISIBILITY
// ====================================================================================================
void ToggleHatView(int client, bool thirdPerson)
{
	if( !g_bCvarAllow || !HatsClientPrefsReady(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "HAT_NOT_RIGHT_NOW", client);
		return;
	}

	if( thirdPerson )
	{
		g_bHatViewTP[client] = !g_bHatViewTP[client];

		if( g_bIsThirdPerson[client] )
		{
			if( !g_bHatViewTP[client] )
				SetHatView(client, false);
			else
				SetHatView(client, true);
		}

		HatsCommitPrefs(client, true);

		char sTemp[64];
		Format(sTemp, sizeof(sTemp), "%T", g_bHatViewTP[client] ? "Hat_On" : "Hat_Off", client);
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_ViewTP", client, sTemp);

		return;
	}

	g_bHatView[client] = !g_bHatView[client];

	if( !g_bHatView[client] && (!g_bIsThirdPerson[client] || !g_bHatViewTP[client]) )
		SetHatView(client, false);
	else if( g_bHatView[client] && (!g_bIsThirdPerson[client] || g_bHatViewTP[client]) )
		SetHatView(client, true);

	HatsCommitPrefs(client, true);

	char sTemp[64];
	FormatEx(sTemp, sizeof(sTemp), "%T", g_bHatView[client] ? "Hat_On" : "Hat_Off", client);
	CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_View", client, sTemp);

	return;
}

// ====================================================================================================
//					OTHER HAT VISIBILITY
// ====================================================================================================
void ToggleOtherHats(int client)
{
	if( !g_bCvarAllow || !HatsClientPrefsReady(client) )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "HAT_NOT_RIGHT_NOW", client);
		return;
	}

	g_bHatAll[client] = !g_bHatAll[client];

	HatsCommitPrefs(client, true);

	char sTemp[64];
	FormatEx(sTemp, sizeof(sTemp), "%T", g_bHatAll[client] ? "Hat_On" : "Hat_Off", client);
	CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Visibility_Set", client, sTemp);

	return;
}



void TranslateHatName(int client, int index)
{
	if( g_bTranslation == false )
	{
		CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Wearing", client, g_sNames[index]);
	}
	else
	{
		static char sMsg[128];
		FormatEx(sMsg, sizeof(sMsg), "%s", g_sModels[index]);
		int lang = GetClientLanguage(client);

		if( IsTranslatedForLanguage(sMsg, lang) == true )
		{
			Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
			CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Wearing", client, sMsg);
		} else {
			FormatEx(sMsg, sizeof(sMsg), "Hat %d", index + 1);
			if( IsTranslatedForLanguage(sMsg, lang) == true )
			{
				Format(sMsg, sizeof(sMsg), "%T", sMsg, client);
				CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Wearing", client, sMsg);
			} else {
				CPrintToChat(client, "%T%T", "HAT_SYSTEM", client, "Hat_Wearing", client, g_sNames[index]);
			}
		}
	}
}

// ====================================================================================================
//					HAT STUFF
// ===================================================================================================
void RemoveHat(int client)
{
	g_bExternalState[client] = false;

	// Hat entity
	int entity = g_iHatIndex[client];
	g_iHatIndex[client] = 0;

	if( IsValidEntRef(entity) )
		RemoveEntity(entity);

	// Hidden entity
	entity = g_iHatWalls[client];
	g_iHatWalls[client] = 0;

	if( IsValidEntRef(entity) )
		RemoveEntity(entity);
}

bool CreateHat(int client, int index = -1, bool notify = true)
{
	if( g_bHatOff[client] || IsValidEntRef(g_iHatIndex[client]) == true || HatsValidClient(client) == false )
		return false;

	int requested = index;

	if( index == -1 ) // Random hat
	{
		if( g_iCvarRand == 0 ) return false;
		if( g_iType[client] == -1 ) return false;

		if( g_iCvarMenu != 0)
		{
			if( IsFakeClient(client) )
				return false;

			int flags = GetUserFlagBits(client);
			if( !(flags & ADMFLAG_ROOT) && !(flags & g_iCvarMenu) )
				return false;
		}

		index = GetRandomInt(0, g_iCount -1);
		g_iType[client] = index + 1;
	}
	else if( index == -2 ) // Previous random hat
	{
		if( g_iCvarRand != 2 ) return false;

		index = g_iType[client];
		if( index == -1 ) return false;

		if( index == 0 )
		{
			index = GetRandomInt(1, g_iCount);
		}

		index--;
	}
	else if( index == -3 ) // Saved hats
	{
		index = g_iType[client];
		if( index == -1 ) return false;

		if( index == 0 )
		{
			if( IsFakeClient(client) )
			{
				return false;
			}
			else
			{
				if( g_iCvarRand == 0 ) return false;

				index = GetRandomInt(1, g_iCount);
			}
		}

		index--;
	}
	else // Specified hat
	{
		g_iType[client] = index + 1;
	}
	if( notify && requested >= 0 )
	{
		g_bHatTypeDirtyLocal[client] = true;
		FireHatLoadSave(client, g_iType[client] - 1);
	}

	HatsWriteHatTypeCookie(client);
	HatsWritePrefCookies(client);

	// Fix showing glow through walls, break glow inheritance by attaching hats to info_target.
	// Method by "Marttt": https://forums.alliedmods.net/showpost.php?p=2737781&postcount=21
	int target;

	if( g_bCvarWall )
	{
		target = CreateEntityByName("info_target");
		DispatchSpawn(target);
	}

	int entity = CreateEntityByName("prop_dynamic_override");
	if( entity != -1 )
	{
		SetEntityModel(entity, g_sModels[index]);
		DispatchSpawn(entity);
		if( g_bLeft4Dead2 )
		{
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", g_fSize[index]);
		}

		if( g_bCvarWall )
		{
			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", target);
			TeleportEntity(target, g_vPos[index], NULL_VECTOR, NULL_VECTOR);

			SetVariantString("!activator");
			AcceptEntityInput(target, "SetParent", client);
			SetVariantString("eyes");
			AcceptEntityInput(target, "SetParentAttachment");
			TeleportEntity(target, g_vPos[index], NULL_VECTOR, NULL_VECTOR);

			g_iHatWalls[client] = EntIndexToEntRef(target);
		} else {
			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", client);
			SetVariantString("eyes");
			AcceptEntityInput(entity, "SetParentAttachment");
			TeleportEntity(entity, g_vPos[index], NULL_VECTOR, NULL_VECTOR);
		}

		// Lux
		AcceptEntityInput(entity, "DisableCollision");
		SetEntProp(entity, Prop_Send, "m_noGhostCollision", 1, 1);
		SetEntProp(entity, Prop_Data, "m_CollisionGroup", 0x0004);
		SetEntPropVector(entity, Prop_Send, "m_vecMins", view_as<float>({0.0, 0.0, 0.0}));
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", view_as<float>({0.0, 0.0, 0.0}));
		// Lux

		TeleportEntity(g_bCvarWall ? target : entity, g_vPos[index], g_vAng[index], NULL_VECTOR);
		SetEntProp(entity, Prop_Data, "m_iEFlags", 0);

		if( g_iCvarOpaq )
		{
			SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
			SetEntityRenderColor(entity, 255, 255, 255, g_iCvarOpaq);
		}

		g_iHatIndex[client] = EntIndexToEntRef(entity);
		SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
		g_bExternalState[client] = HatsShouldShowOwnHat(client);

		TranslateHatName(client, index);

		SpectatorHatHooks();
		return true;
	}

	return false;
}

void ExternalView(int client)
{
	if( g_fCvarChange && g_bLeft4Dead2 )
	{
		EventView(client, true);

		g_bExternalChange[client] = true;

		delete g_hTimerView[client];
		g_hTimerView[client] = CreateTimer(g_fCvarChange + (g_fCvarChange >= 2.0 ? 0.4 : 0.2), TimerEventView, GetClientUserId(client));

		// Survivor Thirdperson plugin sets 99999.3.
		if( GetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView") != 99999.3 )
			SetEntPropFloat(client, Prop_Send, "m_TimeForceExternalView", GetGameTime() + g_fCvarChange);
	}
}

Action TimerEventView(Handle timer, any client)
{
	client = GetClientOfUserId(client);
	if( client )
	{
		g_hTimerView[client] = null;
		g_bExternalChange[client] = false;

		EventView(client, false);
	}

	return Plugin_Continue;
}

Action Hook_SetTransmit(int entity, int client)
{
	if( client < 1 || client > MaxClients )
		return Plugin_Continue;

	if( EntIndexToEntRef(entity) == g_iHatIndex[client] )
		return HatsShouldShowOwnHat(client) ? Plugin_Continue : Plugin_Handled;

	if( !g_bHatAll[client] )
		return Plugin_Handled;

	return Plugin_Continue;
}

bool IsValidEntRef(int entity)
{
	if( entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE )
		return true;
	return false;
}



// ====================================================================================================
//					COLORS.INC REPLACEMENT
// ====================================================================================================
/*
void CPrintToChat(int client, char[] message, any ...)
{
	static char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 3);

	ReplaceString(buffer, sizeof(buffer), "{DEFAULT}",		"\x01", false);
	ReplaceString(buffer, sizeof(buffer), "{WHITE}",		"\x01", false);
	ReplaceString(buffer, sizeof(buffer), "{CYAN}",			"\x03", false);
	ReplaceString(buffer, sizeof(buffer), "{LIGHTGREEN}",	"\x03", false);
	ReplaceString(buffer, sizeof(buffer), "{ORANGE}",		"\x04", false);
	ReplaceString(buffer, sizeof(buffer), "{GREEN}",		"\x04", false); // Actually orange in L4D2, but replicating colors.inc behaviour
	ReplaceString(buffer, sizeof(buffer), "{OLIVE}",		"\x05", false);

	PrintToChat(client, buffer);
}
*/



/**************************************************************************
 *                                                                        *
 *          	 	     	 New color inc   				    	      *
 *                          Author: Ernecio (updated by pan0s)            *
 *                           Version: 1.0.1                               *
 *                                                                        *
 **************************************************************************/
enum
{
	SERVER_INDEX	= 0,
	NO_INDEX		= -1,
	NO_PLAYER		= -2,
	BLUE_INDEX		= 2,
	RED_INDEX		= 3,
}

stock const char CTag[][] 				= { "{DEFAULT}", "{ORANGE}", "{CYAN}", "{RED}", "{BLUE}", "{GREEN}" };
stock const char CTagCode[][] 			= { "\x01", "\x04", "\x03", "\x03", "\x03", "\x05" };
stock const bool CTagReqSayText2[]	 	= { false, false, true, true, true, false };
stock const int CProfile_TeamIndex[] 	= { NO_INDEX, NO_INDEX, SERVER_INDEX, RED_INDEX, BLUE_INDEX, NO_INDEX };

/**
 * @note Prints a message to a specific client in the chat area.
 * @note Supports color tags.
 *
 * @param client 		Client index.
 * @param sMessage 		Message (formatting rules).
 * @return 				No return
 *
 * On error/Errors:   If the client is not connected an error will be thrown.
 */
stock void CPrintToChat( int client, const char[] sMessage, any ... )
{
	if ( client <= 0 || client > MaxClients )
		ThrowError( "Invalid client index %d", client );

	if ( !IsClientInGame( client ) )
		ThrowError( "Client %d is not in game", client );

	static char sBuffer[250];
	static char sCMessage[250];
	SetGlobalTransTarget(client);
	Format( sBuffer, sizeof( sBuffer ), "\x01%s", sMessage );
	VFormat( sCMessage, sizeof( sCMessage ), sBuffer, 3 );

	int index = CFormat( sCMessage, sizeof( sCMessage ) );
	if( index == NO_INDEX )
		PrintToChat( client, sCMessage );
	else
		CSayText2( client, index, sCMessage );
}

/**
 * @note Prints a message to all clients in the chat area.
 * @note Supports color tags.
 *
 * @param client		Client index.
 * @param sMessage 		Message (formatting rules)
 * @return 				No return
 */
stock void CPrintToChatAll( const char[] sMessage, any ... )
{
	static char sBuffer[250];

	for ( int i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame( i ) && !IsFakeClient( i ) )
		{
			SetGlobalTransTarget( i );
			VFormat( sBuffer, sizeof( sBuffer ), sMessage, 2 );
			CPrintToChat( i, sBuffer );
		}
	}
}

/**
 * @note Replaces color tags in a string with color codes
 *
 * @param sMessage    String.
 * @param maxlength   Maximum length of the string buffer.
 * @return			  Client index that can be used for SayText2 author index
 *
 * On error/Errors:   If there is more then one team color is used an error will be thrown.
 */
stock int CFormat( char[] sMessage, int maxlength )
{
	int iRandomPlayer = NO_INDEX;

	for ( int i = 0; i < sizeof(CTagCode); i++ )											//	Para otras etiquetas de color se requiere un bucle.
	{
		if ( StrContains( sMessage, CTag[i]) == -1 ) 										//	Si no se encuentra la etiqueta, omitir.
			continue;
		else if ( !CTagReqSayText2[i] )
			ReplaceString( sMessage, maxlength, CTag[i], CTagCode[i] ); 					//	Si la etiqueta no necesita Saytext2 simplemente reemplazará.
		else																				//	La etiqueta necesita Saytext2.
		{
			if ( iRandomPlayer == NO_INDEX )												//	Si no se especificó un cliente aleatorio para la etiqueta, reemplaca la etiqueta y busca un cliente para la etiqueta.
			{
				iRandomPlayer = CFindRandomPlayerByTeam( CProfile_TeamIndex[i] ); 			//	Busca un cliente válido para la etiqueta, equipo de infectados oh supervivientes.
				if ( iRandomPlayer == NO_PLAYER )
					ReplaceString( sMessage, maxlength, CTag[i], CTagCode[5] ); 			//	Si no se encuentra un cliente valido, reemplasa la etiqueta con una etiqueta de color verde.
				else
					ReplaceString( sMessage, maxlength, CTag[i], CTagCode[i] ); 			// 	Si el cliente fue encontrado simplemente reemplasa.
			}
			else 																			//	Si en caso de usar dos colores de equipo infectado y equipo de superviviente juntos se mandará un mensaje de error.
				ThrowError("Using two team colors in one message is not allowed"); 			//	Si se ha usadó una combinación de colores no validad se registrara en la carpeta logs.
		}
	}

	return iRandomPlayer;
}

/**
 * @note Founds a random player with specified team
 *
 * @param color_team  Client team.
 * @return			  Client index or NO_PLAYER if no player found
 */
stock int CFindRandomPlayerByTeam( int color_team )
{
	if ( color_team == SERVER_INDEX )
		return 0;
	else
		for ( int i = 1; i <= MaxClients; i ++ )
			if ( IsClientInGame( i ) && GetClientTeam( i ) == color_team )
				return i;

	return NO_PLAYER;
}

/**
 * @note Sends a SayText2 usermessage to a client
 *
 * @param sMessage 		Client index
 * @param maxlength 	Author index
 * @param sMessage 		Message
 * @return 				No return.
 */
stock void CSayText2( int client, int author, const char[] sMessage )
{
	Handle hBuffer = StartMessageOne( "SayText2", client );
	BfWriteByte( hBuffer, author );
	BfWriteByte( hBuffer, true );
	BfWriteString( hBuffer, sMessage );
	EndMessage();
}



// ====================================================================================================
//					TRANSLATE CODE
// ====================================================================================================
// If using this code, you must replace the "\" character with "/" in the new "*phrases.txt.new" file.
stock void TranslateHatnames()
{
	int maxIndex = 95; // Searches from "1" to maxIndex (including max) in the "hatnames" file. Matches to the data config.

	char sLang[5] = "zho/"; // Language folder to translate. Blank for "en"
	char sText[256];
	char sModel[PLATFORM_MAX_PATH];
	char sTran[PLATFORM_MAX_PATH];
	char sData[PLATFORM_MAX_PATH];
	char sSave[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sSave, sizeof sSave, "translations/%shatnames.phrases.txt.new", sLang);
	BuildPath(Path_SM, sTran, sizeof sTran, "translations/%shatnames.phrases.txt", sLang);
	BuildPath(Path_SM, sData, sizeof sData, "data/l4d_hats.cfg");

	KeyValues hTran = new KeyValues("Phrases");
	KeyValues hData = new KeyValues("Models");
	KeyValues hSave = new KeyValues("Phrases");

	hTran.ImportFromFile(sTran);
	hData.ImportFromFile(sData);

	char sIndex[16];

	for( int i = 1; i <= maxIndex; i++ )
	{
		IntToString(i, sIndex, sizeof sIndex);
		hData.JumpToKey(sIndex);
		hData.GetString("mod", sModel, sizeof(sModel));
		ReplaceString(sModel, sizeof sModel, "/", "\\");

		Format(sIndex, sizeof sIndex, "Hat %d", i);
		hTran.JumpToKey(sIndex);
		hTran.GetString(sLang, sText, sizeof(sText));

		PrintToServer("%02d (%s) [%s] == [%s]", i, sIndex, sModel, sText);

		hSave.JumpToKey(sModel, true);
		hSave.SetString(sLang, sText);

		hTran.Rewind();
		hData.Rewind();
		hSave.Rewind();
	}

	hSave.ExportToFile(sSave);

	delete hTran;
	delete hData;
	delete hSave;
}
