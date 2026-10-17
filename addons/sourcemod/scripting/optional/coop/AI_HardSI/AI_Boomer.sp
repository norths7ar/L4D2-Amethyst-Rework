#pragma semicolon 1

// Spray targeting/angle-ordered turns and pitch compensation ported from
// CompetitiveWithAnne optional/AnneHappy/ai_boomer_2.sp (GPL-3.0).
// Profiles can bound HardSI's jump impulse. Native ability state owns cooldown and spray duration;
// every compensation, including zero-frame turns, rechecks the current target.
#define BoostForwardBoomer 90.0
#define BOOMER_TURN_ANGLE_DIVIDE 3.0
#define BOOMER_PLAYER_HEIGHT 72.0

Handle hCvarBoomerExposedTimeTolerance;
Handle hCvarBoomerVomitDelay;
ConVar hAllowBhop;
ConVar g_boomerBhopMaxSpeed, g_boomerBhopVerticalSpeed;
ConVar g_boomerRange, g_boomerUpVision, g_boomerTurnVision;
ConVar g_boomerTurnInterval, g_boomerDegree, g_boomerAutoFrame;
ArrayList g_boomerTargets[MAXPLAYERS + 1]; // [angle at selection, target userid]
int g_boomerTargetIndex[MAXPLAYERS + 1], g_boomerWaitFrames[MAXPLAYERS + 1];
int g_boomerFirstTarget[MAXPLAYERS + 1];
bool g_boomerSpraying[MAXPLAYERS + 1], g_boomerQueueBuilt[MAXPLAYERS + 1];
bool g_boomerBiled[MAXPLAYERS + 1];

public void Boomer_OnModuleStart()
{
	hCvarBoomerExposedTimeTolerance = FindConVar("boomer_exposed_time_tolerance");
	hCvarBoomerVomitDelay = FindConVar("boomer_vomit_delay");
	hAllowBhop = CreateConVar("ai_boomer_bhop", "1", "Flag to enable bhop facsimile on AI Boomers");
	g_boomerBhopMaxSpeed = CreateConVar("ai_boomer_bhop_max_speed", "-1", "Maximum horizontal launch speed in units/s; -1 keeps the original impulse, 0 zeros horizontal launch velocity.", _, true, -1.0);
	g_boomerBhopVerticalSpeed = CreateConVar("ai_boomer_bhop_vertical_speed", "-1", "Vertical launch speed in units/s; -1 keeps the original jump.", _, true, -1.0);
	g_boomerRange = FindConVar("z_vomit_range");
	g_boomerUpVision = CreateConVar("ai_BoomerUpVision", "1", "Boomer 喷吐时是否上抬视角", _, true, 0.0, true, 1.0);
	g_boomerTurnVision = CreateConVar("ai_BoomerTurnVision", "1", "Boomer 喷吐时是否旋转视角", _, true, 0.0, true, 1.0);
	g_boomerTurnInterval = CreateConVar("ai_BoomerTurnInterval", "15", "Boomer 喷吐转移目标的固定等待帧数", _, true, 0.0);
	g_boomerDegree = CreateConVar("ai_BoomerDegreeForceBile", "10", "允许补中目标的水平夹角；0 禁用补中", _, true, 0.0, true, 180.0);
	g_boomerAutoFrame = CreateConVar("ai_BoomerAutoFrame", "1", "按目标夹角计算等待帧数", _, true, 0.0, true, 1.0);
	SetConVarFloat(hCvarBoomerExposedTimeTolerance, 10000.0);
	SetConVarFloat(hCvarBoomerVomitDelay, 0.1);
}

public void Boomer_OnModuleEnd()
{
	ResetConVar(hCvarBoomerExposedTimeTolerance);
	ResetConVar(hCvarBoomerVomitDelay);
	// Survivor bile events remain tracked while AI control is disabled.
	for (int client = 1; client <= MaxClients; client++) Boomer_ResetSpray(client);
}

