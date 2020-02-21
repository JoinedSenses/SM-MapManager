/*
	Maybe need to consider some sort of web api to fetch maps from a dir...
	... or investigate some way of interacting with fastdl to make my life easier.

	Suggestion was to use system2 extension for http/ftp.
	https://forums.alliedmods.net/showthread.php?t=146019
 */

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <discord>
#define REQUIRE_PLUGIN
#define PLUGIN_VERSION "0.0.5"
#define PLUGIN_DESCRIPTION "An interface for managing mapcycle.txt and adminmenu_maplist.ini"

#define MAPFOLDER "custom/my_custom_folder/maps"
#define MAX_MAP_LEN 80

ConVar g_cvarDiscordChannel;

ArrayList g_aMapList;
ArrayList g_aTemp;

char g_sPath_Log[PLATFORM_MAX_PATH];
char g_sPath_AMmaplist[PLATFORM_MAX_PATH];
char g_sPath_Custom[PLATFORM_MAX_PATH];

bool g_bDiscord;

public Plugin myinfo = {
	name = "Map Manager",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
}

// ----------------- SM API

public void OnPluginStart() {
	CreateConVar("sm_mapmanager_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);
	g_cvarDiscordChannel = CreateConVar("sm_mapmanager_discord", "", "Discord channel to use if integrating SM Discord API", FCVAR_NONE);

	AutoExecConfig();

	RegAdminCmd("sm_addmap", cmdAddMap, ADMFLAG_RCON);
	RegAdminCmd("sm_removemap", cmdRemoveMap, ADMFLAG_RCON);
	RegAdminCmd("sm_deletemap", cmdDeleteMap, ADMFLAG_ROOT);
	RegAdminCmd("sm_mapmanager", cmdMapManager, ADMFLAG_RCON);

	RegAdminCmd("sm_testmaps", cmdTest, ADMFLAG_ROOT);

	g_aMapList = new ArrayList(ByteCountToCells(MAX_MAP_LEN));
	g_aTemp = new ArrayList(ByteCountToCells(MAX_MAP_LEN));

	BuildPath(Path_SM, g_sPath_AMmaplist, sizeof(g_sPath_AMmaplist), "/configs/adminmenu_maplist.ini");
	BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/");
	Format(g_sPath_Custom, sizeof(g_sPath_Custom), MAPFOLDER);

	if (!DirExists(g_sPath_Log)) {
		CreateDirectory(g_sPath_Log, 511);
	}

	if (CheckMapCycle()) {
		UpdateMapFiles();
	}
}

public Action cmdTest(int client, int args) {
	DirectoryListing dir = OpenDirectory(g_sPath_Custom);
	FileType filetype;
	char buffer[64];
	while (dir.GetNext(buffer, sizeof(buffer), filetype)) {
		PrintToChatAll("%s", buffer);
	}

	delete dir;
}

public void OnAllPluginsLoaded() {
	g_bDiscord = LibraryExists("discord");
}

public void OnMapEnd() {
	if (CheckMapCycle(true)) {
		UpdateMapFiles();		
	}
}

// ----------------- Commands

public Action cmdAddMap(int client, int args) {
	if (!args) {
		ReplyToCommand(client, "Usage: sm_addmap <mapname>");
		return Plugin_Handled;
	}
	
	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));

	AddMap(client, mapname);
	return Plugin_Handled;
}

public Action cmdRemoveMap(int client, int args) {
	if (!args) {
		ReplyToCommand(client, "Usage: sm_removemap <mapname>");
		return Plugin_Handled;
	}

	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));

	RemoveMap(client, mapname);
	return Plugin_Handled;
}

public Action cmdDeleteMap(int client, int args) {
	if (!args) {
		ReplyToCommand(client, "Usage: sm_deletemap <mapname>");
		return Plugin_Handled;
	}

	char mapname[64];
	GetCmdArg(1, mapname, sizeof(mapname));

	DisplayConfirmationPanel(client, mapname);
	return Plugin_Handled;
}

public Action cmdMapManager(int client, int args) {
	if (!client) {
		return Plugin_Handled;
	}

	DisplayMainMenu(client);
	return Plugin_Handled;
}

// ----------------- Menus

