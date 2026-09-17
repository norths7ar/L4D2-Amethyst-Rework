#if defined _skill_detect_report_included
	#endinput
#endif
#define _skill_detect_report_included

// boomer pop
stock void HandlePop(int attacker, int victim, int shoveCount, float timeAlive)
{
    if (timeAlive <= 2.0) RecordSkill(attacker, victim, Skill_BoomerFast);

	Call_StartForward(g_hForwardBoomerPop);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(shoveCount);
	Call_PushFloat(timeAlive);
	Call_Finish();
}

// charger level
stock void HandleLevel(int attacker, int victim)
{
    RecordSkill(attacker, victim, Skill_ChargerFull);

	Call_StartForward(g_hForwardLevel);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish();
}
// charger level hurt
stock void HandleLevelHurt(int attacker, int victim, int damage)
{
    RecordSkill(attacker, victim, Skill_ChargerHurt);

	Call_StartForward(g_hForwardLevelHurt);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(damage);
	Call_Finish();
}

// deadstops
stock void HandleDeadstop(int attacker, int victim)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepDeadStop.BoolValue)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(victim))
			CPrintToChatAll("%t %t", "Info", "Deadstopped", attacker, victim);
		else if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Info", "DeadstoppedBot", attacker);
	}

	Call_StartForward(g_hForwardHunterDeadstop);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish();
}

stock void HandleShove(int attacker, int victim, int zombieClass)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepShove.BoolValue)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(victim))
			CPrintToChatAll("%t %t", "Info", "Shoved", attacker, victim);
		else if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Info", "ShovedBot", attacker);
	}

	Call_StartForward(g_hForwardSIShove);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(zombieClass);
	Call_Finish();
}

// real skeet


// hurt skeet / non-skeet
//  NOTE: bSniper not set yet, do this


// crown
void HandleCrown(int attacker, int damage)
{


	Call_StartForward(g_hForwardCrown);
	Call_PushCell(attacker);
	Call_PushCell(damage);
	Call_Finish();
}
// drawcrown
void HandleDrawCrown(int attacker, int damage, int chipdamage)
{


	Call_StartForward(g_hForwardDrawCrown);
	Call_PushCell(attacker);
	Call_PushCell(damage);
	Call_PushCell(chipdamage);
	Call_Finish();
}

// smoker clears
void HandleTongueCut(int attacker, int victim)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepTongueCut.BoolValue)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(victim))
			CPrintToChatAll("%t %t", "Info", "CutTongue", attacker, victim);
		else if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Info", "CutTongueBot", attacker);
	}

	// call forward
	Call_StartForward(g_hForwardTongueCut);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish();
}

void HandleSmokerSelfClear(int attacker, int victim, bool withShove = false)
{
    if (!withShove) RecordSkill(attacker, victim, Skill_SmokerSelf);
	// report?
	if (withShove && g_cvarReport.BoolValue && g_cvarRepSelfClear.BoolValue && (!withShove || g_cvarRepSelfClearShove.BoolValue))
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(victim))
			CPrintToChatAll("%t %t", "Info", "SelfClearedTongue", attacker, victim, (withShove) ? "Shoving" : "Empty");
		else if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Info", "SelfClearedTongueBot", attacker, (withShove) ? "Shoving" : "Empty");
	}

	// call forward
	Call_StartForward(g_hForwardSmokerSelfClear);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(withShove);
	Call_Finish();
}

// rocks
void HandleRockEaten(int attacker, int victim)
{
	Call_StartForward(g_hForwardRockEaten);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish();
}
void HandleRockSkeeted(int attacker, int victim)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepRockSkeet.BoolValue)
	{
		if (!IsValidClientInGame(attacker))
			return;

		if (g_cvarRepRockName.BoolValue && IsValidClientInGame(victim) && !IsFakeClient(victim))
			CPrintToChatAll("%t %t", "Info", "SkeetedRock", attacker, victim);
		else
			CPrintToChatAll("%t %t", "Info", "SkeetedRockBot", attacker);
	}

	Call_StartForward(g_hForwardRockSkeeted);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_Finish();
}

