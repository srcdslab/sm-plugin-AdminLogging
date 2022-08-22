#include <sourcemod>
#include <sourcecomms>
#include <sdktools>
#include <Discord>

#define PLUGIN_VERSION "1.1"

#pragma newdecls required

public Plugin myinfo = 
{
	name = "AdminLogging",
	author = "inGame, maxime1907",
	description = "Admin logs saved to Discord",
	version = PLUGIN_VERSION,
	url = "https://nide.gg"
};

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
	// Get the admin ID
	AdminId adminID;

	// If this user has no admin and is NOT the server
	// let the core log this

	if(client == 0) return Plugin_Continue;
	
	if (adminID == INVALID_ADMIN_ID && client > 0)
		return Plugin_Continue;

	char sWebhook[64];
	Format(sWebhook, sizeof(sWebhook), "adminlogs");

	char sMessage[4096];
	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y @ %H:%M:%S", iTime);

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	Format(sMessage, sizeof(sMessage), "*%s (CT: %d | T: %d) - %s* ```%s```", currentMap, GetTeamScore(3), GetTeamScore(2), sTime, message);

	if(StrContains(sMessage, "\"") != -1)
		ReplaceString(sMessage, sizeof(sMessage), "\"", "");

	Discord_SendMessage(sWebhook, sMessage);

	return Plugin_Handled;
}
