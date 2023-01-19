#include <sourcemod>
#include <sdktools>
#include <discordWebhookAPI>

#pragma newdecls required

#define WEBHOOK_URL_MAX_SIZE	1000

ConVar g_cvWebhook, g_cvWebhookRetry;

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
	g_cvWebhookRetry = CreateConVar("sm_adminlogging_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);

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

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);
	if(!sWebhookURL[0])
	{
		LogError("[Adminlogging] No webhook found or specified.");
		return Plugin_Handled;
	}

	SendWebHook(sMessage, sWebhookURL);

	return Plugin_Continue;
}

stock void SendWebHook(char sMessage[4096], char sWebhookURL[WEBHOOK_URL_MAX_SIZE])
{
	Webhook webhook = new Webhook(sMessage);

	DataPack pack = new DataPack();
	pack.WriteString(sMessage);
	pack.WriteString(sWebhookURL);

	webhook.Execute(sWebhookURL, OnWebHookExecuted, pack);

	delete webhook;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries = 0;

	pack.Reset();

	char sMessage[4096];
	pack.ReadString(sMessage, sizeof(sMessage));

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;

	if (response.Status != HTTPStatus_OK)
	{
		if (retries < g_cvWebhookRetry.IntValue)
		{
			PrintToServer("[AdminLogging] Failed to send the webhook. Resending it .. (%d/%d)", retries, g_cvWebhookRetry.IntValue);

			SendWebHook(sMessage, sWebhookURL);
			retries++;
			return;
		}
		else
		{
			LogError("[AdminLogging] Failed to send the webhook after %d retries, aborting.", retries);
		}
	}

	retries = 0;
}