// highpounces
stock void HandleHunterDP(int attacker, int victim, int actualDamage, float calculatedDamage, float height, bool playerIncapped = false)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepHunterDP.BoolValue && height >= g_cvarHunterDPThresh.FloatValue && !playerIncapped)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(attacker))
			CPrintToChatAll("%t %t", "Info", "HunterHP", attacker, victim, RoundFloat(calculatedDamage), RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Info", "HunterHPBot", victim, RoundFloat(calculatedDamage), RoundFloat(height));
	}

	Call_StartForward(g_hForwardHunterDP);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(actualDamage);
	Call_PushFloat(calculatedDamage);
	Call_PushFloat(height);
	Call_PushCell((height >= g_cvarHunterDPThresh.FloatValue) ? 1 : 0);
	Call_PushCell((playerIncapped) ? 1 : 0);
	Call_Finish();
}
stock void HandleJockeyDP(int attacker, int victim, float height)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepJockeyDP.BoolValue && height >= g_cvarJockeyDPThresh.FloatValue)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(attacker))
			CPrintToChatAll("%t %t", "Info", "JockeyHP", attacker, victim, RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Info", "JockeyHPBot", victim, RoundFloat(height));
	}

	Call_StartForward(g_hForwardJockeyDP);
	Call_PushCell(victim);
	Call_PushCell(attacker);
	Call_PushFloat(height);
	Call_PushCell((height >= g_cvarJockeyDPThresh.FloatValue) ? 1 : 0);
	Call_Finish();
}

// deathcharges
stock void HandleDeathCharge(int attacker, int victim, float height, float distance, bool bCarried = true)
{
	// report?
	if (g_cvarReport.BoolValue && g_cvarRepDeathCharge.BoolValue && height >= g_cvarDeathChargeHeight.FloatValue)
	{
		if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(attacker))
			CPrintToChatAll("%t %t", "Info", "DeathCharged", attacker, victim, (bCarried) ? "Empty" : "Bowling", RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Info", "DeathChargedBot", victim, (bCarried) ? "Empty" : "Bowling", RoundFloat(height));
	}

	Call_StartForward(g_hForwardDeathCharge);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushFloat(height);
	Call_PushFloat(distance);
	Call_PushCell((bCarried) ? 1 : 0);
	Call_Finish();
}

// SI clears    (cleartimeA = pummel/pounce/ride/choke, cleartimeB = tongue drag, charger carry)
stock void HandleClear(int attacker, int victim, int pinVictim, int zombieClass, float clearTimeA, float clearTimeB, bool bWithShove = false)
{
	// sanity check:
	if (clearTimeA < 0 && clearTimeA != -1.0)
		clearTimeA = 0.0;

	if (clearTimeB < 0 && clearTimeB != -1.0)
		clearTimeB = 0.0;

	PrintDebug("Clear: %i freed %i from %i: time: %.2f / %.2f -- class: %s (with shove? %i)", attacker, pinVictim, victim, clearTimeA, clearTimeB, g_csSIClassName[zombieClass], bWithShove);

	if (g_cvarRepInstanClear.IntValue && attacker != pinVictim)
	{
		float fMinTime	 = g_cvarInstaTime.FloatValue;
		float fClearTime = clearTimeA;
		if (zombieClass == ZC_CHARGER || zombieClass == ZC_SMOKER) { fClearTime = clearTimeB; }

		if (fClearTime != -1.0 && fClearTime <= fMinTime)
		{
			if (IsValidClientInGame(attacker) && IsValidClientInGame(victim) && !IsFakeClient(victim))
			{
				if (IsValidClientInGame(pinVictim))
					CPrintToChatAll("%t %t", "Info", "SIClear", attacker, pinVictim, victim, g_csSIClassName[zombieClass], fClearTime);
				else
					CPrintToChatAll("%t %t", "Info", "SIClearTeammate", attacker, victim, g_csSIClassName[zombieClass], fClearTime);
			}
			else if (IsValidClientInGame(attacker))
			{
				if (IsValidClientInGame(pinVictim))
					CPrintToChatAll("%t %t", "Info", "SIClearBot", attacker, pinVictim, g_csSIClassName[zombieClass], fClearTime);
				else
					CPrintToChatAll("%t %t", "Info", "SIClearTeammateBot", attacker, g_csSIClassName[zombieClass], fClearTime);
			}
		}
	}

	Call_StartForward(g_hForwardClear);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(pinVictim);
	Call_PushCell(zombieClass);
	Call_PushFloat(clearTimeA);
	Call_PushFloat(clearTimeB);
	Call_PushCell((bWithShove) ? 1 : 0);
	Call_Finish();
}

