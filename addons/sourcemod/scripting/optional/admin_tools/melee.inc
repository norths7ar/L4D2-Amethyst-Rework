Action CommandMelee(int client, int args)
{
	if (!AdminWeapons_CanSpawn(client, "sm_melee", "AdminMeleeReadyOnly")) return Plugin_Handled;
	int table = FindStringTable("MeleeWeapons");
	if (table == INVALID_STRING_TABLE) return Plugin_Handled;
	static const char weapons[][] = { "pitchfork", "shovel", "crowbar" };
	float positions[5][3], angles[3];
	if (!FindAdminWeaponPositions(client, sizeof(weapons), positions, angles))
	{
		PrintToChat(client, "[SM] %t", "AdminGunsNoGround");
		return Plugin_Handled;
	}
	int count;
	for (int i = 0; i < sizeof(weapons); i++)
	{
		if (FindStringIndex(table, weapons[i]) == INVALID_STRING_INDEX) continue;
		int entity = CreateEntityByName("weapon_melee");
		if (entity == -1) break;
		DispatchKeyValue(entity, "melee_script_name", weapons[i]);
		DispatchKeyValueInt(entity, "spawnflags", 1);
		TeleportEntity(entity, positions[i], angles, NULL_VECTOR);
		if (!DispatchSpawn(entity)) { RemoveEntity(entity); continue; }
		count++;
	}
	if (count > 0)
	{
		LogAction(client, -1, "\"%L\" spawned %d melee weapons", client, count);
		PrintToChat(client, "[SM] %t", "AdminMeleeSpawned");
	}
	return Plugin_Handled;
}
