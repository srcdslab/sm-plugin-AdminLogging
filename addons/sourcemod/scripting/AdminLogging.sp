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
#define DISCORD_MAX_CONTENT 2000
#define DISCORD_CODEBLOCK_PREFIX "```txt\n"
#define DISCORD_CODEBLOCK_SUFFIX "\n```"
#define ADMINLOGGING_BUFFER_SIZE 4096

ConVar g_cvWebhook, g_cvWebhookRetry, g_cvAvatar, g_cvUsername
ConVar g_cvChannelType, g_cvThreadID;

ArrayList g_hSendQueue = null;

char g_sMap[PLATFORM_MAX_PATH];
char g_sWebhookURL[WEBHOOK_URL_MAX_SIZE];
bool g_bQueueSending = false;

bool g_bLate = false;
bool g_Plugin_ExtDiscord = false;
bool g_Plugin_AutoRecorder = false;
bool g_bNative_IsDemoRecording = false;
bool g_bNative_GetDemoRecordCount = false;
bool g_bNative_GetDemoRecordingTick = false;
bool g_bNative_GetDemoRecordingTime = false;
bool g_bNative_ExtendedDiscord_LogError = false;

public Plugin myinfo = 
{
	name = PLUGIN_NAME,
	author = "inGame, maxime1907, .Rushaway",
	description = "Admin logs saved to Discord",
	version = "1.4.1",
	url = "https://github.com/srcdslab/sm-plugin-AdminLogging"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvWebhook = CreateConVar("sm_adminlogging_webhook", "", "The webhook URL of your Discord channel.", FCVAR_PROTECTED);
	g_cvWebhookRetry = CreateConVar("sm_adminlogging_webhook_retry", "3", "Number of retries if webhook fails.", FCVAR_PROTECTED);
	g_cvAvatar = CreateConVar("sm_adminlogging_avatar", "https://avatars.githubusercontent.com/u/110772618?s=200&v=4", "URL to Avatar image.");
	g_cvUsername = CreateConVar("sm_adminlogging_username", "Admin Logging", "Discord username.");
	g_cvChannelType = CreateConVar("sm_adminlogging_channel_type", "0", "Type of your channel: (1 = Thread, 0 = Classic Text channel");

	/* Thread config */
	g_cvThreadID = CreateConVar("sm_adminlogging_threadid", "0", "If thread_id is provided, the message will send in that thread.", FCVAR_PROTECTED);

	delete g_hSendQueue;
	g_hSendQueue = new ArrayList(ByteCountToCells(DISCORD_MAX_CONTENT + 1));

	AutoExecConfig(true);

	g_cvWebhook.AddChangeHook(OnWebhookConVarChanged);
	g_cvWebhook.GetString(g_sWebhookURL, sizeof(g_sWebhookURL));

	if (g_bLate)
		GetCurrentMap(g_sMap, sizeof(g_sMap));
}

public void OnWebhookConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sWebhookURL, sizeof(g_sWebhookURL), newValue);
}

public void OnPluginEnd()
{
	g_bQueueSending = false;
	delete g_hSendQueue;
}

public void OnAllPluginsLoaded()
{
	g_Plugin_AutoRecorder = LibraryExists("AutoRecorder");
	g_Plugin_ExtDiscord = LibraryExists("ExtendedDiscord");

	VerifyNatives();
}

public void OnLibraryAdded(const char[] sName)
{
	HandleLibraryChange(sName, true);
}

public void OnLibraryRemoved(const char[] sName)
{
	HandleLibraryChange(sName, false);
}

void HandleLibraryChange(const char[] name, bool isAdded = false)
{
	if (strcmp(name, "AutoRecorder", false) == 0)
	{
		g_Plugin_AutoRecorder = isAdded;
		VerifyNative_AutoRecorder();
	}
	else if (strcmp(name, "ExtendedDiscord", false) == 0)
	{
		g_Plugin_ExtDiscord = isAdded;
		VerifyNative_ExtendedDiscord();
	}
}