void Boomer_ResetSpray(int client)
{
	if (g_boomerTargets[client] != null) g_boomerTargets[client].Clear();
	g_boomerTargetIndex[client] = 0;
	g_boomerWaitFrames[client] = 0;
	g_boomerFirstTarget[client] = 0;
	g_boomerSpraying[client] = false;
	g_boomerQueueBuilt[client] = false;
}

void Boomer_ResetAll()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		Boomer_ResetSpray(client);
		g_boomerBiled[client] = false;
	}
}

public Action Boomer_OnSpawn(int client)
{
	Boomer_ResetSpray(client);
	return Plugin_Continue;
}

public void Boomer_OnBileState(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0) g_boomerBiled[client] = StrEqual(name, "player_now_it");
}

public void Boomer_OnDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		Boomer_ResetSpray(client);
		g_boomerBiled[client] = false;
	}
}

bool Boomer_IsSpraying(int client)
{
	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	return ability > MaxClients && IsValidEntity(ability)
		&& GetEntProp(ability, Prop_Send, "m_isSpraying") != 0;
}

bool Boomer_ValidTarget(int target)
{
	return target > 0 && target <= MaxClients && IsClientInGame(target)
		&& GetClientTeam(target) == 2 && IsPlayerAlive(target);
}

// Anne traces to the eyes and lets bile pass already-covered survivors.
public bool Boomer_TraceFilter(int entity, int contentsMask, any self)
{
	if (entity == self) return false;
	if (entity > 0 && entity <= MaxClients && g_boomerBiled[entity]) return false;
	return true;
}

bool Boomer_TargetVisible(int client, int target)
{
	if (!Boomer_ValidTarget(target)) return false;
	float eye[3], other[3];
	GetClientEyePosition(client, eye);
	GetClientEyePosition(target, other);
	if (GetVectorDistance(eye, other) > g_boomerRange.FloatValue) return false;
	Handle trace = TR_TraceRayFilterEx(eye, other, MASK_VISIBLE, RayType_EndPoint, Boomer_TraceFilter, client);
	bool visible = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == target;
	delete trace;
	return visible;
}

float Boomer_TargetAngle(int client, int target)
{
	float eye[3], other[3], direction[3], angles[3], facing[3];
	GetClientEyePosition(client, eye);
	GetClientEyePosition(target, other);
	eye[2] = other[2] = 0.0;
	MakeVectorFromPoints(eye, other, direction);
	if (NormalizeVector(direction, direction) == 0.0) return 0.0;
	GetClientEyeAngles(client, angles);
	angles[0] = angles[2] = 0.0;
	GetAngleVectors(angles, facing, NULL_VECTOR, NULL_VECTOR);
	float dot = GetVectorDotProduct(direction, facing);
	dot = dot > 1.0 ? 1.0 : (dot < -1.0 ? -1.0 : dot);
	return RadToDeg(ArcCosine(dot));
}

void Boomer_Aim(int client, int target, float angles[3])
{
	float eye[3], other[3], direction[3];
	GetClientEyePosition(client, eye);
	GetClientEyePosition(target, other);
	MakeVectorFromPoints(eye, other, direction);
	GetVectorAngles(direction, angles);
	if (angles[0] > 180.0) angles[0] -= 360.0;
	if (g_boomerUpVision.BoolValue)
	{
		// Anne's distance/height compensation and minimum upward pitch.
		float factor = eye[2] - other[2] > 0.0 ? 1.5 : 0.8;
		angles[0] -= GetVectorDistance(eye, other) / (BOOMER_PLAYER_HEIGHT * factor);
		if (angles[0] > -5.0) angles[0] = -5.0;
	}
	if (angles[0] < -89.0) angles[0] = -89.0;
	if (angles[0] > 89.0) angles[0] = 89.0;
	angles[2] = 0.0;
	TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
}

