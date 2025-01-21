#if defined _adminlogging_included
 #endinput
#endif
#define _adminlogging_included

/**
 * Called when AdminLogging plugin becomes available
 *
 * @noreturn
 */
forward void AdminLogging_OnPluginOK();

/**
 * Called when AdminLogging plugin becomes unavailable
 *
 * @noreturn
 */
forward void AdminLogging_OnPluginNotOK();

public SharedPlugin __pl_adminlogging = 
{
	name = "AdminLogging",
	file = "AdminLogging.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};