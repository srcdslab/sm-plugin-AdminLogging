#include <sourcemod>
#include <sdktools>
#include <discordWebhookAPI>

#pragma newdecls required

#undef REQUIRE_PLUGIN
#tryinclude <AutoRecorder>
#define REQUIRE_PLUGIN

#define WEBHOOK_URL_MAX_SIZE	1000

ConVar g_cvWebhook, g_cvWebhookRetry;
ConVar g_cvChannelType, g_cvThreadID;

char g_sMap[PLATFORM_MAX_PATH];

bool g_Plugin_AutoRecorder = false;

public Plugin myinfo = 
{
	name = "AdminLogging",
	author = "inGame, maxime1907, .Rushaway",
	description = "Admin logs saved to Discord",
	version = "1.3",
	url = "https://nide.gg"
};

public void OnPluginStart()
{
	g_cvWebhook = CreateConVar("sm_adminlogging_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);
	g_cvWebhookRetry = CreateConVar("sm_adminlogging_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);
	g_cvChannelType = CreateConVar("sm_adminlogging_channel_type", "0", "Type of your channel: (1 = Thread, 0 = Classic Text channel");

	/* Thread config */
	g_cvThreadID = CreateConVar("sm_adminlogging_threadid", "0", "If thread_id is provided, the message will send in that thread.", FCVAR_PROTECTED);

	AutoExecConfig(true);
}

public void OnAllPluginsLoaded()
{
	g_Plugin_AutoRecorder = LibraryExists("AutoRecorder");
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "AutoRecorder", false) == 0)
		g_Plugin_AutoRecorder = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "AutoRecorder", false) == 0)
		g_Plugin_AutoRecorder = false;
}

public void OnMapStart()
{
	GetCurrentMap(g_sMap, sizeof(g_sMap));
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);

	if(!sWebhookURL[0])
	{
		LogError("[Adminlogging] No webhook found or specified.");
		return Plugin_Handled;
	}

	// If this user has no admin and is NOT the server
	// let the core log this
	if(client == 0) return Plugin_Continue;

	// Get the admin ID
	AdminId adminID;
	
	if (adminID == INVALID_ADMIN_ID && client > 0)
		return Plugin_Continue;

	char sMessage[4096];
	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y @ %H:%M:%S", iTime);

	if (g_Plugin_AutoRecorder)
	{
		char sDate[32];
		int iCount = -1;
		int iTick = -1;
		int retValTime = -1;
		#if defined _autorecorder_included
		if (AutoRecorder_IsDemoRecording())
		{
			iCount = AutoRecorder_GetDemoRecordCount();
			iTick = AutoRecorder_GetDemoRecordingTick();
			retValTime = AutoRecorder_GetDemoRecordingTime()
		}
		if (retValTime == -1)
			sDate = "N/A";
		else
			FormatTime(sDate, sizeof(sDate), "%d.%m.%Y @ %H:%M", retValTime);
		#endif
		Format(sMessage, sizeof(sMessage), "%s *(CT: %d | T: %d) - %s* - Demo: %d @ Tick: ≈ %d *(Started %s)* ```%s```",
			g_sMap, GetTeamScore(3), GetTeamScore(2), sTime, iCount, iTick, sDate, message);
	}
	else
	{
		Format(sMessage, sizeof(sMessage), "%s *(CT: %d | T: %d) - %s* ```%s```", g_sMap, GetTeamScore(3), GetTeamScore(2), sTime, message);
	}

	if(StrContains(sMessage, "\"") != -1)
		ReplaceString(sMessage, sizeof(sMessage), "\"", "");

	SendWebHook(sMessage, sWebhookURL);

	return Plugin_Continue;
}

stock void SendWebHook(char sMessage[4096], char sWebhookURL[WEBHOOK_URL_MAX_SIZE])
{
	Webhook webhook = new Webhook(sMessage);

	char sThreadID[32];
	g_cvThreadID.GetString(sThreadID, sizeof sThreadID);

	bool IsThread = g_cvChannelType.BoolValue;

	if (IsThread && !sThreadID[0])
	{
		LogError("[Admin-Logging] ThreadID not found or specified.");
		delete webhook;
		return;
	}

	DataPack pack = new DataPack();

	if (IsThread && strlen(sThreadID) > 0)
		pack.WriteCell(1);
	else
		pack.WriteCell(0);

	pack.WriteString(sMessage);
	pack.WriteString(sWebhookURL);

	webhook.Execute(sWebhookURL, OnWebHookExecuted, pack, sThreadID);
	delete webhook;
}

public void OnWebHookExecuted(HTTPResponse response, DataPack pack)
{
	static int retries = 0;
	pack.Reset();

	bool IsThreadReply = pack.ReadCell();

	char sMessage[4096], sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sMessage, sizeof(sMessage));
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;

	if (!IsThreadReply && response.Status != HTTPStatus_OK)
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
			LogError("[AdminLogging] Failed message : %s", sMessage);
			return;
		}
	}

	if (IsThreadReply && response.Status != HTTPStatus_NoContent)
	{
		if (retries < g_cvWebhookRetry.IntValue)
		{
			PrintToServer("[AdminLogging] Failed to send the webhook. Resending it .. (%d/%d)", retries + 1, g_cvWebhookRetry.IntValue);
			SendWebHook(sMessage, sWebhookURL);
			retries++;
			return;
		}
		else
		{
			LogError("[AdminLogging] Failed to send the webhook after %d retries, aborting. (Message: %s)", retries, sMessage);
			return;
		}
	}

	retries = 0;
}
