#include <sourcemod>
#include <sdktools>
#include <discordWebhookAPI>

#pragma newdecls required

ConVar g_cvWebhook;

public Plugin myinfo = 
{
	name = "AdminLogging",
	author = "inGame, maxime1907",
	description = "Admin logs saved to Discord",
	version = "1.2.1",
	url = "https://nide.gg"
};

public void OnPluginStart()
{
    g_cvWebhook = CreateConVar("sm_adminlogging_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);

    AutoExecConfig(true);
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
	// Get the admin ID
	AdminId adminID;

	// If this user has no admin and is NOT the server
	// let the core log this

	if(client == 0) return Plugin_Continue;
	
	if (adminID == INVALID_ADMIN_ID && client > 0)
		return Plugin_Continue;

	char sMessage[4096];
	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y @ %H:%M:%S", iTime);

	char currentMap[PLATFORM_MAX_PATH];
	GetCurrentMap(currentMap, sizeof(currentMap));

	Format(sMessage, sizeof(sMessage), "*%s (CT: %d | T: %d) - %s* ```%s```", currentMap, GetTeamScore(3), GetTeamScore(2), sTime, message);

	if(StrContains(sMessage, "\"") != -1)
		ReplaceString(sMessage, sizeof(sMessage), "\"", "");

	char szWebhookURL[1000];
	g_cvWebhook.GetString(szWebhookURL, sizeof szWebhookURL);

	Webhook webhook = new Webhook(sMessage);
	webhook.Execute(szWebhookURL, OnWebHookExecuted);
	delete webhook;

	return Plugin_Handled;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
    if (response.Status != HTTPStatus_OK)
    {
        LogError("Failed to send adminlogging webhook");
    }
}