stock void VerifyNatives()
{
	VerifyNative_AutoRecorder();
	VerifyNative_ExtendedDiscord();
}

stock void VerifyNative_AutoRecorder()
{
	g_bNative_GetDemoRecordCount = g_Plugin_AutoRecorder && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordCount") == FeatureStatus_Available;
	g_bNative_IsDemoRecording = g_Plugin_AutoRecorder && GetFeatureStatus(FeatureType_Native, "AutoRecorder_IsDemoRecording") == FeatureStatus_Available;
	g_bNative_GetDemoRecordingTick = g_Plugin_AutoRecorder && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordingTick") == FeatureStatus_Available;
	g_bNative_GetDemoRecordingTime = g_Plugin_AutoRecorder && GetFeatureStatus(FeatureType_Native, "AutoRecorder_GetDemoRecordingTime") == FeatureStatus_Available;
}

stock void VerifyNative_ExtendedDiscord()
{
	g_bNative_ExtendedDiscord_LogError = g_Plugin_ExtDiscord && GetFeatureStatus(FeatureType_Native, "ExtendedDiscord_LogError") == FeatureStatus_Available;
}

public void OnMapInit(const char[] mapName)
{
	FormatEx(g_sMap, sizeof(g_sMap), mapName);
}

void QueueOutgoingMessage(const char[] message)
{
	if (g_hSendQueue == null || !message[0])
		return;

	g_hSendQueue.PushString(message);
}

void SendNextQueuedMessage()
{
	if (!g_bQueueSending || g_hSendQueue == null)
		return;

	if (g_hSendQueue.Length <= 0)
	{
		g_bQueueSending = false;
		return;
	}

	char message[DISCORD_MAX_CONTENT + 1];
	g_hSendQueue.GetString(0, message, sizeof(message));
	g_hSendQueue.Erase(0);

	SendWebHook(message);
}

void StartQueueDispatch()
{
	g_bQueueSending = true;
	SendNextQueuedMessage();
}

void QueueDiscordCodeBlockChunked(const char[] header, const char[] content)
{
	int maxChunkLen = DISCORD_MAX_CONTENT - strlen(header) - 1 - strlen(DISCORD_CODEBLOCK_PREFIX) - strlen(DISCORD_CODEBLOCK_SUFFIX);
	if (maxChunkLen <= 0)
	{
		QueueOutgoingMessage(header);
		return;
	}

	int totalLen = strlen(content);
	char pending[DISCORD_MAX_CONTENT + 1];
	pending[0] = '\0';
	int pendingLen = 0;
	int lineStart = 0;

	while (lineStart <= totalLen)
	{
		int lineEnd = lineStart;
		while (lineEnd < totalLen && content[lineEnd] != '\n')
			lineEnd++;

		int lineLen = lineEnd - lineStart;
		bool hasNextLine = (lineEnd < totalLen);

		if (lineLen <= maxChunkLen)
		{
			bool needNewline = (pendingLen > 0);
			int additional = lineLen + (needNewline ? 1 : 0);

			if (pendingLen > 0 && pendingLen + additional > maxChunkLen)
			{
				char wrappedFlush[DISCORD_MAX_CONTENT + 1];
				FormatEx(wrappedFlush, sizeof(wrappedFlush), "%s\n%s%s%s", header, DISCORD_CODEBLOCK_PREFIX, pending, DISCORD_CODEBLOCK_SUFFIX);
				QueueOutgoingMessage(wrappedFlush);
				pending[0] = '\0';
				pendingLen = 0;
				needNewline = false;
			}

			if (needNewline)
			{
				pending[pendingLen] = '\n';
				pendingLen++;
			}

			for (int i = 0; i < lineLen; i++)
				pending[pendingLen + i] = content[lineStart + i];

			pendingLen += lineLen;
			pending[pendingLen] = '\0';
		}
		else
		{
			if (pendingLen > 0)
			{
				char wrappedFlush[DISCORD_MAX_CONTENT + 1];
				FormatEx(wrappedFlush, sizeof(wrappedFlush), "%s\n%s%s%s", header, DISCORD_CODEBLOCK_PREFIX, pending, DISCORD_CODEBLOCK_SUFFIX);
				QueueOutgoingMessage(wrappedFlush);
				pending[0] = '\0';
				pendingLen = 0;
			}

			int offset = 0;
			while (offset < lineLen)
			{
				int partLen = lineLen - offset;
				if (partLen > maxChunkLen)
					partLen = maxChunkLen;

				char part[DISCORD_MAX_CONTENT + 1];
				for (int i = 0; i < partLen; i++)
					part[i] = content[lineStart + offset + i];
				part[partLen] = '\0';

				char wrappedPart[DISCORD_MAX_CONTENT + 1];
				FormatEx(wrappedPart, sizeof(wrappedPart), "%s\n%s%s%s", header, DISCORD_CODEBLOCK_PREFIX, part, DISCORD_CODEBLOCK_SUFFIX);
				QueueOutgoingMessage(wrappedPart);

				offset += partLen;
			}
		}

		if (!hasNextLine)
			break;

		lineStart = lineEnd + 1;
	}

	if (pendingLen > 0)
	{
		char wrapped[DISCORD_MAX_CONTENT + 1];
		FormatEx(wrapped, sizeof(wrapped), "%s\n%s%s%s", header, DISCORD_CODEBLOCK_PREFIX, pending, DISCORD_CODEBLOCK_SUFFIX);
		QueueOutgoingMessage(wrapped);
	}
}

