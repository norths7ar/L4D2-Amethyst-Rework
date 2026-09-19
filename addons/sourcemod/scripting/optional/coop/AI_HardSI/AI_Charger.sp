#pragma semicolon 1

#define DEBUG_CHARGER_TARGET 0

// custom convar
Handle hCvarChargeProximity;
Handle hCvarAimOffsetSensitivityCharger;
Handle hCvarHealthThresholdCharger;
int g_chargerTargetUserId[MAXPLAYERS + 1];
int bShouldCharge[MAXPLAYERS + 1]; // manual tracking of charge cooldown

public void Charger_OnModuleStart() {
	// Charge proximity
	hCvarChargeProximity = CreateConVar("ai_charge_proximity", "300", "How close a charger will approach before charging");	
	// Aim offset sensitivity
	hCvarAimOffsetSensitivityCharger = CreateConVar("ai_aim_offset_sensitivity_charger",
									"20",
									"If the charger has a target, it will not straight pounce if the target's aim on the horizontal axis is within this radius",
									FCVAR_NONE,
									true, 0.0, true, 179.0);
	// Health threshold
	hCvarHealthThresholdCharger = CreateConVar("ai_health_threshold_charger", "350", "Charger will charge if its health drops to this level");	
}

public void Charger_OnModuleEnd() {
}

/***********************************************************************************************************************************************************************************

																KEEP CHARGE ON COOLDOWN UNTIL WITHIN PROXIMITY

***********************************************************************************************************************************************************************************/

// Initialise spawned chargers
public Action Charger_OnSpawn(int botCharger) {
	bShouldCharge[botCharger] = false;
	g_chargerTargetUserId[botCharger] = 0;
	return Plugin_Handled;
}

public Action Charger_OnPlayerRunCmd(int charger, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon) {
	// Use the victim selected by the AI, not whichever player happens to cross
	// its crosshair while turning. Leave navigation/attacks alone during abilities.
	if (GetEntPropEnt(charger, Prop_Send, "m_carryVictim") > 0
		|| GetEntPropEnt(charger, Prop_Send, "m_pummelVictim") > 0
		|| L4D_IsPlayerStaggering(charger)) return Plugin_Continue;
	int ability = GetEntPropEnt(charger, Prop_Send, "m_customAbility");
	if (ability > MaxClients && IsValidEntity(ability)
		&& GetEntProp(ability, Prop_Send, "m_isCharging")) return Plugin_Continue;
	int target = GetClientOfUserId(g_chargerTargetUserId[charger]);
	if (!IsSurvivor(target) || !IsPlayerAlive(target)) return Plugin_Continue;
	float chargerPos[3];
	GetClientAbsOrigin(charger, chargerPos);
	int distance = GetSurvivorProximity(chargerPos, target);
	int chargerHealth = GetEntProp(charger, Prop_Send, "m_iHealth");
	if (chargerHealth > GetConVarInt(hCvarHealthThresholdCharger) && distance > GetConVarInt(hCvarChargeProximity)) {
		if (!bShouldCharge[charger]) BlockCharge(charger);
	} else {
		bShouldCharge[charger] = true;
	}
	return Charger_CorrectApproach(charger, target, buttons, vel, angles) ? Plugin_Changed : Plugin_Continue;
}

void BlockCharge(int charger) {
	int chargeEntity = GetEntPropEnt(charger, Prop_Send, "m_customAbility");
	if (chargeEntity > MaxClients && IsValidEntity(chargeEntity)
		&& GetEntPropFloat(chargeEntity, Prop_Send, "m_timestamp") <= GetGameTime() + 0.1) {  // charger entity persists for a short while after death; check ability entity is valid
		SetEntPropFloat(chargeEntity, Prop_Send, "m_timestamp", GetGameTime() + 0.1); // keep extending end of cooldown period
	} 			
}

void Charger_OnCharge(int charger) {
	// Share the same eligible-target policy with OnChooseVictim. Do not undo
	// its choice by turning the charge back into a pinned survivor.
	int aimTarget = GetClientOfUserId(g_chargerTargetUserId[charger]);
	if (!Charger_IsFreeTarget(aimTarget)
		|| GetPlayerAimOffset(aimTarget, charger) <= GetConVarFloat(hCvarAimOffsetSensitivityCharger)) {
		// Do not turn a close attack into a dash at someone farther away/behind.
		float position[3]; GetClientAbsOrigin(charger, position);
		float limit = GetConVarFloat(hCvarChargeProximity);
		if (Charger_IsFreeTarget(aimTarget)) {
			float distance = float(GetSurvivorProximity(position, aimTarget));
			if (distance < limit) limit = distance;
		}
		int alternative = Charger_GetNearbyUnpinnedTarget(charger, aimTarget, limit, true);
		if (alternative > 0) aimTarget = alternative;
	}
	if (Charger_IsFreeTarget(aimTarget) && Charger_HasChargeLine(charger, aimTarget))
		ChargePrediction(charger, aimTarget);
}

bool Charger_IsFreeTarget(int survivor) {
	return IsSurvivor(survivor) && IsPlayerAlive(survivor)
		&& !IsIncapacitated(survivor) && !IsPinned(survivor)
		&& !GetEntProp(survivor, Prop_Send, "m_isHangingFromLedge");
}

bool Charger_IsAbilityReady(int charger)
{
	int ability = GetEntPropEnt(charger, Prop_Send, "m_customAbility");
	return ability > MaxClients && IsValidEntity(ability)
		&& GetEntPropFloat(ability, Prop_Send, "m_timestamp") <= GetGameTime();
}

