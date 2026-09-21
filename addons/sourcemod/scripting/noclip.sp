#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <adminmenu>

TopMenu hTopMenu;

public Plugin myinfo =
{
	name = "Noclip",
	author = "AlliedModders LLC, norths7ar",
	description = "Administrator noclip command and player assistance menu for all modes",
	version = "1.0.0"
};

public void OnPluginStart()
{
	LoadTranslations("admin_tools.phrases");
	RegAdminCmd("sm_noclip", Command_NoClip, ADMFLAG_SLAY | ADMFLAG_CHEATS, "sm_noclip <#userid|name>");
	if (LibraryExists("adminmenu")) OnAdminMenuReady(GetAdminTopMenu());
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "adminmenu")) hTopMenu = null;
}

public void OnAdminMenuReady(Handle topmenu)
{
	if (topmenu == null) return;
	TopMenu menu = TopMenu.FromHandle(topmenu);
	if (menu == null || menu == hTopMenu) return;
	hTopMenu = menu;
	TopMenuObject category = FindTopMenuCategory(menu, "PlayerAssistance");
	if (category == INVALID_TOPMENUOBJECT)
		category = menu.AddCategory("PlayerAssistance", PlayerAssistanceCategory);
	if (category == INVALID_TOPMENUOBJECT) return;
	menu.AddItem("sm_noclip", AdminMenu_NoClip, category, "sm_noclip", ADMFLAG_SLAY | ADMFLAG_CHEATS);
}

public void PlayerAssistanceCategory(TopMenu menu, TopMenuAction action, TopMenuObject objectId,
	int client, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminPlayerAssistance", client);
}

/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod Basefuncommands Plugin
 * Provides noclip functionality
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

// Localized UI and target revalidation retained from admin_tools.


bool CanUseNoClip(int client)
{
	return CheckCommandAccess(client, "sm_noclip", ADMFLAG_SLAY | ADMFLAG_CHEATS);
}

void PerformNoClip(int client, int target)
{
	bool enable = GetEntityMoveType(target) != MOVETYPE_NOCLIP;
	SetEntityMoveType(target, enable ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
	LogAction(client, target, "\"%L\" %s noclip on \"%L\"", client, enable ? "enabled" : "disabled", target);
	ShowActivity2(client, "[SM] ", "%t", enable ? "AdminNoclipOn" : "AdminNoclipOff", target);
}

public void AdminMenu_NoClip(TopMenu menu, TopMenuAction action, TopMenuObject objectId,
	int client, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption) Format(buffer, maxlength, "%T", "AdminNoclip", client);
	else if (action == TopMenuAction_SelectOption) DisplayNoClipMenu(client);
}

void DisplayNoClipMenu(int client)
{
	if (!CanUseNoClip(client)) return;
	Menu menu = new Menu(MenuHandler_NoClip);
	menu.SetTitle("%T", "AdminNoclipTitle", client);
	menu.ExitBackButton = true;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target) || !IsPlayerAlive(target) || IsClientInKickQueue(target)
			|| !CanUserTarget(client, target)) continue;
		char info[16], name[MAX_NAME_LENGTH + 24];
		IntToString(GetClientUserId(target), info, sizeof(info));
		Format(name, sizeof(name), "%T", GetEntityMoveType(target) == MOVETYPE_NOCLIP ? "AdminNoclipRowOn" : "AdminNoclipRowOff", client, target);
		menu.AddItem(info, name);
	}
	if (menu.ItemCount == 0)
	{
		char label[192];
		Format(label, sizeof(label), "%T", "AdminNoAliveTargets", client);
		menu.AddItem("", label, ITEMDRAW_DISABLED);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_NoClip(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End) delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && hTopMenu != null)
		hTopMenu.Display(client, TopMenuPosition_LastCategory);
	else if (action == MenuAction_Select)
	{
		if (!CanUseNoClip(client)) return 0;
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		int target = GetClientOfUserId(StringToInt(info));
		if (target <= 0 || !IsClientInGame(target) || !IsPlayerAlive(target) || IsClientInKickQueue(target))
			PrintToChat(client, "[SM] %t", "AdminPlayerGone");
		else if (!CanUserTarget(client, target)) PrintToChat(client, "[SM] %t", "AdminTargetImmune");
		else PerformNoClip(client, target);
		DisplayNoClipMenu(client);
	}
	return 0;
}

public Action Command_NoClip(int client, int args)
{
	if (args != 1)
	{
		ReplyToCommand(client, "[SM] %t", "AdminNoclipSyntax");
		return Plugin_Handled;
	}
	char requested[65], targetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, requested, sizeof(requested));
	int targets[MAXPLAYERS];
	bool multilingual;
	int count = ProcessTargetString(requested, client, targets, sizeof(targets), COMMAND_FILTER_ALIVE,
		targetName, sizeof(targetName), multilingual);
	if (count <= 0) ReplyToCommand(client, "[SM] %t", "AdminNoclipNoMatch");
	else for (int i = 0; i < count; i++) PerformNoClip(client, targets[i]);
	return Plugin_Handled;
}
