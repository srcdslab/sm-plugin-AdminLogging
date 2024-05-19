#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <discordWebhookAPI>

#undef REQUIRE_PLUGIN
#tryinclude <AutoRecorder>
#tryinclude <ExtendedDiscord>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME "AdminLogging"
#define MAX_RAMDOM_INT 10000

ConVar g_cvWebhook, g_cvWebhookRetry, g_cvAvatar, g_cvUsername
ConVar g_cvChannelType, g_cvThreadID;

char g_sMap[PLATFORM_MAX_PATH];

bool g_Plugin_ExtDiscord = false;
bool g_Plugin_AutoRecorder = false;

public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = "inGame, maxime1907, .Rushaway",
	description = "Admin logs saved to Discord",
	version = "1.3.6",
	url = "https://github.com/srcdslab/sm-plugin-AdminLogging"
};

public void OnPluginStart()
{
	g_cvWebhook = CreateConVar("sm_adminlogging_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);
	g_cvWebhookRetry = CreateConVar("sm_adminlogging_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);
	g_cvAvatar = CreateConVar("sm_adminlogging_avatar", "https://avatars.githubusercontent.com/u/110772618?s=200&v=4", "URL to Avatar image.");
	g_cvUsername = CreateConVar("sm_adminlogging_username", "Admin Logging", "Discord username.");
	g_cvChannelType = CreateConVar("sm_adminlogging_channel_type", "0", "Type of your channel: (1 = Thread, 0 = Classic Text channel");

	/* Thread config */
	g_cvThreadID = CreateConVar("sm_adminlogging_threadid", "0", "If thread_id is provided, the message will send in that thread.", FCVAR_PROTECTED);

	AutoExecConfig(true);
}

public void OnAllPluginsLoaded()
{
	g_Plugin_AutoRecorder = LibraryExists("AutoRecorder");
	g_Plugin_ExtDiscord = LibraryExists("ExtendedDiscord");
}

public void OnLibraryAdded(const char[] sName)
{
	if (strcmp(sName, "AutoRecorder", false) == 0)
		g_Plugin_AutoRecorder = true;
	if (strcmp(sName, "ExtendedDiscord", false) == 0)
		g_Plugin_ExtDiscord = true;
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "AutoRecorder", false) == 0)
		g_Plugin_AutoRecorder = false;
	if (strcmp(sName, "ExtendedDiscord", false) == 0)
		g_Plugin_ExtDiscord = false;
}

public void OnMapInit(const char[] mapName)
{
	FormatEx(g_sMap, sizeof(g_sMap), mapName);
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
	// If this user has no admin and is NOT the server
	// let the core log this
	if(client == 0) return Plugin_Continue;

	char sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	g_cvWebhook.GetString(sWebhookURL, sizeof sWebhookURL);

	if(!sWebhookURL[0])
	{
		LogError("[%s] No webhook found or specified.", PLUGIN_NAME);
		return Plugin_Handled;
	}

	// Get the admin ID
	AdminId adminID;
	
	if (adminID == INVALID_ADMIN_ID && client > 0)
		return Plugin_Continue;

	char sMessage[WEBHOOK_MSG_MAX_SIZE];
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
			retValTime = AutoRecorder_GetDemoRecordingTime();
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

stock void SendWebHook(char sMessage[WEBHOOK_MSG_MAX_SIZE], char sWebhookURL[WEBHOOK_URL_MAX_SIZE], int iMsgIndex = -1, int iRetries = 0)
{
	/* Webhook UserName */
	char sName[128];
	g_cvUsername.GetString(sName, sizeof(sName));

	/* Webhook Avatar */
	char sAvatar[256];
	g_cvAvatar.GetString(sAvatar, sizeof(sAvatar));

	Webhook webhook = new Webhook(sMessage);

	char sThreadID[32];
	g_cvThreadID.GetString(sThreadID, sizeof sThreadID);

	bool IsThread = g_cvChannelType.BoolValue;

	if (IsThread && !sThreadID[0])
	{
		LogError("[%s] ThreadID not found or specified.", PLUGIN_NAME);
		delete webhook;
		return;
	}

	if (strlen(sName) > 0)
		webhook.SetUsername(sName);
	if (strlen(sAvatar) > 0)
		webhook.SetAvatarURL(sAvatar);

	DataPack pack = new DataPack();

	if (iMsgIndex == -1)
		iMsgIndex = GetRandomInt(1, MAX_RAMDOM_INT);

	pack.WriteCell(iMsgIndex);
	pack.WriteCell(iRetries);

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
	int retries[MAX_RAMDOM_INT + 1];

	pack.Reset();
	int iMsgIndex = pack.ReadCell();
	int iRetries = pack.ReadCell();
	retries[iMsgIndex] = iRetries;

	bool IsThreadReply = pack.ReadCell();

	char sMessage[WEBHOOK_MSG_MAX_SIZE], sWebhookURL[WEBHOOK_URL_MAX_SIZE];
	pack.ReadString(sMessage, sizeof(sMessage));
	pack.ReadString(sWebhookURL, sizeof(sWebhookURL));

	delete pack;

	if ((!IsThreadReply && response.Status != HTTPStatus_OK) || (IsThreadReply && response.Status != HTTPStatus_NoContent))
	{
		if (retries[iMsgIndex] < g_cvWebhookRetry.IntValue) {
			retries[iMsgIndex]++;
			float fTimer = 1.0 * (retries[iMsgIndex] + 1);

			DataPack Datapack = new DataPack();
			Datapack.WriteString(sMessage);
			Datapack.WriteString(sWebhookURL);
			Datapack.WriteCell(iMsgIndex);
			Datapack.WriteCell(retries[iMsgIndex]);

			CreateTimer(fTimer, Timer_ResendWebhook, Datapack);
			PrintToServer("[%s] Failed to send the webhook (ID: %d). Resending it in %0.1f seconds.. (%d/%d)", PLUGIN_NAME, iMsgIndex, fTimer, retries[iMsgIndex], g_cvWebhookRetry.IntValue);
			return;
		} else {
			if (!g_Plugin_ExtDiscord)
			{
				LogError("[%s] Failed to send the webhook after %d retries, aborting.", PLUGIN_NAME, retries[iMsgIndex]);
				LogError("[%s] Failed message : %s", PLUGIN_NAME, sMessage);
			}
		#if defined _extendeddiscord_included
			else
			{
				ExtendedDiscord_LogError("[%s] Failed to send the webhook after %d retries, aborting.", PLUGIN_NAME, retries[iMsgIndex]);
				ExtendedDiscord_LogError("[%s] Failed message : %s", PLUGIN_NAME, sMessage);
			}
		#endif
		}
	}

	retries[iMsgIndex] = 0;
}

public Action Timer_ResendWebhook(Handle timer, DataPack Datapack)
{
	char sMessage[WEBHOOK_MSG_MAX_SIZE], sWebhookURL[WEBHOOK_URL_MAX_SIZE];

	Datapack.Reset();
	Datapack.ReadString(sMessage, sizeof(sMessage));
	Datapack.ReadString(sWebhookURL, sizeof(sWebhookURL));
	int iMsgIndex = Datapack.ReadCell();
	int iRetries = Datapack.ReadCell();
	delete Datapack;

	SendWebHook(sMessage, sWebhookURL, iMsgIndex, iRetries);
	return Plugin_Stop;
}
