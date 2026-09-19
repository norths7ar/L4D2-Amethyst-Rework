#if defined _resource_rules_included
 #endinput
#endif
#define _resource_rules_included

enum ResourceGroup
{
	ResourceGroup_Grenade,
	ResourceGroup_Fire,
	ResourceGroup_Explosive,
	ResourceGroup_Count
};

native bool ResourceRules_IsAllowed(ResourceGroup group);
native void ResourceRules_SetAllowed(ResourceGroup group, bool allowed);

// Emitted by campaign_switcher only for a new campaign, not a chapter change.
forward void CampaignSwitcher_OnNewCampaign();

public SharedPlugin __pl_resource_rules =
{
	name = "resource_rules",
	file = "resource_rules.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_resource_rules_SetNTVOptional()
{
	MarkNativeAsOptional("ResourceRules_IsAllowed");
	MarkNativeAsOptional("ResourceRules_SetAllowed");
}
#endif