// booms
stock void HandleVomitLanded(int attacker, int boomCount)
{
	Call_StartForward(g_hForwardVomitLanded);
	Call_PushCell(attacker);
	Call_PushCell(boomCount);
	Call_Finish();
}

// bhaps
stock void HandleBHopStreak(int survivor, int streak, float maxVelocity)
{
	if (g_cvarRepBhopStreak.BoolValue && IsValidClientInGame(survivor) && !IsFakeClient(survivor) && streak >= g_cvarBHopMinStreak.IntValue)
		CPrintToChat(survivor, "%t %t", "Info", "BunnyHop", streak, (streak > 1) ? "PluralCount" : "Empty", maxVelocity);

	Call_StartForward(g_hForwardBHopStreak);
	Call_PushCell(survivor);
	Call_PushCell(streak);
	Call_PushFloat(maxVelocity);
	Call_Finish();
}

// car alarms
stock void HandleCarAlarmTriggered(int survivor, int infected, int reason)
{
	if (g_cvarRepCarAlarm.BoolValue && IsValidClientInGame(survivor) && !IsFakeClient(survivor))
	{
		if (reason == CALARM_HIT)
			CPrintToChatAll("%t %t", "Info", "CalarmHit", survivor);
		else if (reason == CALARM_TOUCHED)
		{
			// if a survivor touches an alarmed car, it might be due to a special infected...
			if (IsValidInfected(infected))
			{
				if (!IsFakeClient(infected))
					CPrintToChatAll("%t %t", "Info", "CalarmTouched", infected, survivor);
				else
				{
					switch (GetEntProp(infected, Prop_Send, "m_zombieClass"))
					{
						case ZC_SMOKER:
							CPrintToChatAll("%t %t", "Info", "CalarmTouchedHunter", survivor);
						case ZC_JOCKEY:
							CPrintToChatAll("%t %t", "Info", "CalarmTouchedJockey", survivor);
						case ZC_CHARGER:
							CPrintToChatAll("%t %t", "Info", "CalarmTouchedCharger", survivor);
						default:
							CPrintToChatAll("%t %t", "Info", "CalarmTouchedInfected", survivor);
					}
				}
			}
			else
				CPrintToChatAll("%t %t", "Info", "CalarmTouchedBot", survivor);
		}
		else if (reason == CALARM_EXPLOSION)
			CPrintToChatAll("%t %t", "Info", "CalarmExplosion", survivor);
		else if (reason == CALARM_BOOMER)
		{
			if (IsValidInfected(infected) && !IsFakeClient(infected))
				CPrintToChatAll("%t %t", "Info", "CalarmBoomer", survivor, infected);
			else
				CPrintToChatAll("%t %t", "Info", "CalarmBoomerBot", survivor);
		}
		else
			CPrintToChatAll("%t %t", "Info", "Calarm", survivor);
	}

	Call_StartForward(g_hForwardAlarmTriggered);
	Call_PushCell(survivor);
	Call_PushCell(infected);
	Call_PushCell(reason);
	Call_Finish();
}
