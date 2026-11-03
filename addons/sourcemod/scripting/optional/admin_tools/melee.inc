Action CommandMelee(int client, int args)
{
	if (!AdminWeapons_CanSpawn(client, "sm_melee")) return Plugin_Handled;
	if (g_meleeUsed)
	{
		PrintToChat(client, "[SM] %t", "AdminMeleeUsed");
		return Plugin_Handled;
	}
	int table = FindStringTable("MeleeWeapons");
	if (table == INVALID_STRING_TABLE) return Plugin_Handled;
	static const char weapons[][] = { "pitchfork", "shovel", "crowbar" };
	float position[3];
	GetClientEyePosition(client, position);
	int count;
	for (int i = 0; i < sizeof(weapons); i++)
	{
		if (FindStringIndex(table, weapons[i]) == INVALID_STRING_INDEX) continue;
		int entity = CreateEntityByName("weapon_melee");
		if (entity == -1) break;
		DispatchKeyValue(entity, "melee_script_name", weapons[i]);
		if (!DispatchSpawn(entity)) { RemoveEntity(entity); continue; }
		// Match dropped secondary weapons: spawn unconstrained and let physics settle them.
		TeleportEntity(entity, position, NULL_VECTOR, NULL_VECTOR);
		count++;
	}
	if (count > 0)
	{
		g_meleeUsed = true;
		LogAction(client, -1, "\"%L\" spawned %d melee weapons", client, count);
		PrintToChat(client, "[SM] %t", "AdminMeleeSpawned");
	}
	return Plugin_Handled;
}
