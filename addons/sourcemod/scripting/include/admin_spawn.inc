#if defined _admin_spawn_included
    #endinput
#endif
#define _admin_spawn_included

// Source information owned by the administrator generation component.
// Active only inside its synchronous spawn command, never across frames.
native bool AdminSpawn_IsActive();
// Marks this client's current life, not a reusable client slot.
native bool AdminSpawn_IsInfected(int client);

public SharedPlugin __pl_admin_spawn =
{
    name = "admin_spawn",
    file = "all4dead2.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_admin_spawn_SetNTVOptional()
{
    MarkNativeAsOptional("AdminSpawn_IsActive");
    MarkNativeAsOptional("AdminSpawn_IsInfected");
}
#endif