bool Boomer_CanCompensate(int client, int target)
{
	return g_boomerDegree.FloatValue > 0.0 && IsPlayerAlive(client)
		&& Boomer_IsSpraying(client) && !L4D_IsPlayerStaggering(client)
		&& Boomer_ValidTarget(target) && !g_boomerBiled[target]
		&& Boomer_TargetVisible(client, target)
		&& Boomer_TargetAngle(client, target) <= g_boomerDegree.FloatValue;
}

public void L4D_OnVomitedUpon_Post(int victim, int attacker, bool boomerExplosion)
{
	if (Boomer_ValidTarget(victim)) g_boomerBiled[victim] = true;
	if (!g_bHardSIActive || attacker <= 0 || attacker > MaxClients
		|| !IsClientInGame(attacker) || !IsFakeClient(attacker) || !IsPlayerAlive(attacker)
		|| GetClientTeam(attacker) != 3 || GetInfectedClass(attacker) != L4D2Infected_Boomer
		|| !Boomer_IsSpraying(attacker) || L4D_IsPlayerStaggering(attacker)
		|| g_boomerQueueBuilt[attacker]) return;

	// A successful first hit opens one queue per spray. Compensated hits also
	// dispatch this forward, so mark it built before collecting more targets.
	g_boomerQueueBuilt[attacker] = true;
	g_boomerSpraying[attacker] = true;
	g_boomerWaitFrames[attacker] = 0;
	if (g_boomerTargets[attacker] == null) g_boomerTargets[attacker] = new ArrayList(2);
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!Boomer_ValidTarget(target) || g_boomerBiled[target]
			|| !Boomer_TargetVisible(attacker, target)) continue;
		any row[2];
		row[0] = Boomer_TargetAngle(attacker, target);
		row[1] = GetClientUserId(target);
		g_boomerTargets[attacker].PushArray(row);
	}
	g_boomerTargets[attacker].Sort(Sort_Ascending, Sort_Float);
}

void Boomer_UpdateSpray(int client, int firstTarget, float angles[3])
{
	int target, wait;
	if (g_boomerQueueBuilt[client])
	{
		if (!g_boomerTurnVision.BoolValue) return;
		if (g_boomerTargetIndex[client] >= g_boomerTargets[client].Length) return;
		any row[2];
		g_boomerTargets[client].GetArray(g_boomerTargetIndex[client], row);
		target = GetClientOfUserId(row[1]);
		wait = g_boomerAutoFrame.BoolValue
			? RoundToNearest(view_as<float>(row[0]) / BOOMER_TURN_ANGLE_DIVIDE)
			: g_boomerTurnInterval.IntValue;
		if (!Boomer_ValidTarget(target) || g_boomerBiled[target])
		{
			g_boomerTargetIndex[client]++;
			g_boomerWaitFrames[client] = 0;
			return;
		}
	}
	else
	{
		target = firstTarget;
		if (!Boomer_ValidTarget(target) || g_boomerBiled[target]) return;
		int userid = GetClientUserId(target);
		if (g_boomerFirstTarget[client] != userid)
		{
			g_boomerFirstTarget[client] = userid;
			g_boomerWaitFrames[client] = 0;
		}
		wait = g_boomerTurnInterval.IntValue;
	}

	Boomer_Aim(client, target, angles);
	if (g_boomerWaitFrames[client] < wait)
	{
		g_boomerWaitFrames[client]++;
		return;
	}
	bool queued = g_boomerQueueBuilt[client];
	// Zero means check now, never bypass the current range/angle/trace checks.
	if (Boomer_CanCompensate(client, target))
		L4D_CTerrorPlayer_OnVomitedUpon(target, client);
	if (queued)
	{
		g_boomerTargetIndex[client]++;
		g_boomerWaitFrames[client] = 0;
	}
}