int Charger_GetNearbyUnpinnedTarget(int charger, int excluded, float maximum = 0.0, bool forwardOnly = false)
{
	float chargerPos[3], survivorPos[3];
	GetClientAbsOrigin(charger, chargerPos);
	int best = -1;
	float bestDistance = float(GetConVarInt(hCvarChargeProximity));
	ConVar cvChargeSpeed = FindConVar("z_charge_max_speed");
	ConVar cvChargeDuration = FindConVar("z_charge_duration");
	if (cvChargeSpeed != null && cvChargeDuration != null)
	{
		bestDistance = cvChargeSpeed.FloatValue * cvChargeDuration.FloatValue;
	}

	if (maximum > 0.0 && maximum < bestDistance) bestDistance = maximum;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (survivor == excluded || !Charger_IsFreeTarget(survivor))
		{
			continue;
		}
		GetClientAbsOrigin(survivor, survivorPos);
		if (forwardOnly && GetPlayerAimOffset(charger, survivor) > 90.0) continue;
		float distance = GetVectorDistance(chargerPos, survivorPos);
		if (distance <= bestDistance && Charger_HasChargeLine(charger, survivor))
		{
			best = survivor;
			bestDistance = distance;
		}
	}
	return best;
}

bool Charger_HasChargeLine(int charger, int survivor)
{
	float start[3], end[3];
	float mins[3] = {-16.0, -16.0, 0.0};
	float maxs[3] = {16.0, 16.0, 71.0};
	GetClientAbsOrigin(charger, start);
	GetClientAbsOrigin(survivor, end);
	if (FloatAbs(end[2] - start[2]) > 48.0) return false;
	start[2] += 1.0;
	end[2] += 1.0;
	Handle trace = TR_TraceHullFilterEx(start, end, mins, maxs, MASK_PLAYERSOLID, Charger_TraceFilter, charger);
	bool clear = !TR_DidHit(trace) || TR_GetEntityIndex(trace) == survivor;
	delete trace;
	return clear;
}

public bool Charger_TraceFilter(int entity, int contentsMask, int charger)
{
	return entity != charger;
}

void ChargePrediction(int charger, int survivor) {
	if( !IsBotCharger(charger) || !IsSurvivor(survivor) ) {
		return;
	}
	float survivorPos[3];
	float chargerPos[3];
	float attackDirection[3];
	float attackAngle[3];
	// Add some fancy schmancy trignometric prediction here; as a placeholder charger will face survivor directly
	GetClientAbsOrigin(charger, chargerPos);
	GetClientAbsOrigin(survivor, survivorPos);
	MakeVectorFromPoints( chargerPos, survivorPos, attackDirection );
	GetVectorAngles(attackDirection, attackAngle);	
	TeleportEntity(charger, NULL_VECTOR, attackAngle, NULL_VECTOR); 
}

// Anne's approach module also separates direct approaches from navigation.
// Only correct a backwards command on a short, level, supported, clear route.
// No forced charge, jump, turn, or interference with the engine's obstacle detours.
bool Charger_CorrectApproach(int charger, int target, int &buttons, float vel[3], const float angles[3]) {
	if (!Charger_IsFreeTarget(target) || !(GetEntityFlags(charger) & FL_ONGROUND)
		|| GetEntityMoveType(charger) != MOVETYPE_WALK || GetEntProp(charger, Prop_Data, "m_nWaterLevel") > 1) return false;
	float position[3], end[3], direction[3];
	GetClientAbsOrigin(charger, position); GetClientAbsOrigin(target, end);
	MakeVectorFromPoints(position, end, direction);
	float distance = GetVectorLength(direction);
	if (distance < 70.0 || distance > GetConVarFloat(hCvarChargeProximity)
		|| FloatAbs(direction[2]) > 18.0 || !Charger_HasChargeLine(charger, target)) return false;
	direction[2] = 0.0; NormalizeVector(direction, direction);
	float facing[3], forwardVector[3], right[3], movement[3];
	facing = angles; facing[0] = 0.0;
	GetAngleVectors(facing, forwardVector, right, NULL_VECTOR);
	for (int axis = 0; axis < 2; axis++) movement[axis] = forwardVector[axis] * vel[0] + right[axis] * vel[1];
	float speed = GetVectorLength(movement);
	if (speed < 1.0 || GetVectorDotProduct(movement, direction) >= 0.0) return false;
	for (float offset = 32.0; offset < distance; offset += 32.0) {
		float top[3], bottom[3];
		for (int axis = 0; axis < 3; axis++) top[axis] = position[axis] + direction[axis] * offset;
		top[2] += 18.0; bottom = top; bottom[2] -= 36.0;
		Handle trace = TR_TraceRayFilterEx(top, bottom, MASK_PLAYERSOLID, RayType_EndPoint, Charger_GroundFilter);
		float normal[3]; TR_GetPlaneNormal(trace, normal);
		bool supported = TR_DidHit(trace) && !TR_StartSolid(trace) && normal[2] >= 0.7;
		delete trace;
		if (!supported) return false;
	}
	vel[0] = GetVectorDotProduct(direction, forwardVector) * speed;
	vel[1] = GetVectorDotProduct(direction, right) * speed;
	buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);
	if (vel[0] > 0.0) buttons |= IN_FORWARD;
	else if (vel[0] < 0.0) buttons |= IN_BACK;
	if (vel[1] > 0.0) buttons |= IN_MOVERIGHT;
	else if (vel[1] < 0.0) buttons |= IN_MOVELEFT;
	return true;
}

public bool Charger_GroundFilter(int entity, int contentsMask) {
	return entity < 1 || entity > MaxClients;
}