void BuildAdminLogHeader(const char[] sTime, char[] sHeader, int maxlen)
{
	char sStart[64];
	int iCount = -1;
	int iTick = -1;
	int retValTime = -1;

	if (g_Plugin_AutoRecorder)
	{
		#if defined _autorecorder_included
		if (g_bNative_IsDemoRecording && AutoRecorder_IsDemoRecording())
		{
			if (g_bNative_GetDemoRecordCount)
				iCount = AutoRecorder_GetDemoRecordCount();

			if (g_bNative_GetDemoRecordingTick)
				iTick = AutoRecorder_GetDemoRecordingTick();

			if (g_bNative_GetDemoRecordingTime)
				retValTime = AutoRecorder_GetDemoRecordingTime();
		}
		#endif
	}

	if (retValTime >= 0)
		FormatTime(sStart, sizeof(sStart), "%d.%m.%Y @ %H:%M", retValTime);
	else
		strcopy(sStart, sizeof(sStart), "N/A");

	if (iCount >= 0 || iTick >= 0 || retValTime >= 0)
	{
		FormatEx(sHeader, maxlen, "`%s` *(CT: %d | T: %d) - %s* - Demo: %d @ Tick: ≈ %d *(Started %s)*",
			g_sMap, GetTeamScore(3), GetTeamScore(2), sTime, iCount, iTick, sStart);
		return;
	}

	FormatEx(sHeader, maxlen, "`%s` *(CT: %d | T: %d) - %s* - Demo: N/A",
		g_sMap, GetTeamScore(3), GetTeamScore(2), sTime);
}

