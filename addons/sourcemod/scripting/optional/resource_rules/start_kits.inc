// Migrated from nosaferoomkits by Blade (0.1.1).
// The resource_rules framework profile owns activation and round-start calls.
#if defined _resource_rules_start_kits_included
	#endinput
#endif
#define _resource_rules_start_kits_included

static float g_startKitsSurvivorStart[3];

void StartKits_Init()
{
	CreateConVar("nokits_version", "0.1.1", "No Safe Room Medkits Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
}

void StartKits_RoundStart()
{
	// Find the survivor start, then remove the nearest medkit cluster.
	StartKits_FindSurvivorStart();
	StartKits_ReplaceMedkits();
}
static void StartKits_FindSurvivorStart()
{
	int iEntityCount = GetEntityCount();
	char EdictClassName[128];
	float Location[3];
	//Search entities for either a locked saferoom door,
	for (int i = 0; i <= iEntityCount; i++) {
		if (IsValidEntity(i)) {
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if ((StrContains(EdictClassName, "prop_door_rotating_checkpoint", false) != -1) && (GetEntProp(i, Prop_Send, "m_bLocked")== 1)) {
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				g_startKitsSurvivorStart = Location;
				return;
			}
		}
	}
	
	//or a survivor start point.
	for (int i = 0; i <= iEntityCount; i++) {
		if (IsValidEntity(i)) {
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			if (StrContains(EdictClassName, "info_survivor_position", false) != -1) {
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				g_startKitsSurvivorStart = Location;
				return;
			}
		}
	}
}

static void StartKits_ReplaceMedkits()
{
	int iEntityCount = GetEntityCount();
	char EdictClassName[128];
	float NearestMedkit[3], Location[3];
	
	//Look for the nearest medkit from where the survivors start,
	for (int i = 0; i <= iEntityCount; i++) {
		if (IsValidEntity(i)) {
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
			
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1) {
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				//If NearestMedkit is zero, then this must be the first medkit we found.
				
				if ((NearestMedkit[0] + NearestMedkit[1] + NearestMedkit[2]) == 0.0) {
					NearestMedkit = Location;
					continue;
				}
				
				//If this medkit is closer than the last medkit, record its location.
				if (GetVectorDistance(g_startKitsSurvivorStart, Location, false) < GetVectorDistance(g_startKitsSurvivorStart, NearestMedkit, false)) {
					NearestMedkit = Location;
				}
			}
		}
	}

	//then remove the kits
	for (int i = 0; i <= iEntityCount; i++) {
		if (IsValidEntity(i)) {
			GetEdictClassname(i, EdictClassName, sizeof(EdictClassName));
		
			if (StrContains(EdictClassName, "weapon_first_aid_kit", false) != -1) {
				GetEntPropVector(i, Prop_Send, "m_vecOrigin", Location);
				
				if (GetVectorDistance(NearestMedkit, Location, false) < 400) {
					AcceptEntityInput(i, "Kill");
				}
			}
		}
	}
}
