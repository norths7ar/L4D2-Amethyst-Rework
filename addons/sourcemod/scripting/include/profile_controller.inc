#if defined _profile_controller_included
    #endinput
#endif
#define _profile_controller_included

native int ProfileController_GetCurrentProfile();
native bool ProfileController_Reapply();

public SharedPlugin __pl_profile_controller =
{
    name = "profile_controller",
    file = "profile_controller.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_profile_controller_SetNTVOptional()
{
    MarkNativeAsOptional("ProfileController_GetCurrentProfile");
    MarkNativeAsOptional("ProfileController_Reapply");
}
#endif