public Action Boomer_OnPlayerRunCmd(int boomer, int& buttons, float vel[3], float angles[3])
{
	bool spraying = Boomer_IsSpraying(boomer);
	if (!spraying && g_boomerSpraying[boomer]) Boomer_ResetSpray(boomer);
	if (L4D_IsPlayerStaggering(boomer))
	{
		Boomer_ResetSpray(boomer);
		buttons &= ~IN_ATTACK;
		return Plugin_Changed;
	}

	int flags = GetEntityFlags(boomer);
	float vomit_range = g_boomerRange.FloatValue;
	float clientEyeAngles[3], boomerPos[3];
	GetClientEyeAngles(boomer, clientEyeAngles);
	GetClientAbsOrigin(boomer, boomerPos);
	int targetSurvivor = GetClosestSurvivor(boomerPos);
	if (!Boomer_ValidTarget(targetSurvivor)) return Plugin_Continue;
	int proximity = GetSurvivorProximity(boomerPos, targetSurvivor);
	bool hasSight = view_as<bool>(GetEntProp(boomer, Prop_Send, "m_hasVisibleThreats"));

	if (spraying)
	{
		g_boomerSpraying[boomer] = true;
		Boomer_UpdateSpray(boomer, targetSurvivor, angles);
	}

	int ability = GetEntPropEnt(boomer, Prop_Send, "m_customAbility");
	if (!spraying && (flags & FL_ONGROUND) && hasSight && proximity <= vomit_range
		&& ability > MaxClients && IsValidEntity(ability)
		&& GetEntPropFloat(ability, Prop_Send, "m_timestamp") <= GetGameTime())
	{
		Boomer_Aim(boomer, targetSurvivor, angles);
		buttons |= IN_FORWARD | IN_ATTACK;
	}

	// Keep the distance gate; profiles may bound the launch without changing spray behavior.
	if (hAllowBhop.BoolValue && hasSight && proximity > vomit_range - 100)
	{
		buttons &= ~IN_ATTACK;
		buttons |= IN_FORWARD;
		if (flags & FL_ONGROUND)
		{
			float targetPos[3], straightVector[3];
			GetClientAbsOrigin(targetSurvivor, targetPos);
			SubtractVectors(targetPos, boomerPos, straightVector);
			float maxSpeed = g_boomerBhopMaxSpeed.FloatValue;
			float verticalSpeed = g_boomerBhopVerticalSpeed.FloatValue;
			if (maxSpeed < 0.0 && verticalSpeed < 0.0)
			{
				buttons |= IN_JUMP;
				TeleportEntity(boomer, NULL_VECTOR, NULL_VECTOR, straightVector);
				Client_Push(boomer, clientEyeAngles, BoostForwardBoomer);
			}
			else
			{
				float forwardVector[3];
				// Preserve the original horizontal impulse; override lift separately below.
				GetAngleVectors(clientEyeAngles, forwardVector, NULL_VECTOR, NULL_VECTOR);
				ScaleVector(forwardVector, BoostForwardBoomer);
				AddVectors(straightVector, forwardVector, straightVector);
				float horizontalSpeed = SquareRoot(straightVector[0] * straightVector[0] + straightVector[1] * straightVector[1]);
				if (maxSpeed >= 0.0 && horizontalSpeed > maxSpeed)
				{
					straightVector[0] *= maxSpeed / horizontalSpeed;
					straightVector[1] *= maxSpeed / horizontalSpeed;
				}
				if (verticalSpeed >= 0.0)
				{
					straightVector[2] = verticalSpeed;
					// Launch directly: IN_JUMP would add the engine's normal jump impulse.
					buttons &= ~IN_JUMP;
					SetEntPropEnt(boomer, Prop_Send, "m_hGroundEntity", -1);
					SetEntityFlags(boomer, flags & ~FL_ONGROUND);
					bHasBeenShoved[boomer] = false;
				}
				else buttons |= IN_JUMP;
				TeleportEntity(boomer, NULL_VECTOR, NULL_VECTOR, straightVector);
			}
		}
		else if (GetEntityMoveType(boomer) == MOVETYPE_LADDER) buttons &= ~IN_JUMP;
	}
	// Anne: don't let claw input steal the spray animation.
	if (spraying || (buttons & IN_ATTACK)) buttons &= ~IN_ATTACK2;
	return Plugin_Changed;
}
