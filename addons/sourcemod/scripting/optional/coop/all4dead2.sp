/*
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.	If not, see <http://www.gnu.org/licenses/>.
*/

/*
All4Dead - A modification for the game Left4Dead
Copyright 2009 James Richardson
*/

#pragma semicolon 1
#pragma tabsize 2

// Define constants
#define PLUGIN_NAME					"All4Dead"
#define PLUGIN_TAG					"[A4D] "
#define PLUGIN_VERSION			"2.2.0"
#define MENU_DISPLAY_TIME		MENU_TIME_FOREVER

// Include necessary files
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
// Make the admin menu optional
#undef REQUIRE_PLUGIN
#include <adminmenu>

// Menu handlers
new Handle:top_menu;
new Handle:admin_menu;
new TopMenuObject:generation_menus[5];
new const String:generation_ids[][] = {
	"a4d_guns_menu", "a4d_melee_menu", "a4d_items_menu", "a4d_special_menu", "a4d_uncommon_menu"
};
new const String:generation_labels[][] = {
	"A4DGuns", "A4DMeleeWeapons", "A4DSuppliesAndProps", "A4DSpecialInfectedAndHorde", "A4DUncommonInfected"
};

// Other stuff
new bool:currently_spawning = false;
new String:change_zombie_model_to[128] = "";

/// Metadata for the mod - used by SourceMod
public Plugin:myinfo = {
	name = PLUGIN_NAME,
	author = "James Richardson (grandwazir)",
	description = "Administrator generation menus for weapons, items and infected",
	version = PLUGIN_VERSION,
	url = "http://code.james.richardson.name"
};

// Generation plugin setup.
public OnPluginStart() {
	LoadTranslations("all4dead2.phrases");
	CreateConVar("a4d_version", PLUGIN_VERSION, "The version of All4Dead plugin.", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// If the Admin menu has been loaded start adding stuff to it
	if (LibraryExists("adminmenu") && ((top_menu = GetAdminTopMenu()) != INVALID_HANDLE))
		OnAdminMenuReady(top_menu);
}

public OnMapStart() {
	// Precache uncommon infected models
	PrecacheModel("models/infected/common_male_riot.mdl", true);
	PrecacheModel("models/infected/common_male_ceda.mdl", true);
	PrecacheModel("models/infected/common_male_clown.mdl", true);
	PrecacheModel("models/infected/common_male_mud.mdl", true);
	PrecacheModel("models/infected/common_male_roadcrew.mdl", true);
	PrecacheModel("models/infected/common_male_jimmy.mdl", true);
	PrecacheModel("models/infected/common_male_fallen_survivor.mdl", true);
}

/// Register our menus with SourceMod
public OnAdminMenuReady(Handle:menu) {
	// Stop this method being called twice
	if (menu == admin_menu)
		return;
	admin_menu = menu;
	new TopMenuObject:category = AddToTopMenu(admin_menu, "All4Dead Commands", TopMenuObject_Category, Menu_CategoryHandler, INVALID_TOPMENUOBJECT);
	for (new i = 0; i < sizeof(generation_menus); i++)
		generation_menus[i] = AddToTopMenu(admin_menu, generation_ids[i], TopMenuObject_Item,
			Menu_TopItemHandler, category, i < 3 ? "a4d_equipment_menu" : "a4d_infected_menu", ADMFLAG_CHEATS);
}

public OnLibraryRemoved(const String:name[]) {
	if (StrEqual(name, "adminmenu")) {
		admin_menu = INVALID_HANDLE;
		top_menu = INVALID_HANDLE;
	}
}

public OnEntityCreated(entity, const String:classname[]) {
	// If the last thing that was spawned as a zombie then store that entity
	// for future use
	if (StrEqual(classname, "infected", false)) {
		if (currently_spawning && !StrEqual(change_zombie_model_to, "")) {
			currently_spawning = false;
			SetEntityModel(entity, change_zombie_model_to);
			change_zombie_model_to = "";
		}
	}
}

// All4Dead owns generation only. Player actions live in admin_tools.
public Menu_CategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength) {
	if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "A4DSpawnMenu", client);
}

