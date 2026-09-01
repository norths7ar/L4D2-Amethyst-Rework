#if defined _script_reloader_included
    #endinput
#endif
#define _script_reloader_included

/**
 * Reloads the configured VScript file, or the supplied file when non-empty.
 *
 * @return True when the logic_script entity accepted RunScriptFile.
 * @error  The script_reloader plugin is not loaded.
 */
native bool VScript_Reload(const char[] filename = "");

/**
 * Called after a requested VScript reload has completed.
 *
 * @param filename  File passed to RunScriptFile.
 * @param success   Whether the entity accepted the input.
 */
forward void VScript_OnReloaded(const char[] filename, bool success);