void DisplayMainMenu(int client) {
	Menu menu = new Menu(menuHandler_Main, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Map Manager");
	menu.AddItem("Add", "Add maps");
	menu.AddItem("Remove", "Remove maps");
	if (CheckCommandAccess(client, "sm_deletemap", ADMFLAG_ROOT)) {
		menu.AddItem("Delete", "Delete maps");
	}
	menu.Display(client, 30);
}

int menuHandler_Main(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[12];
			menu.GetItem(param2, choice, sizeof(choice));

			if (StrEqual(choice, "Add")) {
				DisplayAddMenu(param1);
			}
			else if (StrEqual(choice, "Remove")) {
				DisplayRemoveMenu(param1);
			}
			else if (StrEqual(choice, "Delete")) {
				DisplayDeleteMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
}

void DisplayAddMenu(int client) {
	if (!DirExists(g_sPath_Custom, true, "GAME")) {
		return;
	}

	Menu menu = new Menu(menuHandler_AddMap, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Add Map");
	menu.ExitBackButton = true;

	DirectoryListing mapfolder = OpenDirectory(g_sPath_Custom);
	char buffer[MAX_MAP_LEN];
	
	FileType filetype;
	char extension[16];

	while (mapfolder.GetNext(buffer, sizeof(buffer), filetype)) {
		if (filetype != FileType_File) {
			continue;
		}

		int index = GetFileExtension(buffer, strlen(buffer), extension, sizeof(extension));
		if (StrEqual(extension, "bsp", false)) {
			Format(buffer, index, buffer);

			if (!IsMapInCycle(buffer)) {
				menu.AddItem(buffer, buffer);
			}
		}
	}
	delete mapfolder;

	menu.Display(client, MENU_TIME_FOREVER);
}

int menuHandler_AddMap(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapname[MAX_MAP_LEN];
			menu.GetItem(param2, mapname, sizeof(mapname));
			menu.RemoveItem(param2);
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);

			AddMap(param1, mapname);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayMainMenu(param1);
			}
		}
		case MenuAction_End: {
			if (param2 != MenuEnd_Selected) {
				delete menu;
			}
		}
	}
}

void DisplayRemoveMenu(int client) {
	Menu menu = new Menu(menuHandler_RemoveMap, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("Remove Map");
	menu.ExitBackButton = true;

	char buffer[MAX_MAP_LEN];
	for (int i = 0; i < g_aMapList.Length; i++) {
		g_aMapList.GetString(i, buffer, sizeof(buffer));
		menu.AddItem(buffer, buffer);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

int menuHandler_RemoveMap(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapname[MAX_MAP_LEN];
			menu.GetItem(param2, mapname, sizeof(mapname));
			menu.RemoveItem(param2);
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);

			RemoveMap(param1, mapname);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayMainMenu(param1);
			}
		}
		case MenuAction_DisplayItem: {
			char mapname[MAX_MAP_LEN + 16];
			menu.GetItem(param2, mapname, sizeof(mapname));
			if (!IsMapOnServer(mapname)) {
				Format(mapname, sizeof(mapname), "%s (Not Found)", mapname);
				return RedrawMenuItem(mapname);
			}			
		}
		case MenuAction_End: {
			if (param2 != MenuEnd_Selected) {
				delete menu;
			}
		}
	}
	return 0;
}