public Action OnLogAction(Handle source, Identity ident, int client, int target, const char[] message)
{
	if(!g_sWebhookURL[0])
	{
		LogError("No webhook found or specified.");
		return Plugin_Continue;
	}

	if (g_hSendQueue == null)
	{
		LogError("Send queue is not initialized.");
		return Plugin_Continue;
	}

	// If this user has no admin and is NOT the server
	// let the core log this

	bool isServer = (client < 0 || client == 0);
	bool isValidClient = (!isServer && client <= MaxClients && IsClientConnected(client));

	if (!isServer && !isValidClient)
		return Plugin_Continue;

	if (!isServer && GetUserAdmin(client) == INVALID_ADMIN_ID)
		return Plugin_Continue;

	char sEscapedMessage[ADMINLOGGING_BUFFER_SIZE];
	FormatEx(sEscapedMessage, sizeof(sEscapedMessage), "%s", message);
	ReplaceString(sEscapedMessage, sizeof(sEscapedMessage), "`", "'");
	ReplaceString(sEscapedMessage, sizeof(sEscapedMessage), "> ", ">");
	ReplaceString(sEscapedMessage, sizeof(sEscapedMessage), "/", "୵"); // Prevent URLs from being embedded
	ReplaceString(sEscapedMessage, sizeof(sEscapedMessage), "@", "ⓐ"); // Because it is a webhook, it bypasses the permission
	ReplaceString(sEscapedMessage, sizeof(sEscapedMessage), "\"", ""); // Prevent messages from being cut off

	char sTime[64];
	int iTime = GetTime();
	FormatTime(sTime, sizeof(sTime), "%m/%d/%Y @ %H:%M:%S", iTime);

	char sHeader[512];
	BuildAdminLogHeader(sTime, sHeader, sizeof(sHeader));

	QueueDiscordCodeBlockChunked(sHeader, sEscapedMessage);

	if (!g_bQueueSending)
		StartQueueDispatch();

	return Plugin_Continue;
}

stock void SendWebHook(char sMessage[WEBHOOK_MSG_MAX_SIZE + 1], int iMsgIndex = -1, int iRetries = 0)
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
		LogError("ThreadID not found or specified.");
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

	webhook.Execute(g_sWebhookURL, OnWebHookExecuted, pack, sThreadID);
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

	char sMessage[WEBHOOK_MSG_MAX_SIZE + 1];
	pack.ReadString(sMessage, sizeof(sMessage));

	delete pack;

	if ((!IsThreadReply && response.Status != HTTPStatus_OK) || (IsThreadReply && response.Status != HTTPStatus_NoContent))
	{
		if (retries[iMsgIndex] < g_cvWebhookRetry.IntValue) {
			retries[iMsgIndex]++;
			float fTimer = 1.0 * (retries[iMsgIndex] + 1);

			DataPack Datapack = new DataPack();
			Datapack.WriteString(sMessage);
			Datapack.WriteCell(iMsgIndex);
			Datapack.WriteCell(retries[iMsgIndex]);

			CreateTimer(fTimer, Timer_ResendWebhook, Datapack);
			PrintToServer("[%s] Failed to send the webhook (ID: %d). Resending it in %0.1f seconds.. (%d/%d)", PLUGIN_NAME, iMsgIndex, fTimer, retries[iMsgIndex], g_cvWebhookRetry.IntValue);
			return;
		} else {
			if (!g_bNative_ExtendedDiscord_LogError)
			{
				LogError("Failed to send the webhook after %d retries, aborting.", retries[iMsgIndex]);
				LogError("Failed message : %s", sMessage);
			}
		#if defined _extendeddiscord_included
			else
			{
				ExtendedDiscord_LogError("Failed to send the webhook after %d retries, aborting.", retries[iMsgIndex]);
				ExtendedDiscord_LogError("Failed message : %s", sMessage);
			}
		#endif
		}
	}

	retries[iMsgIndex] = 0;
	SendNextQueuedMessage();
}

public Action Timer_ResendWebhook(Handle timer, DataPack Datapack)
{
	char sMessage[WEBHOOK_MSG_MAX_SIZE + 1];

	Datapack.Reset();
	Datapack.ReadString(sMessage, sizeof(sMessage));
	int iMsgIndex = Datapack.ReadCell();
	int iRetries = Datapack.ReadCell();
	delete Datapack;

	SendWebHook(sMessage, iMsgIndex, iRetries);
	return Plugin_Stop;
}