public Menu_TopItemHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, client, String:buffer[], maxlength) {
	for (new i = 0; i < sizeof(generation_menus); i++) {
		if (object_id != generation_menus[i]) continue;
		if (action == TopMenuAction_DisplayOption)
			Format(buffer, maxlength, "%T", generation_labels[i], client);
		else if (action == TopMenuAction_SelectOption && CanGenerate(client, i < 3 ? 0 : 1)) {
			switch (i) {
				case 0: Menu_CreateWeaponMenu(client, 0);
				case 1: Menu_CreateMeleeWeaponMenu(client, 0);
				case 2: Menu_CreateItemMenu(client, 0);
				case 3: Menu_CreateSpecialInfectedMenu(client, 0);
				case 4: Menu_CreateUInfectedMenu(client, 0);
			}
		}
		return;
	}
}

bool:CanGenerate(client, group) {
	return client > 0 && client <= MaxClients && IsClientInGame(client)
		&& CheckCommandAccess(client, group == 0 ? "a4d_equipment_menu" : "a4d_infected_menu", ADMFLAG_CHEATS);
}

/// Creates the infected spawning menu when it is selected from the top menu and displays it to the client.
public Action:Menu_CreateSpecialInfectedMenu(client, args) {
	new Handle:menu = CreateMenu(Menu_SpawnSInfectedHandler);
	SetMenuTitle(menu, "%T", "A4DSpawnSpecialInfected", client);
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);

	AddGenerationMenuItem(menu, client, "st", "A4DTank");
	AddGenerationMenuItem(menu, client, "sw", "A4DWitch");
	AddGenerationMenuItem(menu, client, "sb", "A4DBoomer");
	AddGenerationMenuItem(menu, client, "sh", "A4DHunter");
	AddGenerationMenuItem(menu, client, "ss", "A4DSmoker");
	AddGenerationMenuItem(menu, client, "sp", "A4DSpitter");
	AddGenerationMenuItem(menu, client, "sj", "A4DJockey");
	AddGenerationMenuItem(menu, client, "sc", "A4DCharger");
	AddGenerationMenuItem(menu, client, "sb", "A4DHorde");
	DisplayMenuAtItem(menu, client, args, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}
/// Handles callbacks from a client using the spawning menu.
public Menu_SpawnSInfectedHandler(Handle:menu, MenuAction:action, cindex, itempos) {
	// When a player selects an item do this.
	if (action == MenuAction_Select) {
		if (!CanGenerate(cindex, 1)) return;
		switch (itempos) {

			case 0:
				Do_SpawnInfected(cindex, "tank", false);
			case 1:
				Do_SpawnInfected(cindex, "witch", false);
			case 2:
				Do_SpawnInfected(cindex, "boomer", false);
			case 3:
				Do_SpawnInfected(cindex, "hunter", false);
			case 4:
				Do_SpawnInfected(cindex, "smoker", false);
			case 5:
				Do_SpawnInfected(cindex, "spitter", false);
			case 6:
				Do_SpawnInfected(cindex, "jockey", false);
			case 7:
				Do_SpawnInfected(cindex, "charger", false);
			case 8:
				Do_SpawnInfected(cindex, "mob", false);
		}
		// If none of the above matches show the menu again
		Menu_CreateSpecialInfectedMenu(cindex, GetMenuSelectionPosition());
	// If someone closes the menu - close the menu
	} else if (action == MenuAction_End)
		CloseHandle(menu);
	// If someone presses 'back' (8), return to main All4Dead menu */
	else if (action == MenuAction_Cancel)
		if (itempos == MenuCancel_ExitBack && admin_menu != INVALID_HANDLE)
			DisplayTopMenu(admin_menu, cindex, TopMenuPosition_LastCategory);
}

/// Creates the infected spawning menu when it is selected from the top menu and displays it to the client.
public Action:Menu_CreateUInfectedMenu(client, args) {
	new Handle:menu = CreateMenu(Menu_SpawnUInfectedHandler);
	SetMenuTitle(menu, "%T", "A4DSpawnUncommonInfected", client);
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);

	AddGenerationMenuItem(menu, client, "s1", "A4DRiotPolice");
	AddGenerationMenuItem(menu, client, "s2", "A4DCedaWorker");
	AddGenerationMenuItem(menu, client, "s3", "A4DClown");
	AddGenerationMenuItem(menu, client, "s4", "A4DMudman");
	AddGenerationMenuItem(menu, client, "s5", "A4DConstructionWorker");
	AddGenerationMenuItem(menu, client, "s6", "A4DJimmyGibbs");
	AddGenerationMenuItem(menu, client, "s7", "A4DFallenSurvivor");
	DisplayMenuAtItem(menu, client, args, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}
