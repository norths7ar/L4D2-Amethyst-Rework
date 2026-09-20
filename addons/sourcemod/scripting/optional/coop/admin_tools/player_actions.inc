// Player operations shared by the Coop admin menu. Generation stays in All4Dead.
// Target identities travel with each menu item, not in global selection state.

TopMenu hTopMenu;

#include "noclip.inc"

static const char g_playerActionIds[][] = {
	"a4d_health_menu", "a4d_ammo_menu", "a4d_respawn_menu", "a4d_teleport_menu"
};
static const char g_playerActionLabels[][] = {
	"AdminHeal", "AdminAmmo", "AdminRespawn", "AdminTeleport"
};

void InitPlayerActions()
{
	RegAdminCmd("sm_noclip", Command_NoClip, ADMFLAG_SLAY | ADMFLAG_CHEATS, "sm_noclip <#userid|name>");
	if (LibraryExists("adminmenu")) OnAdminMenuReady(GetAdminTopMenu());
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "adminmenu")) hTopMenu = null;
}

public void OnAdminMenuReady(Handle topmenu)
{
	TopMenu menu = TopMenu.FromHandle(topmenu);
	if (menu == null || menu == hTopMenu) return;
	hTopMenu = menu;
	TopMenuObject category = menu.AddCategory("PlayerAssistance", PlayerAssistanceCategory);
	if (category == INVALID_TOPMENUOBJECT) return;
	menu.AddItem("sm_noclip", AdminMenu_NoClip, category, "sm_noclip", ADMFLAG_SLAY | ADMFLAG_CHEATS);
	for (int i = 0; i < sizeof(g_playerActionIds); i++)
		menu.AddItem(g_playerActionIds[i], PlayerActionTopMenu, category, g_playerActionIds[i], ADMFLAG_CHEATS);
}

public void PlayerAssistanceCategory(TopMenu menu, TopMenuAction action, TopMenuObject objectId,
	int client, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminPlayerAssistance", client);
}

public void PlayerActionTopMenu(TopMenu menu, TopMenuAction action, TopMenuObject objectId,
	int client, char[] buffer, int maxlength)
{
	char name[64];
	menu.GetObjName(objectId, name, sizeof(name));
	for (int i = 0; i < sizeof(g_playerActionIds); i++)
	{
		if (!StrEqual(name, g_playerActionIds[i])) continue;
		if (action == TopMenuAction_DisplayOption) Format(buffer, maxlength, "%T", g_playerActionLabels[i], client);
		else if (action == TopMenuAction_SelectOption) ShowPlayerActionTargets(client, i);
		return;
	}
}

bool IsActionTarget(int client, bool alive)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client)
		&& !IsClientInKickQueue(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) == alive;
}

bool CanPerformPlayerAction(int client, int action)
{
	return client > 0 && IsClientInGame(client) && action >= 0 && action < sizeof(g_playerActionIds)
		&& CheckCommandAccess(client, g_playerActionIds[action], ADMFLAG_CHEATS);
}

