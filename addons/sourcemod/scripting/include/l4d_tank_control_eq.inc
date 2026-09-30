#if defined _l4d_tank_control_eq_included
	#endinput
#endif
#define _l4d_tank_control_eq_included

/**
 * @brief Retrieves the selected tank's client index.
 *
 * @return			Client id of the selected tank, -1 if no one is selected.
 */
native int GetTankSelection();

/**
 * Prints selection to the querying player using tankcontrol_print_all and the
 * existing infected/spectator visibility and person-specific wording.
 */
native void TankControl_PrintSelection(int client);

forward void TankControl_OnTryOfferingTankBot(char sQueuedTank[64]);
forward void TankControl_OnTankSelection(char sQueuedTank[64]);

public SharedPlugin __pl_l4d_tank_control_eq =
{
	name = "l4d_tank_control_eq",
	file = "l4d_tank_control_eq.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_l4d_tank_control_eq_SetNTVOptional()
{
	MarkNativeAsOptional("GetTankSelection");
	MarkNativeAsOptional("TankControl_PrintSelection");
}
#endif