void DisplayDeleteMenu(int client) {
	Menu menu = new Menu(menuHandler_DeleteMap, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("Delete Map");
	menu.ExitBackButton = true;

	DirectoryListing mapfolder = OpenDirectory(g_sPath_Custom);
	char buffer[MAX_MAP_LEN];
	
	FileType filetype;
	char extension[16];

	while (mapfolder.GetNext(buffer, sizeof(buffer), filetype)) {
		if (filetype != FileType_File) {
			continue;
		}

		int index = GetFileExtension(buffer, strlen(buffer), extension, sizeof(extension));
		PrintToChatAll("Name: %s Ext: %s", buffer, extension);
		if (StrEqual(extension, "bsp", false)) {
			Format(buffer, index, buffer);

			menu.AddItem(buffer, buffer);
		}
	}
	delete mapfolder;

	menu.Display(client, MENU_TIME_FOREVER);
}

int menuHandler_DeleteMap(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapname[MAX_MAP_LEN];
			menu.GetItem(param2, mapname, sizeof(mapname));

			DisplayConfirmationPanel(param1, mapname);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayMainMenu(param1);
			}
		}
		case MenuAction_DisplayItem: {
			char mapname[MAX_MAP_LEN];
			menu.GetItem(param2, mapname, sizeof(mapname));

			if (IsMapInCycle(mapname)) {
				Format(mapname, sizeof(mapname), "%s   (MAPCYCLE)", mapname);
				return RedrawMenuItem(mapname);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

void DisplayConfirmationPanel(int client, char[] mapname) {
	char title[MAX_MAP_LEN];
	Format(title, sizeof(title), "%s\nDelete Map?", mapname);

	Menu menu = new Menu(menuHandler_DeleteConfirmation, MENU_ACTIONS_DEFAULT);
	menu.SetTitle(title);

	menu.AddItem(mapname, "Yes");
	menu.AddItem("", "No");
	menu.Display(client, 30);
}

int menuHandler_DeleteConfirmation(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapname[64];
			menu.GetItem(param2, mapname, sizeof(mapname));
			if (mapname[0] != '\0') {
				DeleteMap(param1, mapname);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
}

// ----------------- Internal Functions/Stocks

bool CheckMapCycle(bool mapend = false) {
	File file = OpenFile("cfg/mapcycle.txt", "r");

	char buffer[MAX_MAP_LEN];
	bool changed;

	// Check is any maps were added.
	while (!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer))) {
		ReplaceString(buffer, sizeof(buffer), "\n", "", false);
		if (!IsMapInCycle(buffer)) {
			g_aMapList.PushString(buffer);
			changed = true;

			if (mapend) {
				WriteToLog("%s ADDED by Server", buffer);
			}
			else if (!IsMapOnServer(buffer)) {
				WriteToLog("%s in mapcycle, but not on server", buffer);
			}
		}
		g_aTemp.PushString(buffer);
	}
	delete file;

	// Check if any maps were removed.
	for (int i = 0; i < g_aMapList.Length; i++) {
		g_aMapList.GetString(i, buffer, sizeof(buffer));
		if (g_aTemp.FindString(buffer) == -1) {
			g_aMapList.Erase(i);
			changed = true;

			if (mapend) {
				WriteToLog("%s REMOVED by Server", buffer);
			}
		}
	}

	g_aTemp.Clear();

	return changed;
}

void UpdateMapFiles() {
		SortADTArray(g_aMapList, Sort_Ascending, Sort_String);

		char buffer[MAX_MAP_LEN];
		File file = OpenFile("cfg/mapcycle.txt", "w");
		for (int i = 0; i < g_aMapList.Length; i++) {
			g_aMapList.GetString(i, buffer, sizeof(buffer));
			file.WriteLine(buffer);
		}
		delete file;

		file = OpenFile(g_sPath_AMmaplist, "w");
		for (int i = 0; i < g_aMapList.Length; i++) {
			g_aMapList.GetString(i, buffer, sizeof(buffer));
			file.WriteLine(buffer);
		}
		delete file;
}

void AddMap(int client, char[] mapname) {
	if (IsMapInCycle(mapname)) {
		ReplyToCommand(client, "Map already in mapcycle.");
		return;
	}
	
	if (!IsMapOnServer(mapname)) {
		ReplyToCommand(client, "Map not on server. Add to map dir and fastdl before using this cmd");
		return;
	}

	g_aMapList.PushString(mapname);
	UpdateMapFiles();

	ReplyToCommand(client, "%s added to mapcycle", mapname);

	WriteToLog("%s ADDED by %N", mapname, client);
}

void RemoveMap(int client, char[] mapname) {
	int index;
	if (!IsMapInCycle(mapname, index)) {
		ReplyToCommand(client, "Map not in mapcycle");
		return;
	}

	g_aMapList.Erase(index);
	UpdateMapFiles();

	ReplyToCommand(client, "%s removed from mapcycle", mapname);

	WriteToLog("%s REMOVED by %N", mapname, client);
}

void DeleteMap(int client, char[] mapname) {
	if (!IsMapOnServer(mapname)) {
		ReplyToCommand(client, "Map not on server");
		return;
	}

	char filepath[PLATFORM_MAX_PATH];
	Format(filepath, sizeof(filepath), "%s/%s.bsp", MAPFOLDER, mapname);

	if (IsMapInCycle(mapname)) {
		RemoveMap(client, mapname);
	}

	if (!DeleteFile(filepath, true, "GAME")) {
		return;
	}

	ReplyToCommand(client, "Deleted %s.bsp", mapname);
	WriteToLog("%N DELETED %s", client, mapname);
}

int GetFileExtension(char[] filename, int size, char[] extension, int size2) {
	int index;
	for (int i = size - 1; i > 0; i--) {
		if (filename[i] == '.') {
			index = i;
			break;
		}
	}

	if (!index) {
		return -1;
	}

	Format(extension, size2, "%s", filename[index+1]);
	return index+1;
}

bool IsMapOnServer(char[] mapname) {
	char filepath[PLATFORM_MAX_PATH];
	Format(filepath, sizeof(filepath), "%s/%s.bsp", MAPFOLDER, mapname);
	return FileExists(filepath, true, "GAME");
}

bool IsMapInCycle(char[] mapname, int &index = -1) {
	return (index = g_aMapList.FindString(mapname)) != -1;
}

void WriteToLog(char[] message, any ...) {
	char output[1024];
	VFormat(output, sizeof(output), message, 2);

	char date[32];
	FormatTime(date, 100, "%Y_%m_%d");
	BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/%s.log", date);

	File log = OpenFile(g_sPath_Log, "a");
	log.WriteLine(output);
	delete log;

	if (g_bDiscord) {
		char hostname[32];
		FindConVar("hostname").GetString(hostname, sizeof(hostname));

		// This is specific to my servers. If using this plugin, edit if need.
		int index = FindCharInString(hostname, '[');
		Format(output, sizeof(output), "%s | %s", hostname[index-1], output);

		char channel[32];
		g_cvarDiscordChannel.GetString(channel, sizeof(channel));
		
		if (channel[0] != '\0') {
			Discord_SendMessage(channel, output);
		}
	}
}