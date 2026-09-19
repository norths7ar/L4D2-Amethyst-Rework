#if defined _skill_detect_report_included
	#endinput
#endif
#define _skill_detect_report_included

// Kill classification and reward tiers come from events.sp; chat presentation lives here.
int SkillDisplayStars(CoopSkill skill, float lifetime)
{
    // Informational stars do not imply an additional healing reward.
    if (skill == Skill_HunterTeam || skill == Skill_BoomerPop) return 1;
    return SkillRewardTier(skill, lifetime);
}

void ReportSkillKill(int actor, SkillKillRecord record)
{
    if (!g_cvarReport.BoolValue || record.skill == Skill_None) return;
    int stars = SkillDisplayStars(record.skill, record.lifetime);
    char tag[12];
    switch (stars)
    {
        case 1: strcopy(tag, sizeof(tag), "Tag+");
        case 2: strcopy(tag, sizeof(tag), "Tag++");
        case 3: strcopy(tag, sizeof(tag), "Tag+++");
    }
    switch (record.skill)
    {
        case Skill_HunterTeam:
        {
            if (g_cvarRepSkeet.BoolValue)
                CPrintToChatAll("%t %t", tag, "HunterTeamSkeet", actor, record.damage, record.shots, record.assists, record.shots == 1 ? "" : "s");
        }
        case Skill_HunterSolo, Skill_HunterMelee, Skill_HunterMagnum, Skill_HunterSniper, Skill_HunterShotgun, Skill_HunterSmg, Skill_HunterGrenade:
        {
            if (!g_cvarRepSkeet.BoolValue) return;
            switch (record.skill)
            {
                case Skill_HunterMelee: CPrintToChatAll("%t %t", tag, "HunterMeleeSkeet", actor);
                case Skill_HunterMagnum: CPrintToChatAll("%t %t", tag, "HunterMagnumHeadshot", actor);
                case Skill_HunterSniper: CPrintToChatAll("%t %t", tag, "HunterSniperHeadshot", actor);
                case Skill_HunterGrenade: CPrintToChatAll("%t %t", tag, "HunterGrenadeSkeet", actor);
                case Skill_HunterShotgun: CPrintToChatAll("%t %t", tag, "HunterShotgunSkeet", actor);
                case Skill_HunterSmg: CPrintToChatAll("%t %t", tag, "HunterSmgSkeet", actor, record.shots);
                default: CPrintToChatAll("%t %t", tag, "HunterSkeet", actor, record.shots, record.shots == 1 ? "" : "s");
            }
        }
        case Skill_ChargerFull:
        {
            if (g_cvarRepLevel.BoolValue) CPrintToChatAll("%t %t", tag, "ChargerFullLevel", actor);
        }
        case Skill_ChargerHurt:
        {
            if (g_cvarRepHurtLevel.BoolValue) CPrintToChatAll("%t %t", tag, "ChargerHurtLevel", actor, record.skillDamage);
        }
        case Skill_SmokerSelf:
        {
            if (g_cvarRepSelfClear.BoolValue) CPrintToChatAll("%t %t", tag, "SmokerKillSelfClear", actor);
        }
        case Skill_JockeySkeet: CPrintToChatAll("%t %t", tag, "JockeySkeet", actor);
        case Skill_BoomerFast:
        {
            if (g_cvarRepPop.BoolValue) CPrintToChatAll("%t %t", tag, "BoomerShutdown", actor, record.lifetime);
        }
        case Skill_BoomerPop:
        {
            if (g_cvarRepPop.BoolValue) CPrintToChatAll("%t %t", tag, "BoomerPop", actor);
        }
        case Skill_WitchCrown:
        {
            if (g_cvarRepCrow.BoolValue) CPrintToChatAll("%t %t", tag, "WitchCrown", actor);
        }
        case Skill_WitchDraw:
        {
            if (g_cvarRepDrawCrow.BoolValue) CPrintToChatAll("%t %t", tag, "WitchDrawCrown", actor);
        }
    }
}


