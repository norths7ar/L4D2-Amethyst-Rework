#pragma semicolon 1

public void Spitter_OnModuleStart() {
}

public void Spitter_OnModuleEnd() {
}

// Prefer acid under an actively pinned survivor. The class values deliberately
// match the requested order: Charger, Hunter, Smoker, then Jockey.
int Spitter_GetPinnedTarget(int spitter)
{
	static const int priorities[] = {
		L4D2Infected_Charger,
		L4D2Infected_Hunter,
		L4D2Infected_Smoker,
		L4D2Infected_Jockey
	};

	for (int priority = 0; priority < sizeof(priorities); priority++)
	{
		int closest = -1;
		float origin[3], target[3];
		GetClientAbsOrigin(spitter, origin);
		float distanceLimit = FindConVar("z_spit_range").FloatValue;
		for (int survivor = 1; survivor <= MaxClients; survivor++)
		{
			if (!IsSurvivor(survivor) || !IsPlayerAlive(survivor))
			{
				continue;
			}

			int attacker = Spitter_GetPinningAttacker(survivor, priorities[priority]);
			if (attacker > 0 && IsClientInGame(attacker) && IsPlayerAlive(attacker)
				&& GetClientTeam(attacker) == L4D2Team_Infected
				&& GetInfectedClass(attacker) == priorities[priority])
			{
				GetClientAbsOrigin(survivor, target);
				float distance = GetVectorDistance(origin, target);
				if (distance <= distanceLimit && isVisibleTo(spitter, survivor))
				{
					closest = survivor;
					distanceLimit = distance;
				}
			}
		}
		if (closest > 0) return closest;
	}

	return -1;
}

int Spitter_GetPinningAttacker(int survivor, int zombieClass)
{
	switch (zombieClass)
	{
		case L4D2Infected_Charger: return GetEntPropEnt(survivor, Prop_Send, "m_pummelAttacker"); // not carry
		case L4D2Infected_Hunter: return GetEntPropEnt(survivor, Prop_Send, "m_pounceAttacker");
		case L4D2Infected_Smoker: return GetEntPropEnt(survivor, Prop_Send, "m_tongueOwner");
		case L4D2Infected_Jockey: return GetEntPropEnt(survivor, Prop_Send, "m_jockeyAttacker");
	}
	return -1;
}
