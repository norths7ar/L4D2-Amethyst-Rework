// One finite pickup of each basic gun, placed in the world rather than given
// to the administrator. The menu and chat command share permission/live checks.
static const char g_basicGunClasses[][] = {
	"weapon_smg_spawn", "weapon_smg_silenced_spawn",
	"weapon_pumpshotgun_spawn", "weapon_shotgun_chrome_spawn",
	"weapon_smg_mp5_spawn"
};

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
	float positions[sizeof(g_basicGunClasses)][3], angles[3];
	if (!FindBasicGunPositions(client, positions, angles))
	{
		PrintToChat(client, "[SM] %t", "AdminGunsNoGround");
		return;
	}
	int spawned[sizeof(g_basicGunClasses)], count;
	for (int i = 0; i < sizeof(g_basicGunClasses); i++)
	{
		int entity = CreateEntityByName(g_basicGunClasses[i]);
		if (entity == -1) break;
		DispatchKeyValueInt(entity, "count", 1);
		DispatchKeyValueInt(entity, "spawnflags", 0);
		DispatchKeyValueInt(entity, "spawn_without_director", 1);
		TeleportEntity(entity, positions[i], angles, NULL_VECTOR);
		if (!DispatchSpawn(entity)) { RemoveEntity(entity); break; }
		spawned[count++] = entity;
	}
	if (count != sizeof(g_basicGunClasses))
	{
		for (int i = 0; i < count; i++) RemoveEntity(spawned[i]);
		LogError("Could not spawn all basic guns for %L", client);
		PrintToChat(client, "[SM] %t", "AdminGunsFailed");
		return;
	}
	LogAction(client, -1, "\"%L\" spawned Uzi, MAC-10, MP5, pump and chrome shotguns", client);
	PrintToChat(client, "[SM] %t", "AdminGunsSpawned");
}

bool FindBasicGunPositions(int client, float positions[sizeof(g_basicGunClasses)][3], float angles[3])
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
	for (int i = 0; i < sizeof(g_basicGunClasses); i++)
	{
		float start[3], end[3];
		for (int axis = 0; axis < 3; axis++)
			start[axis] = center[axis] + ahead[axis] * (i == 4 ? 0.0 : (i < 2 ? -24.0 : 24.0))
				+ right[axis] * (i == 4 ? 0.0 : (i % 2 == 0 ? -24.0 : 24.0));
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