/// Handles callbacks from a client using the spawning menu.
public Menu_SpawnUInfectedHandler(Handle:menu, MenuAction:action, cindex, itempos) {
	// When a player selects an item do this.
	if (action == MenuAction_Select) {
		if (!CanGenerate(cindex, 1)) return;
		switch (itempos) {

			case 0:
				Do_SpawnUncommonInfected(cindex, 0);
			case 1:
				Do_SpawnUncommonInfected(cindex, 1);
			case 2:
				Do_SpawnUncommonInfected(cindex, 2);
			case 3:
				Do_SpawnUncommonInfected(cindex, 3);
			case 4:
				Do_SpawnUncommonInfected(cindex, 4);
			case 5:
				Do_SpawnUncommonInfected(cindex, 5);
			case 6:
				Do_SpawnUncommonInfected(cindex, 6);
		}
		// If none of the above matches show the menu again
		Menu_CreateUInfectedMenu(cindex, GetMenuSelectionPosition());
	// If someone closes the menu - close the menu
	} else if (action == MenuAction_End)
		CloseHandle(menu);
	// If someone presses 'back' (8), return to main All4Dead menu */
	else if (action == MenuAction_Cancel)
		if (itempos == MenuCancel_ExitBack && admin_menu != INVALID_HANDLE)
			DisplayTopMenu(admin_menu, cindex, TopMenuPosition_LastCategory);
}

/**
 * <summary>
 * 	Spawns one of the specified infected using the z_spawn command.
 * </summary>
 * <param name="type">
 * 	The type of infected to spawn
 * </param>
 * <remarks>
 * 	The infected will spawn either at the crosshair of the spawning player
 * 	or at a location automatically decided by the AI Director if auto_placement
 * 	is true. Automatically falls back to a fake client if the client requesting
 * 	the action is the console.
 * </remarks>
*/
Do_SpawnInfected(client, const String:type[], bool:spawning_uncommon) {
	if (client <= 0 || !IsClientInGame(client)) return;
	currently_spawning = spawning_uncommon;
	StripAndExecuteClientCommand(client, "z_spawn", type);
	// OnEntityCreated consumes the uncommon model during this command. A failed
	// spawn must not leave it queued for an unrelated Director spawn later.
	currently_spawning = false;
	change_zombie_model_to[0] = '\0';
	LogAction(client, -1, "[NOTICE]: (%L) has spawned a %s", client, type);
}

Do_SpawnUncommonInfected(client, type) {
	new String:model[128];
	switch (type) {
		case 0:
			Format(model, sizeof(model), "models/infected/common_male_riot.mdl");
		case 1:
			Format(model, sizeof(model), "models/infected/common_male_ceda.mdl");
		case 2:
			Format(model, sizeof(model), "models/infected/common_male_clown.mdl");
		case 3:
			Format(model, sizeof(model), "models/infected/common_male_mud.mdl");
		case 4:
			Format(model, sizeof(model), "models/infected/common_male_roadcrew.mdl");
		case 5:
			Format(model, sizeof(model), "models/infected/common_male_jimmy.mdl");
		case 6:
			Format(model, sizeof(model), "models/infected/common_male_fallen_survivor.mdl");
	}
	change_zombie_model_to = model;
	Do_SpawnInfected(client, "zombie", true);
}
/// Sourcemod Action for the Do_EnableAutoPlacement command.

/**
 * <summary>
 * 	Allows (or disallows) the AI Director to place spawned infected automatically.
 * </summary>
 * <remarks>
 * 	If this is enabled the director will place mobs outside the players sight so
 * 	it will not look like they are magically appearing. This only affects zombies
 * 	spawned through z_spawn.
 * </remarks>
*/

// Item spawning functions