// boomer pop
stock void HandlePop(int attacker, int victim, int shoveCount, float timeAlive)
{
    // An explosion may arrive after player_death. Use the actual kill time,
    // not the explosion callback time, for both classification and stars.
    int index = g_PendingKill[victim];
    if (index >= 0 && index < g_KillRecords.Length)
    {
        SkillKillRecord record;
        g_KillRecords.GetArray(index, record);
        timeAlive = record.lifetime;
    }
    RecordSkill(attacker, victim, timeAlive <= 2.0 ? Skill_BoomerFast : Skill_BoomerPop);

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
    RecordSkill(attacker, victim, Skill_ChargerHurt, damage);

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
		if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Tag+", "HunterDeadstop", attacker);
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
		if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Tag+", "InfectedShove", attacker);
	}

	Call_StartForward(g_hForwardSIShove);
	Call_PushCell(attacker);
	Call_PushCell(victim);
	Call_PushCell(zombieClass);
	Call_Finish();
}

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
		if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Tag+++", "SmokerTongueCut", attacker);
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
	if (withShove && g_cvarReport.BoolValue && g_cvarRepSelfClear.BoolValue && g_cvarRepSelfClearShove.BoolValue)
	{
		if (IsValidClientInGame(attacker))
			CPrintToChatAll("%t %t", "Tag++", "SmokerShoveSelfClear", attacker);
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

		CPrintToChatAll("%t %t", "Tag+", "TankRockSkeet", attacker);
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
			CPrintToChatAll("%t %t", "Tag++", "HunterHighPounce", attacker, RoundFloat(calculatedDamage), RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Tag++", "HunterHighPounceAI", RoundFloat(calculatedDamage), RoundFloat(height));
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
			CPrintToChatAll("%t %t", "Tag+++", "JockeyHighPounce", attacker, RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Tag+++", "JockeyHighPounceAI", RoundFloat(height));
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
			CPrintToChatAll("%t %t", "Tag++++", "ChargerDeathCharge", attacker, (bCarried) ? "Empty" : "Bowling", RoundFloat(height));
		else if (IsValidClientInGame(victim))
			CPrintToChatAll("%t %t", "Tag++++", "ChargerDeathChargeAI", (bCarried) ? "Empty" : "Bowling", RoundFloat(height));
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
			if (IsValidClientInGame(attacker))
			{
				if (IsValidClientInGame(pinVictim))
					CPrintToChatAll("%t %t", "Tag+", "InfectedClear", attacker, pinVictim, g_csSIClassName[zombieClass], fClearTime);
				else
					CPrintToChatAll("%t %t", "Tag+", "InfectedClearTeammate", attacker, g_csSIClassName[zombieClass], fClearTime);
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
		CPrintToChat(survivor, "%t %t", "Tag+", "BunnyHop", streak, (streak > 1) ? "PluralCount" : "Empty", maxVelocity);

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
			CPrintToChatAll("%t %t", "Tag+", "AlarmHit", survivor);
		else if (reason == CALARM_TOUCHED)
		{
			// if a survivor touches an alarmed car, it might be due to a special infected...
			if (IsValidInfected(infected))
			{
				int zombieClass = GetEntProp(infected, Prop_Send, "m_zombieClass");
				if (!IsFakeClient(infected))
					CPrintToChatAll("%t %t", "Tag+", "AlarmInfectedPlayer", infected, g_csSIClassName[zombieClass]);
				else
					CPrintToChatAll("%t %t", "Tag+", "AlarmInfectedAI", g_csSIClassName[zombieClass]);
			}
			else
				CPrintToChatAll("%t %t", "Tag+", "AlarmTouch", survivor);
		}
		else if (reason == CALARM_EXPLOSION)
			CPrintToChatAll("%t %t", "Tag+", "AlarmExplosion", survivor);
		else if (reason == CALARM_BOOMER)
		{
			CPrintToChatAll("%t %t", "Tag+", "AlarmBoomerKill", survivor);
		}
		else
			CPrintToChatAll("%t %t", "Tag+", "AlarmTriggered", survivor);
	}

	Call_StartForward(g_hForwardAlarmTriggered);
	Call_PushCell(survivor);
	Call_PushCell(infected);
	Call_PushCell(reason);
	Call_Finish();
}
