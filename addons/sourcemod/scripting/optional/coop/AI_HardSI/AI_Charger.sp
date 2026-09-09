#pragma semicolon 1

#define DEBUG_CHARGER_TARGET 0

// custom convar
Handle hCvarChargeProximity;
Handle hCvarAimOffsetSensitivityCharger;
Handle hCvarHealthThresholdCharger;
int bShouldCharge[MAXPLAYERS]; // manual tracking of charge cooldown

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
	return Plugin_Handled;
}

public Action Charger_OnPlayerRunCmd(int charger, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon) {
	// prevent charge until survivors are within the defined proximity
	float chargerPos[3];
	GetClientAbsOrigin(charger, chargerPos);
	int target = GetClientAimTarget(charger);	
	int iSurvivorProximity = GetSurvivorProximity(chargerPos, target); // invalid(=-1) target will cause GetSurvivorProximity() to return distance to closest survivor
	int chargerHealth = GetEntProp(charger, Prop_Send, "m_iHealth");
	//new String:sweapon[32];
	//if (!target) return Plugin_Handled;
	//GetClientWeapon(target, sweapon, sizeof(sweapon));
	//PrintToChatAll("Charger 的目标正在使用的武器：%s", sweapon);
	if( (chargerHealth > GetConVarInt(hCvarHealthThresholdCharger) && iSurvivorProximity > GetConVarInt(hCvarChargeProximity)) ) {
		if( !bShouldCharge[charger] ) { 				
			BlockCharge(charger);
			return Plugin_Changed;
		}
	} else {
		bShouldCharge[charger] = true;
	}
	return Plugin_Continue;
}

void BlockCharge(int charger) {
	int chargeEntity = GetEntPropEnt(charger, Prop_Send, "m_customAbility");
	if (chargeEntity > 0) {  // charger entity persists for a short while after death; check ability entity is valid
		SetEntPropFloat(chargeEntity, Prop_Send, "m_timestamp", GetGameTime() + 0.1); // keep extending end of cooldown period
	} 			
}

void Charger_OnCharge(int charger) {
	// Share the same eligible-target policy with OnChooseVictim. Do not undo
	// its choice by turning the charge back into a pinned survivor.
	int aimTarget = GetClientAimTarget(charger);
	if (!Charger_IsFreeTarget(aimTarget)
		|| IsTargetWatchingAttacker(charger, GetConVarInt(hCvarAimOffsetSensitivityCharger))) {
		int alternative = Charger_GetNearbyUnpinnedTarget(charger, aimTarget);
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

int Charger_GetNearbyUnpinnedTarget(int charger, int excluded)
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

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (survivor == excluded || !Charger_IsFreeTarget(survivor))
		{
			continue;
		}
		GetClientAbsOrigin(survivor, survivorPos);
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
