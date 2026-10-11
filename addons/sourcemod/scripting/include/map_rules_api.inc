#if defined _map_rules_api_included
 #endinput
#endif
#define _map_rules_api_included

// Feature-owned interfaces for the admin_tools menu. saved=true means the
// configured next-round value; false means this round's effective value.
native bool BossRules_GetStatic(bool witch, bool saved = false);
native bool BossRules_SetStatic(bool witch, bool enabled);
native bool FinaleRules_CanEdit();
native bool FinaleRules_GetRound(int slot, bool saved = false);
native bool FinaleRules_SetRound(int slot, bool allowed);
native bool SkipIntro_GetAlways(bool saved = false);
native bool SkipIntro_SetAlways(bool enabled);
native bool SkipIntro_IsOfficialForced();

stock void MapRules_MarkAPIsOptional()
{
	MarkNativeAsOptional("BossRules_GetStatic");
	MarkNativeAsOptional("BossRules_SetStatic");
	MarkNativeAsOptional("FinaleRules_CanEdit");
	MarkNativeAsOptional("FinaleRules_GetRound");
	MarkNativeAsOptional("FinaleRules_SetRound");
	MarkNativeAsOptional("SkipIntro_GetAlways");
	MarkNativeAsOptional("SkipIntro_SetAlways");
	MarkNativeAsOptional("SkipIntro_IsOfficialForced");
}
