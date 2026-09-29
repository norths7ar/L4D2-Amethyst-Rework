// Migrated from l4d2_saferoom_item_remove by Tabun, Sir, A1m` (1.1.1).
// The resource_rules framework profile owns round-start scheduling.
#if defined _resource_rules_saferoom_items_included
	#endinput
#endif
#define _resource_rules_saferoom_items_included

#include <l4d2_saferoom_detect>

enum
{
	SafeItems_Room_END = 1,
	SafeItems_Room_START = 2
};

enum
{
	SafeItems_Type = 0,					// 0
	SafeItems_Type_HEALTH = (1 << 0),	// 1
	SafeItems_Type_WEAPON = (1 << 1),	// 2
	SafeItems_Type_MELEE = (1 << 2),	// 4
	SafeItems_Type_OTHER = (1 << 3)		// 8
};

static ConVar
	g_safeItemsEnabled = null,
	g_safeItemsSaferooms = null,
	g_safeItemsTypes = null;

static StringMap
	g_safeItemsTrie = null;

void SafeItems_Init()
{
	SafeItems_PrepareTrie();

	g_safeItemsEnabled = CreateConVar("sm_safeitemkill_enable", "1", "Whether end saferoom items should be removed.", _, true, 0.0, true, 1.0);
	g_safeItemsSaferooms = CreateConVar("sm_safeitemkill_saferooms", "1", "Saferooms to empty. Flags: 1 = end saferoom, 2 = start saferoom (3 = kill items from both).", _, true, 0.0, true, 3.0);
	g_safeItemsTypes = CreateConVar("sm_safeitemkill_items", "7", "Types to rmove. Flags: 1 = health items, 2 = guns, 4 = melees, 8 = all other usable items", _, true, 0.0, true, 15.0);

}

void SafeItems_Run()
{
	if (!g_safeItemsEnabled.BoolValue) {
		return;
	}

	// check for any items in the end saferoom, and remove them
	char sClassname[128];
	int iCheckItem, iCountEnd = 0, iCountStart = 0;

	int iEntityCount = GetEntityCount();
	int iCvarSafeRoomValue = g_safeItemsSaferooms.IntValue;

	for (int i = (MaxClients + 1); i <= iEntityCount; i++) {
		if (!IsValidEntity(i)) {
			continue;
		}

		// check item type
		GetEntityClassname(i, sClassname, sizeof(sClassname));

		if (!g_safeItemsTrie.GetValue(sClassname, iCheckItem)) {
			continue;
		}

		// see if item is of a killable type by cvar
		if (iCheckItem == SafeItems_Type || g_safeItemsTypes.IntValue & iCheckItem) {
			if (iCvarSafeRoomValue & SafeItems_Room_END) {
				if (SAFEDETECT_IsEntityInEndSaferoom(i)) {
					// kill the item
					RemoveEntity(i);

					iCountEnd++;
					continue;
				}
			}

			if (iCvarSafeRoomValue & SafeItems_Room_START) {
				if (SAFEDETECT_IsEntityInStartSaferoom(i)) {
					// kill the item
					RemoveEntity(i);

					iCountStart++;
					continue;
				}
			}
		}
	}

	LogMessage("Removed %i saferoom item(s) (start: %i; end: %i).", iCountStart + iCountEnd, iCountStart, iCountEnd);
}

static void SafeItems_PrepareTrie()
{
	g_safeItemsTrie = new StringMap();

	g_safeItemsTrie.SetValue("weapon_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_ammo_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_pistol_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_pistol_magnum_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_smg_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_smg_silenced_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_pumpshotgun_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_shotgun_chrome_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_hunting_rifle_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_sniper_military_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_rifle_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_rifle_ak47_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_rifle_desert_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_autoshotgun_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_shotgun_spas_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_rifle_m60_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_grenade_launcher_spawn", SafeItems_Type_WEAPON);
	g_safeItemsTrie.SetValue("weapon_chainsaw_spawn", SafeItems_Type_WEAPON);

	g_safeItemsTrie.SetValue("weapon_melee_spawn", SafeItems_Type_MELEE);

	g_safeItemsTrie.SetValue("weapon_item_spawn", SafeItems_Type_HEALTH);
	g_safeItemsTrie.SetValue("weapon_first_aid_kit_spawn", SafeItems_Type_HEALTH);
	g_safeItemsTrie.SetValue("weapon_defibrillator_spawn", SafeItems_Type_HEALTH);
	g_safeItemsTrie.SetValue("weapon_pain_pills_spawn", SafeItems_Type_HEALTH);
	g_safeItemsTrie.SetValue("weapon_adrenaline_spawn", SafeItems_Type_HEALTH);

	g_safeItemsTrie.SetValue("weapon_pipe_bomb_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("weapon_molotov_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("weapon_vomitjar_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("weapon_gascan_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("upgrade_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("upgrade_laser_sight", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("weapon_upgradepack_explosive_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("weapon_upgradepack_incendiary_spawn", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("upgrade_ammo_incendiary", SafeItems_Type_OTHER);
	g_safeItemsTrie.SetValue("upgrade_ammo_explosive", SafeItems_Type_OTHER);

	//g_safeItemsTrie.SetValue(prop_fuel_barrel", SafeItems_Type);
	//g_safeItemsTrie.SetValue("prop_physics", SafeItems_Type);
}