void ShowPlayerActionTargets(int client, int action)
{
	if (!CanPerformPlayerAction(client, action)) return;
	Menu menu = new Menu(PlayerActionTargetHandler);
	char label[128];
	Format(label, sizeof(label), "%T", g_playerActionLabels[action], client);
	menu.SetTitle("%T", "AdminSelectPlayer", client, label);
	menu.ExitBackButton = true;
	if (action == 3)
	{
		AddAdminMenuItem(menu, client, "3:checkpoint", "AdminCheckpoint");
		AddAdminMenuItem(menu, client, "3:all", "AdminAllDest");
	}
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsActionTarget(target, action != 2) || !CanUserTarget(client, target)) continue;
		char info[48], name[MAX_NAME_LENGTH];
		Format(info, sizeof(info), "%d:%d", action, GetClientUserId(target));
		GetClientName(target, name, sizeof(name));
		menu.AddItem(info, name);
	}
	if (menu.ItemCount == 0) AddAdminMenuItem(menu, client, "", "AdminNoTargets", ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PlayerActionTargetHandler(Menu menu, MenuAction event, int client, int item)
{
	if (event == MenuAction_End) delete menu;
	else if (event == MenuAction_Cancel && item == MenuCancel_ExitBack && hTopMenu != null)
		hTopMenu.Display(client, TopMenuPosition_LastCategory);
	else if (event == MenuAction_Select)
	{
		char info[48], fields[2][24];
		menu.GetItem(item, info, sizeof(info));
		if (ExplodeString(info, ":", fields, sizeof(fields), sizeof(fields[])) != 2) return 0;
		int action = StringToInt(fields[0]);
		if (!CanPerformPlayerAction(client, action)) return 0;
		if (action == 3)
		{
			if (StrEqual(fields[1], "checkpoint"))
			{
				// This engine command necessarily moves everyone; respect target immunity.
				for (int target = 1; target <= MaxClients; target++)
					if (IsActionTarget(target, true) && !CanUserTarget(client, target))
					{
						PrintToChat(client, "[SM] %t", "AdminTeamImmune");
						ShowPlayerActionTargets(client, action);
						return 0;
					}
				ExecutePlayerCheat(client, "warp_all_survivors_to_checkpoint", "");
				LogAction(client, -1, "\"%L\" warped survivors to checkpoint", client);
				ShowPlayerActionTargets(client, action);
			}
			else ShowTeleportDestinations(client, fields[1]);
			return 0;
		}
		int target = GetClientOfUserId(StringToInt(fields[1]));
		if (!IsActionTarget(target, action != 2)) PrintToChat(client, "[SM] %t", "AdminTargetChanged");
		else if (!CanUserTarget(client, target)) PrintToChat(client, "[SM] %t", "AdminTargetImmune");
		else
		{
			if (action == 2) L4D_RespawnPlayer(target);
			else ExecutePlayerCheat(target, "give", action == 0 ? "health" : "ammo");
			ShowActivity2(client, "[SM] ", "%t", action == 0 ? "AdminHealActivity" : (action == 1 ? "AdminAmmoActivity" : "AdminRespawnActivity"), target);
			LogAction(client, target, "\"%L\" used %s on \"%L\"", client, g_playerActionIds[action], target);
		}
		ShowPlayerActionTargets(client, action);
	}
	return 0;
}

void ShowTeleportDestinations(int client, const char[] source)
{
	if (!CanPerformPlayerAction(client, 3)) return;
	bool all = StrEqual(source, "all");
	int origin = all ? 0 : GetClientOfUserId(StringToInt(source));
	if (!all && (!IsActionTarget(origin, true) || !CanUserTarget(client, origin)))
	{
		PrintToChat(client, "[SM] %t", "AdminOriginInvalid");
		ShowPlayerActionTargets(client, 3);
		return;
	}
	Menu menu = new Menu(TeleportDestinationHandler);
	if (all) menu.SetTitle("%T", "AdminTeleportAllTitle", client);
	else menu.SetTitle("%T", "AdminTeleportTitle", client, origin);
	menu.ExitBackButton = true;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsActionTarget(target, true) || target == origin) continue;
		char info[48], name[MAX_NAME_LENGTH];
		Format(info, sizeof(info), "%s:%d", source, GetClientUserId(target));
		GetClientName(target, name, sizeof(name));
		menu.AddItem(info, name);
	}
	if (menu.ItemCount == 0) AddAdminMenuItem(menu, client, "", "AdminNoDest", ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TeleportDestinationHandler(Menu menu, MenuAction event, int client, int item)
{
	if (event == MenuAction_End) delete menu;
	else if (event == MenuAction_Cancel && item == MenuCancel_ExitBack) ShowPlayerActionTargets(client, 3);
	else if (event == MenuAction_Select)
	{
		if (!CanPerformPlayerAction(client, 3)) return 0;
		char info[48], fields[2][24];
		menu.GetItem(item, info, sizeof(info));
		if (ExplodeString(info, ":", fields, sizeof(fields), sizeof(fields[])) != 2) return 0;
		int destination = GetClientOfUserId(StringToInt(fields[1]));
		if (!IsActionTarget(destination, true))
		{
			PrintToChat(client, "[SM] %t", "AdminDestInvalid");
			ShowTeleportDestinations(client, fields[0]);
			return 0;
		}
		bool all = StrEqual(fields[0], "all");
		int origin = all ? 0 : GetClientOfUserId(StringToInt(fields[0]));
		if (!all && (!IsActionTarget(origin, true) || !CanUserTarget(client, origin)))
		{
			PrintToChat(client, "[SM] %t", "AdminOriginInvalid");
			ShowPlayerActionTargets(client, 3);
			return 0;
		}
		float position[3], velocity[3];
		GetClientAbsOrigin(destination, position);
		int count;
		for (int target = 1; target <= MaxClients; target++)
		{
			if (!all && target != origin) continue;
			if (target == destination || !IsActionTarget(target, true) || !CanUserTarget(client, target)) continue;
			TeleportEntity(target, position, NULL_VECTOR, velocity);
			LogAction(client, target, "\"%L\" teleported \"%L\" to \"%L\"", client, target, destination);
			count++;
		}
		ShowActivity2(client, "[SM] ", "%t", "AdminTeleportActivity", count, destination);
		ShowPlayerActionTargets(client, 3);
	}
	return 0;
}

void ExecutePlayerCheat(int client, const char[] command, const char[] arguments)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
}

void AddAdminMenuItem(Menu menu, int client, const char[] info, const char[] phrase, int style = ITEMDRAW_DEFAULT)
{
	char label[192];
	Format(label, sizeof(label), "%T", phrase, client);
	menu.AddItem(info, label, style);
}