/// Creates the item spawning menu when it is selected from the top menu and displays it to the client */
public Action:Menu_CreateItemMenu(client, args) {
	new Handle:menu = CreateMenu(Menu_SpawnItemsHandler);
	SetMenuTitle(menu, "%T", "A4DSpawnItems", client);
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	AddGenerationMenuItem(menu, client, "2", "A4DPainPills");
	AddGenerationMenuItem(menu, client, "10", "A4DAmmoPile");
	AddGenerationMenuItem(menu, client, "1", "A4DFirstAidKit");
	AddGenerationMenuItem(menu, client, "0", "A4DDefibrillator");
	AddGenerationMenuItem(menu, client, "3", "A4DAdrenaline");
	AddGenerationMenuItem(menu, client, "4", "A4DMolotov");
	AddGenerationMenuItem(menu, client, "5", "A4DPipeBomb");
	AddGenerationMenuItem(menu, client, "6", "A4DBileJar");
	AddGenerationMenuItem(menu, client, "7", "A4DGasCan");
	AddGenerationMenuItem(menu, client, "8", "A4DPropaneTank");
	AddGenerationMenuItem(menu, client, "9", "A4DOxygenTank");
	AddGenerationMenuItem(menu, client, "11", "A4DIncendiaryAmmoPack");
	AddGenerationMenuItem(menu, client, "12", "A4DExplosiveAmmoPack");
	AddGenerationMenuItem(menu, client, "13", "A4DLaserSights");
	AddGenerationMenuItem(menu, client, "14", "A4DCola");
	AddGenerationMenuItem(menu, client, "15", "A4DGnome");
	DisplayMenuAtItem(menu, client, args, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}
/// Handles callbacks from a client using the spawn item menu.
public Menu_SpawnItemsHandler(Handle:menu, MenuAction:action, cindex, itempos) {
	if (action == MenuAction_Select) {
		if (!CanGenerate(cindex, 0)) return;
		new String:selection[12];
		GetMenuItem(menu, itempos, selection, sizeof(selection));
		switch (StringToInt(selection)) {
			case 0: {
				Do_SpawnItem(cindex, "defibrillator");
			} case 1: {
				Do_SpawnItem(cindex, "first_aid_kit");
			} case 2: {
				Do_SpawnItem(cindex, "pain_pills");
			} case 3: {
				Do_SpawnItem(cindex, "adrenaline");
			} case 4: {
				Do_SpawnItem(cindex, "molotov");
			} case 5: {
				Do_SpawnItem(cindex, "pipe_bomb");
			} case 6: {
				Do_SpawnItem(cindex, "vomitjar");
			} case 7: {
				Do_SpawnItem(cindex, "gascan");
			} case 8: {
				Do_SpawnItem(cindex, "propanetank");
			} case 9: {
				Do_SpawnItem(cindex, "oxygentank");
			} case 10: {
				new Float:location[3];
				if (!Misc_TraceClientViewToLocation(cindex, location)) {
					GetClientAbsOrigin(cindex, location);
				}
				Do_CreateEntity(cindex, "weapon_ammo_spawn", "models/props/terror/ammo_stack.mdl", location);
			} case 11: {
				Do_SpawnItem(cindex, "weapon_upgradepack_incendiary");
			} case 12: {
				Do_SpawnItem(cindex, "weapon_upgradepack_explosive");
			} case 13: {
				new Float:location[3];
				if (!Misc_TraceClientViewToLocation(cindex, location)) {
					GetClientAbsOrigin(cindex, location);
				}
				Do_CreateEntity(cindex, "upgrade_laser_sight", "PROVIDED", location);
			} case 14: {
				Do_SpawnItem(cindex, "cola_bottles");
			} case 15: {
				Do_SpawnItem(cindex, "gnome");
			}
		}
		Menu_CreateItemMenu(cindex, GetMenuSelectionPosition());
	} else if (action == MenuAction_End) {
		CloseHandle(menu);
	} else if (action == MenuAction_Cancel) {
		if (itempos == MenuCancel_ExitBack && admin_menu != INVALID_HANDLE)
			DisplayTopMenu(admin_menu, cindex, TopMenuPosition_LastCategory);
	}
}

/**
 * <summary>
 * 	Spawns one of the specified type of item using the give command.
 * </summary>
 * <param name="type">
 * 	The type of item to spawn
 * </param>
 * <remarks>
 * 	The infected will spawn either at the crosshair of the spawning player
 * 	or at a location automatically decided by the AI Director if auto_placement
 * 	is true. Slightly misleadingly named this function is used for both items and weapons.
 * </remarks>
*/
Do_SpawnItem(client, const String:type[]) {
	new String:feedback[64];
	Format(feedback, sizeof(feedback), "A %s has been spawned", type);
	if (client == 0) {
		ReplyToCommand(client, "%t", "A4DPleaseUseThisFeatureInGame");
	} else {
		StripAndExecuteClientCommand(client, "give", type);
		LogAction(client, -1, "[NOTICE]: (%L) has spawned a %s", client, type);
	}
}

Do_CreateEntity(client, const String:name[], const String:model[], Float:location[3]) {
	new entity = CreateEntityByName(name);
	if (entity == -1) {
		PrintToChat(client, "[SM] %t", "A4DUnableToSpawnThisItem");
		return;
	}
	if (StrEqual(model, "PROVIDED") == false)
		SetEntityModel(entity, model);
	DispatchSpawn(entity);
	// Starts animation on whatever we spawned - necessary for mobs
	ActivateEntity(entity);
	// Teleport the entity to the client's crosshair
	TeleportEntity(entity, location, NULL_VECTOR, NULL_VECTOR);
	LogAction(client, -1, "[NOTICE]: (%L) has created a %s (%s)", client, name, model);
}

// Weapon Spawning functions

/// Creates the weapon spawning menu when it is selected from the top menu and displays it to the client.
public Action:Menu_CreateWeaponMenu(client, args) {
	new Handle:menu = CreateMenu(Menu_SpawnWeaponHandler);
	SetMenuTitle(menu, "%T", "A4DSpawnGuns", client);
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	AddGenerationMenuItem(menu, client, "6", "A4DUzi");
	AddGenerationMenuItem(menu, client, "7", "A4DSilencedSmg");
	AddGenerationMenuItem(menu, client, "2", "A4DPumpShotgun");
	AddGenerationMenuItem(menu, client, "3", "A4DChromeShotgun");
	AddGenerationMenuItem(menu, client, "15", "A4DScout");
	AddGenerationMenuItem(menu, client, "0", "A4DPistol");
	AddGenerationMenuItem(menu, client, "1", "A4DMagnum");
	AddGenerationMenuItem(menu, client, "4", "A4DAutoShotgun");
	AddGenerationMenuItem(menu, client, "5", "A4DSpasShotgun");
	AddGenerationMenuItem(menu, client, "8", "A4DMp5");
	AddGenerationMenuItem(menu, client, "9", "A4DM16");
	AddGenerationMenuItem(menu, client, "10", "A4DAk47");
	AddGenerationMenuItem(menu, client, "11", "A4DScar");
	AddGenerationMenuItem(menu, client, "12", "A4DHuntingRifle");
	AddGenerationMenuItem(menu, client, "13", "A4DSg550");
	AddGenerationMenuItem(menu, client, "14", "A4DAwp");
	AddGenerationMenuItem(menu, client, "16", "A4DGrenadeLauncher");
	DisplayMenuAtItem(menu, client, args, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}
/// Handles callbacks from a client using the spawn weapon menu.
public Menu_SpawnWeaponHandler(Handle:menu, MenuAction:action, cindex, itempos) {
	if (action == MenuAction_Select) {
		if (!CanGenerate(cindex, 0)) return;
		new String:selection[12];
		GetMenuItem(menu, itempos, selection, sizeof(selection));
		switch (StringToInt(selection)) {
			case 0: {
				Do_SpawnItem(cindex, "pistol");
			} case 1: {
				Do_SpawnItem(cindex, "pistol_magnum");
			} case 2: {
				Do_SpawnItem(cindex, "pumpshotgun");
			} case 3: {
				Do_SpawnItem(cindex, "shotgun_chrome");
			} case 4: {
				Do_SpawnItem(cindex, "autoshotgun");
			} case 5: {
				Do_SpawnItem(cindex, "shotgun_spas");
			} case 6: {
				Do_SpawnItem(cindex, "smg");
			} case 7: {
				Do_SpawnItem(cindex, "smg_silenced");
			} case 8: {
				Do_SpawnItem(cindex, "smg_mp5");
			} case 9: {
				Do_SpawnItem(cindex, "rifle");
			} case 10: {
				Do_SpawnItem(cindex, "rifle_ak47");
			} case 11: {
				Do_SpawnItem(cindex, "rifle_desert");
			} case 12: {
				Do_SpawnItem(cindex, "hunting_rifle");
			} case 13: {
				Do_SpawnItem(cindex, "sniper_military");
			} case 14: {
				Do_SpawnItem(cindex, "sniper_awp");
			} case 15: {
				Do_SpawnItem(cindex, "sniper_scout");
			} case 16: {
				Do_SpawnItem(cindex, "grenade_launcher");
			}
		}
		Menu_CreateWeaponMenu(cindex, GetMenuSelectionPosition());
	} else if (action == MenuAction_End)
		CloseHandle(menu);
	/* If someone presses 'back' (8), return to main All4Dead menu */
	else if (action == MenuAction_Cancel)
		if (itempos == MenuCancel_ExitBack && admin_menu != INVALID_HANDLE)
			DisplayTopMenu(admin_menu, cindex, TopMenuPosition_LastCategory);
}

/// Creates the melee weapon spawning menu when it is selected from the top menu and displays it to the client.
public Action:Menu_CreateMeleeWeaponMenu(client, args) {
	new Handle:menu = CreateMenu(Menu_SpawnMeleeWeaponHandler);
	SetMenuTitle(menu, "%T", "A4DSpawnMeleeWeapons", client);
	SetMenuExitBackButton(menu, true);
	SetMenuExitButton(menu, true);
	AddGenerationMenuItem(menu, client, "ma", "A4DBaseballBat");
	AddGenerationMenuItem(menu, client, "mb", "A4DChainsaw");
	AddGenerationMenuItem(menu, client, "mc", "A4DCricketBat");
	AddGenerationMenuItem(menu, client, "md", "A4DCrowbar");
	AddGenerationMenuItem(menu, client, "me", "A4DElectricGuitar");
	AddGenerationMenuItem(menu, client, "mf", "A4DFireAxe");
	AddGenerationMenuItem(menu, client, "mg", "A4DFryingPan");
	AddGenerationMenuItem(menu, client, "mh", "A4DKatana");
	AddGenerationMenuItem(menu, client, "mi", "A4DMachete");
	AddGenerationMenuItem(menu, client, "mj", "A4DTonfa");
	AddGenerationMenuItem(menu, client, "hk", "A4DKnife");
	AddGenerationMenuItem(menu, client, "hk", "A4DPitchfork");
	AddGenerationMenuItem(menu, client, "hk", "A4DShovel");
	DisplayMenuAtItem(menu, client, args, MENU_DISPLAY_TIME);
	return Plugin_Handled;
}
/// Handles callbacks from a client using the spawn weapon menu.
public Menu_SpawnMeleeWeaponHandler(Handle:menu, MenuAction:action, cindex, itempos) {
	if (action == MenuAction_Select) {
		if (!CanGenerate(cindex, 0)) return;
		switch (itempos) {
			case 0: {
				Do_SpawnItem(cindex, "baseball_bat");
			} case 1: {
				Do_SpawnItem(cindex, "chainsaw");
			} case 2: {
				Do_SpawnItem(cindex, "cricket_bat");
			} case 3: {
				Do_SpawnItem(cindex, "crowbar");
			} case 4: {
				Do_SpawnItem(cindex, "electric_guitar");
			} case 5: {
				Do_SpawnItem(cindex, "fireaxe");
			} case 6: {
				Do_SpawnItem(cindex, "frying_pan");
			} case 7: {
				Do_SpawnItem(cindex, "katana");
			} case 8: {
				Do_SpawnItem(cindex, "machete");
			} case 9: {
				Do_SpawnItem(cindex, "tonfa");
			} case 10: {
				Do_SpawnItem(cindex, "knife");
			} case 11: {
				Do_SpawnItem(cindex, "pitchfork");
			} case 12: {
				Do_SpawnItem(cindex, "shovel");
			}
		}
		Menu_CreateMeleeWeaponMenu(cindex, GetMenuSelectionPosition());
	} else if (action == MenuAction_End)
		CloseHandle(menu);
	/* If someone presses 'back' (8), return to main All4Dead menu */
	else if (action == MenuAction_Cancel)
		if (itempos == MenuCancel_ExitBack && admin_menu != INVALID_HANDLE)
			DisplayTopMenu(admin_menu, cindex, TopMenuPosition_LastCategory);
}

/// Strip and execute a client command. This 'fakes' a client calling a specfied command. Can be used to call cheat-protected commands.
StripAndExecuteClientCommand(client, const String:command[], const String:arguments[]) {
	new flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
}
bool:Misc_TraceClientViewToLocation(client, Float:location[3])
{
	new Float:vAngles[3], Float:vOrigin[3];
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceRayDontHitSelf, client);
	if(TR_DidHit(trace)) {
		TR_GetEndPosition(location, trace);
		CloseHandle(trace);
		return true;
	}
	CloseHandle(trace);
	return false;
}

public bool:TraceRayDontHitSelf(entity, mask, any:data) {
	if(entity == data) { // Check if the TraceRay hit the itself.
		return false; // Don't let the entity be hit
	}
	return true; // It didn't hit itself
}

AddGenerationMenuItem(Handle:menu, client, const String:info[], const String:phrase[]) {
	new String:label[192];
	Format(label, sizeof(label), "%T", phrase, client);
	AddMenuItem(menu, info, label);
}
