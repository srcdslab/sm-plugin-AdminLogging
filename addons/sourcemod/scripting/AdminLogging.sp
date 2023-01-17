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
	if(!szWebhookURL[0])
	{
		LogError("[Adminlogging] No webhook found or specified.");
		return Plugin_Handled;
	}
	
	Webhook webhook = new Webhook(sMessage);
	
	DataPack pack = new DataPack();
	pack.WriteCell(view_as<int>(webhook));
	pack.WriteString(szWebhookURL);
	
	webhook.Execute(szWebhookURL, OnWebHookExecuted, pack);

	return Plugin_Handled;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries;
	
	pack.Reset();
	Webhook hook = view_as<Webhook>(pack.ReadCell());

	if (response.Status != HTTPStatus_OK)
	{
		if(retries < 3)
			PrintToServer("[AdminLogging] Failed to send the webhook. Resending it .. (%d/3)", retries);
		
		else if(retries >= 3)
		{
			LogError("[AdminLogging] Could not send the webhook after %d retries.", retries);
			delete hook;
			delete pack;
			return;
		}
		
		char webhookURL[PLATFORM_MAX_PATH];
		pack.ReadString(webhookURL, sizeof(webhookURL));
		
		DataPack newPack;
		newPack.WriteCell(view_as<int>(hook));
		newPack.WriteString(webhookURL);
		CreateDataTimer(0.5, ExecuteWebhook_Timer, newPack);
		delete pack;
		retries++;
		return;
	}
	
	delete pack;
	delete hook;
	retries = 0;
}

Action ExecuteWebhook_Timer(Handle timer, DataPack pack)
{
	pack.Reset();
	Webhook hook = view_as<Webhook>(pack.ReadCell());
	
	char webhookURL[PLATFORM_MAX_PATH];
	pack.ReadString(webhookURL, sizeof(webhookURL));
	
	DataPack newPack = new DataPack();
	newPack.WriteCell(view_as<int>(hook));
	newPack.WriteString(webhookURL);	
	hook.Execute(webhookURL, OnWebHookExecuted, newPack);
	return Plugin_Continue;
}
