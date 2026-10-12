// Spawn actual weapons, not dispensers. Each selected type contributes one gun.
// CWeaponSpawn ignores count depletion for primary weapons in Versus-based modes.
static const char g_basicGunNames[][] = {
	"smg", "smg_silenced", "pumpshotgun", "shotgun_chrome", "smg_mp5"
};
ConVar g_basicGuns;

void InitBasicGuns()
{
	g_basicGuns = CreateConVar("admin_guns_weapons", "smg,smg_silenced,smg_mp5,pumpshotgun,shotgun_chrome",
		"Comma-separated T1 weapons for !guns; empty disables spawning.");
}

int ReadBasicGuns(int selected[5])
{
	char list[256], names[6][64];
	g_basicGuns.GetString(list, sizeof(list));
	TrimString(list);
	if (!list[0]) return 0;
	int entries = ExplodeString(list, ",", names, sizeof(names), sizeof(names[]));
	if (entries > sizeof(g_basicGunNames)) return -1;
	int count;
	bool included[sizeof(g_basicGunNames)];
	for (int i = 0; i < entries; i++)
	{
		TrimString(names[i]);
		int index = -1;
		for (int j = 0; j < sizeof(g_basicGunNames); j++)
			if (StrEqual(names[i], g_basicGunNames[j])) { index = j; break; }
		if (index == -1) return -1;
		if (included[index]) continue;
		included[index] = true;
		selected[count++] = index;
	}
	return count;
}

Action CommandGuns(int client, int args)
{
	SpawnBasicGuns(client);
	return Plugin_Handled;
}

public void GunsTopMenu(TopMenu menu, TopMenuAction action, TopMenuObject objectId,
	int client, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminBasicGuns", client);
	else if (action == TopMenuAction_SelectOption)
	{
		SpawnBasicGuns(client);
		menu.Display(client, TopMenuPosition_LastCategory);
	}
}

void SpawnBasicGuns(int client)
{
	if (client == 0 || !IsClientInGame(client))
	{
		ReplyToCommand(client, "[SM] %t", "AdminGunsInGame");
		return;
	}
	if (!CheckCommandAccess(client, "sm_guns", ADMFLAG_CHEATS)) return;
	if (GetFeatureStatus(FeatureType_Native, "IsInReady") != FeatureStatus_Available
		|| !IsInReady() || MapRules_IsLive())
	{
		PrintToChat(client, "[SM] %t", "AdminGunsReadyOnly");
		return;
	}
	int selected[5];
	int requested = ReadBasicGuns(selected);
	if (requested <= 0)
	{
		if (requested < 0) LogError("Invalid admin_guns_weapons: use comma-separated T1 weapon names.");
		PrintToChat(client, "[SM] %t", requested == 0 ? "AdminGunsDisabled" : "AdminGunsFailed");
		return;
	}
	float positions[5][3], angles[3];
	if (!FindBasicGunPositions(client, requested, positions, angles))
	{
		PrintToChat(client, "[SM] %t", "AdminGunsNoGround");
		return;
	}
	int spawned[5], count;
	for (int i = 0; i < requested; i++)
	{
		char classname[64], model[PLATFORM_MAX_PATH];
		FormatEx(classname, sizeof(classname), "weapon_%s", g_basicGunNames[selected[i]]);
		L4D2_GetWeaponModelByWeaponId(L4D2_GetWeaponIdByWeaponName(classname), model, sizeof(model));
		Format(model, sizeof(model), "models%s", model);
		PrecacheModel(model);
		int entity = CreateEntityByName(classname);
		if (entity == -1) break;
		ConVar ammo = FindConVar(selected[i] == 2 || selected[i] == 3 ? "ammo_shotgun_max" : "ammo_smg_max");
		DispatchKeyValueInt(entity, "ammo", ammo.IntValue);
		DispatchKeyValueInt(entity, "spawnflags", 1);
		TeleportEntity(entity, positions[i], angles, NULL_VECTOR);
		if (!DispatchSpawn(entity)) { RemoveEntity(entity); break; }
		spawned[count++] = entity;
	}
	if (count != requested)
	{
		for (int i = 0; i < count; i++) RemoveEntity(spawned[i]);
		LogError("Could not spawn all basic guns for %L", client);
		PrintToChat(client, "[SM] %t", "AdminGunsFailed");
		return;
	}
	LogAction(client, -1, "\"%L\" spawned %d configured T1 weapons", client, count);
	PrintToChat(client, "[SM] %t", "AdminGunsSpawned");
}

bool FindBasicGunPositions(int client, int count, float positions[5][3], float angles[3])
{
	float eye[3], aim[3], center[3], normal[3];
	GetClientEyePosition(client, eye);
	GetClientEyeAngles(client, aim);
	Handle trace = TR_TraceRayFilterEx(eye, aim, MASK_SOLID, RayType_Infinite, GunsTraceFilter);
	bool hit = TR_DidHit(trace) && !TR_StartSolid(trace);
	if (hit)
	{
		TR_GetEndPosition(center, trace);
		TR_GetPlaneNormal(trace, normal);
	}
	delete trace;
	if (!hit || normal[2] < 0.7) return false;
	angles[0] = 0.0;
	angles[1] = aim[1];
	angles[2] = 90.0;
	float yaw[3], ahead[3], right[3];
	yaw[1] = aim[1];
	GetAngleVectors(yaw, ahead, right, NULL_VECTOR);
	for (int i = 0; i < count; i++)
	{
		float start[3], end[3];
		for (int axis = 0; axis < 3; axis++)
			start[axis] = center[axis] + ahead[axis] * ((i / 3) * 48.0)
				+ right[axis] * ((i % 3) - (count < 3 ? (count - 1) / 2.0 : 1.0)) * 48.0;
		start[2] += 24.0;
		end = start;
		end[2] -= 64.0;
		trace = TR_TraceRayFilterEx(start, end, MASK_SOLID, RayType_EndPoint, GunsTraceFilter);
		hit = TR_DidHit(trace) && !TR_StartSolid(trace);
		if (hit)
		{
			TR_GetEndPosition(positions[i], trace);
			TR_GetPlaneNormal(trace, normal);
		}
		delete trace;
		if (!hit || normal[2] < 0.7) return false;
		positions[i][2] += 3.0;
	}
	return true;
}

public bool GunsTraceFilter(int entity, int contentsMask)
{
	return entity == 0 || entity > MaxClients;
}
