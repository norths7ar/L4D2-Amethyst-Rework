CoopSkill CheckWitchCrown(int witch, int attacker, int witch_dmg_array[MAXPLAYERS + DMGARRAYEXT], bool bOneShot = false)
{
	// Preserve the existing skill thresholds; per-entity HP is report-only.
	int iWitchHealth = g_WitchSkillHealth.IntValue;
	int chipDamage	 = 0;

	if (bOneShot)
		witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE] = 1;

	if (witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH] || !witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE])
	{
		PrintDebug("Witch Crown Check: Failed: bungled: %i / crowntype: %i (entity: %i)",
				   witch_dmg_array[MAXPLAYERS + WTCH_GOTSLASH],
				   witch_dmg_array[MAXPLAYERS + WTCH_CROWNTYPE],
				   witch);
		PrintDebug("Witch Crown Check: Further details: attacker: %N, attacker dmg: %i, teamless dmg: %i",
				   attacker,
				   witch_dmg_array[attacker],
				   witch_dmg_array[0]);
		return Skill_None;
	}

	PrintDebug("Witch Crown Check: crown shot: %i, harrassed: %i (full health: %i / drawthresh: %i / oneshot %i)",
			   witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT],
			   witch_dmg_array[MAXPLAYERS + WTCH_STARTLED],
			   iWitchHealth,
			   g_cvarDrawCrownThresh.IntValue,
			   bOneShot);

	// full crown? unharrassed
	if (!witch_dmg_array[MAXPLAYERS + WTCH_STARTLED] && (bOneShot || witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] >= iWitchHealth))
	{
		PrintDebug("Witch Crown Check: Full crown detected. Attacker: %N, Damage: %i, Chip Damage: %i",
				   attacker,
				   witch_dmg_array[attacker],
				   chipDamage);

		// make sure that we don't count any type of chip
		if (g_cvarHideFakeDamage.BoolValue)
		{
			chipDamage = 0;
			for (int i = 0; i <= MAXPLAYERS; i++)
			{
				if (i == attacker) { continue; }
				chipDamage += witch_dmg_array[i];
			}
			witch_dmg_array[attacker] = iWitchHealth - chipDamage;
		}
		HandleCrown(attacker, witch_dmg_array[attacker]);
        return Skill_WitchCrown;
	}
	else if (witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] >= g_cvarDrawCrownThresh.IntValue)
	{
		PrintDebug("Witch Crown Check: Draw crown detected. Attacker: %N, Crown Shot: %i, Threshold: %i",
				   attacker,
				   witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT],
				   g_cvarDrawCrownThresh.IntValue);

		// draw crown: harassed + over X damage done by one survivor -- in ONE shot

		for (int i = 0; i <= MAXPLAYERS; i++)
		{
			if (i == attacker)
				// count any damage done before final shot as chip
				chipDamage += witch_dmg_array[i] - witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT];
			else
				chipDamage += witch_dmg_array[i];
		}

		PrintDebug("Witch Crown Check: Chip Damage Calculated: %i, Total Health: %i", chipDamage, iWitchHealth);

		// make sure that we don't count any type of chip
		if (g_cvarHideFakeDamage.BoolValue)
		{
			// unlikely to happen, but if the chip was A LOT
			if (chipDamage >= iWitchHealth)
			{
				chipDamage									 = iWitchHealth - 1;
				witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] = 1;
			}
			else
				witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] = iWitchHealth - chipDamage;

			PrintDebug("Witch Crown Check: Adjusted Crown Shot: %i, Adjusted Chip Damage: %i",
					   witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT],
					   chipDamage);

			// re-check whether it qualifies as a drawcrown:
			if (witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT] < g_cvarDrawCrownThresh.IntValue)
			{
				PrintDebug("Witch Crown Check: Adjusted Crown Shot below threshold. No draw crown.");
				return Skill_None;
			}
		}

		// plus, set final shot as 'damage', and the rest as chip
		HandleDrawCrown(attacker, witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT], chipDamage);
        return Skill_WitchDraw;
	}
	else
	{
		PrintDebug("Witch Crown Check: No crown detected. Crown Shot: %i, Threshold: %i, Harassed: %i",
				   witch_dmg_array[MAXPLAYERS + WTCH_CROWNSHOT],
				   g_cvarDrawCrownThresh.IntValue,
				   witch_dmg_array[MAXPLAYERS + WTCH_STARTLED]);
	}

	return Skill_None;

}
