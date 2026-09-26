#pragma semicolon 1

enum Angle_Vector {
	Pitch = 0,
	Yaw,
	Roll
};

Handle hCvarJockeyLeapRange; // vanilla cvar

Handle hCvarHopActivationProximity; // custom cvar
// Leaps
float g_fJockeyNextLeap[MAXPLAYERS + 1];
bool bDoNormalJump[MAXPLAYERS + 1]; // used to alternate pounces and normal jumps
ConVar hCvarJockeyLeapAgain;

Handle hCvarJockeyStumbleRadius; // stumble radius of jockey ride
bool g_bJockeyRideHooked;

// Bibliography: "hunter pounce push" by "Pan XiaoHai & Marcus101RR & AtomicStryker"

public void Jockey_OnModuleStart() {
	Jockey_ResetAll();
	hCvarJockeyLeapAgain = FindConVar("z_jockey_leap_again_timer");
	// CONSOLE VARIABLES
	// jockeys will move to attack survivors within this range
	hCvarJockeyLeapRange = FindConVar("z_jockey_leap_range");
	SetConVarInt(hCvarJockeyLeapRange, 1000); 
	
	// proximity when plugin will start forcing jockeys to hop
	hCvarHopActivationProximity = CreateConVar("ai_hop_activation_proximity", "500", "How close a jockey will approach before it starts hopping");
	
	// Jockey stumble
	if (!g_bJockeyRideHooked)
	{
		HookEvent("jockey_ride", OnJockeyRide, EventHookMode_Pre);
		g_bJockeyRideHooked = true;
	}
	hCvarJockeyStumbleRadius = CreateConVar("ai_jockey_stumble_radius", "50", "Stumble radius of a jockey landing a ride");
}

public void Jockey_OnModuleEnd() {
	Jockey_ResetAll();
	ResetConVar(hCvarJockeyLeapRange);
}

/***********************************************************************************************************************************************************************************

																	HOPS: ALTERNATING LEAP AND JUMP

***********************************************************************************************************************************************************************************/

public Action Jockey_OnPlayerRunCmd(int jockey, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, bool& hasBeenShoved) {
	// Leave riding, ghost and ladder movement to the engine.
	if (GetEntProp(jockey, Prop_Send, "m_isGhost")
		|| GetEntPropEnt(jockey, Prop_Send, "m_jockeyVictim") > 0
		|| GetEntityMoveType(jockey) == MOVETYPE_LADDER) return Plugin_Continue;

	// A jump cannot be the prerequisite for releasing the shove lock: we block
	// jumps while it is held. Wait for both the existing delay and real stagger.
	if (L4D_IsPlayerStaggering(jockey)
		|| (hasBeenShoved && GetGameTime() < g_fJockeyNextLeap[jockey])) {
		buttons &= ~(IN_JUMP | IN_ATTACK);
		return Plugin_Changed;
	}
	hasBeenShoved = false;

	float jockeyPos[3];
	GetClientAbsOrigin(jockey, jockeyPos);
	int iSurvivorsProximity = GetSurvivorProximity(jockeyPos);
	bool bHasLOS = view_as<bool>(GetEntProp(jockey, Prop_Send, "m_hasVisibleThreats"));
	if (!bHasLOS || iSurvivorsProximity < 0
		|| iSurvivorsProximity >= GetConVarInt(hCvarHopActivationProximity)) return Plugin_Continue;

	if (GetEntityFlags(jockey) & FL_ONGROUND) {
		if (bDoNormalJump[jockey]) {
			buttons &= ~IN_ATTACK;
			buttons |= IN_JUMP;
			bDoNormalJump[jockey] = false;
		} else {
			int ability = GetEntPropEnt(jockey, Prop_Send, "m_customAbility");
			if (GetGameTime() >= g_fJockeyNextLeap[jockey]
				&& ability > MaxClients && IsValidEntity(ability)
				&& GetEntPropFloat(ability, Prop_Send, "m_timestamp") <= GetGameTime()) {
				buttons |= IN_ATTACK;
			}
		}
	} else {
		buttons &= ~(IN_JUMP | IN_ATTACK);
	}
	return Plugin_Changed;
}

/***********************************************************************************************************************************************************************************

																	DEACTIVATING HOP DURING SHOVES

***********************************************************************************************************************************************************************************/

void Jockey_Reset(int client) {
	g_fJockeyNextLeap[client] = 0.0;
	bDoNormalJump[client] = false;
}

void Jockey_ResetAll() {
	for (int client = 1; client <= MaxClients; client++) Jockey_Reset(client);
}

public Action Jockey_OnSpawn(int botJockey) {
	Jockey_Reset(botJockey);
	return Plugin_Handled;
}

// Keep the full configured delay after the latest shove, without stale timers
// from an earlier shove, death or client occupying the same slot.
public void Jockey_OnShoved(int botJockey) {
	float nextLeap = GetGameTime() + hCvarJockeyLeapAgain.FloatValue;
	if (nextLeap > g_fJockeyNextLeap[botJockey]) g_fJockeyNextLeap[botJockey] = nextLeap;
	bDoNormalJump[botJockey] = false;
}

void Jockey_OnLeap(int jockey) {
	g_fJockeyNextLeap[jockey] = GetGameTime() + hCvarJockeyLeapAgain.FloatValue;
	// Only advance on an actual ability use, not an attempted attack command.
	// Occasionally stay on foot instead of the usual intervening normal jump.
	bDoNormalJump[jockey] = GetRandomInt(0, 3) != 0;
}

/***********************************************************************************************************************************************************************************

																		JOCKEY STUMBLE

***********************************************************************************************************************************************************************************/

public void OnJockeyRide(Handle event, const char[] name, bool dontBroadcast) {
	if (!g_bHardSIActive) return;
	if (IsCoop()) {
		int attacker = GetClientOfUserId(GetEventInt(event, "userid"));  
		int victim = GetClientOfUserId(GetEventInt(event, "victim"));  
		if(attacker > 0 && victim > 0) {
			StumbleBystanders(victim, attacker);
		} 
	}	
}

bool IsCoop() {
	char GameName[16];
	GetConVarString(FindConVar("mp_gamemode"), GameName, sizeof(GameName));
	return (!StrEqual(GameName, "versus", false) && !StrEqual(GameName, "scavenge", false));
}

void StumbleBystanders( int pinnedSurvivor, int pinner ) {
	float pinnedSurvivorPos[3];
	float pos[3];
	float dir[3];
	GetClientAbsOrigin(pinnedSurvivor, pinnedSurvivorPos);
	int radius = GetConVarInt(hCvarJockeyStumbleRadius);
	for( int i = 1; i <= MaxClients; i++ ) {
		if( IsClientInGame(i) && IsPlayerAlive(i) && IsSurvivor(i) ) {
			if( i != pinnedSurvivor && i != pinner && !IsPinned(i) ) {
				GetClientAbsOrigin(i, pos);
				SubtractVectors(pos, pinnedSurvivorPos, dir);
				if( GetVectorLength(dir) <= float(radius) ) {
					NormalizeVector( dir, dir ); 
					L4D_StaggerPlayer( i, pinnedSurvivor, dir );
				}
			}
		} 
	}
}

stock float modulus(float a, float b) {
	while(a > b)
		a -= b;
	return a;
}
