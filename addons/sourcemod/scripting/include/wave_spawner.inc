#if defined _wave_spawner_included
    #endinput
#endif
#define _wave_spawner_included

native bool WaveSpawner_ResetAllOverrides();
native int WaveSpawner_GetCurrentOverrideMask();

#define WAVE_FIELD_INTERVAL (1 << 0)
#define WAVE_FIELD_SIZE (1 << 1)
#define WAVE_FIELD_HUNTER (1 << 2)
#define WAVE_FIELD_SMOKER (1 << 3)
#define WAVE_FIELD_BOOMER (1 << 4)
#define WAVE_FIELD_SPITTER (1 << 5)
#define WAVE_FIELD_JOCKEY (1 << 6)
#define WAVE_FIELD_CHARGER (1 << 7)
#define WAVE_FIELD_DIRECTION (1 << 8)

public SharedPlugin __pl_wave_spawner =
{
    name = "wave_spawner",
    file = "wave_spawner.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_wave_spawner_SetNTVOptional()
{
    MarkNativeAsOptional("WaveSpawner_ResetAllOverrides");
    MarkNativeAsOptional("WaveSpawner_GetCurrentOverrideMask");
}
#endif
