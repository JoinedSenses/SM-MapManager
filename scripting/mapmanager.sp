/*
	Maybe need to consider some sort of web api to fetch maps from a dir...
	... or investigate some way of interacting with fastdl to make my life easier.

	Suggestion was to use system2 extension for http/ftp.
	https://forums.alliedmods.net/showthread.php?t=146019
 */

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#define PLUGIN_VERSION "0.0.1"
#define PLUGIN_DESCRIPTION "An interface for managing mapcycle.txt and adminmenu_maplist.ini"

#define MAPFOLDER "custom/my_custom_folder/maps"

ArrayList g_aMapList;

char g_sPath_Log[PLATFORM_MAX_PATH];
char g_sPath_AMmaplist[PLATFORM_MAX_PATH];
char g_sPath_Custom[PLATFORM_MAX_PATH];

public Plugin myinfo = {
	name = "Map Manager",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
}

// ----------------- SM API

public void OnPluginStart() {
	CreateConVar("sm_mapmanager_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);

	RegAdminCmd("sm_addmap", cmdAddMap, ADMFLAG_RCON);
	RegAdminCmd("sm_removemap", cmdRemoveMap, ADMFLAG_RCON);
	RegAdminCmd("sm_deletemap", cmdDeleteMap, ADMFLAG_ROOT);
	RegAdminCmd("sm_mapmanager", cmdMapManager, ADMFLAG_RCON);

	g_aMapList = new ArrayList(ByteCountToCells(80));

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
	char buffer[80];
	
	FileType filetype;
	char extension[16];

	while (mapfolder.GetNext(buffer, sizeof(buffer), filetype)) {
		if (filetype != FileType_File) {
			continue;
		}
		int index = GetFileExtension(buffer, sizeof(buffer), extension, sizeof(extension));
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
			char mapname[80];
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

	char buffer[80];
	for (int i = 0; i < g_aMapList.Length; i++) {
		g_aMapList.GetString(i, buffer, sizeof(buffer));
		menu.AddItem(buffer, buffer);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

int menuHandler_RemoveMap(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char mapname[80];
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
			char mapname[96];
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
	char buffer[80];
	
	FileType filetype;
	char extension[16];

	while (mapfolder.GetNext(buffer, sizeof(buffer), filetype)) {
		if (filetype != FileType_File) {
			continue;
		}

		int index = GetFileExtension(buffer, sizeof(buffer), extension, sizeof(extension));
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
			char mapname[80];
			menu.GetItem(param2, mapname, sizeof(mapname));

			DisplayConfirmationPanel(param1, mapname);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayMainMenu(param1);
			}
		}
		case MenuAction_DisplayItem: {
			char mapname[80];
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
	char title[80];
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

bool CheckMapCycle(bool late = false) {
	File file = OpenFile("cfg/mapcycle.txt", "r");

	char buffer[80];
	bool changed;
	while (!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer))) {
		ReplaceString(buffer, sizeof(buffer), "\n", "", false);
		if (!IsMapInCycle(buffer)) {
			g_aMapList.PushString(buffer);
			changed = true;

			if (late) {
				char date[32];
				FormatTime(date, 100, "%Y_%m_%d");
				BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/%s", date);
				File log = OpenFile(g_sPath_Log, "a");
				log.WriteLine(buffer);
				delete log;
			}
			else if (!IsMapOnServer(buffer)) {
				LogError("%s in mapcycle, but not on server", buffer);
			}
		}
	}
	delete file;

	return changed;
}

void UpdateMapFiles() {
		SortADTArray(g_aMapList, Sort_Ascending, Sort_String);

		char buffer[80];
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
	
	char buffer[32];
	if (!IsMapOnServer(mapname)) {
		ReplyToCommand(client, "Map not on server. Add to map dir and fastdl before using this cmd");
		return;
	}

	g_aMapList.PushString(mapname);
	UpdateMapFiles();

	ReplyToCommand(client, "%s added to mapcycle", mapname);

	char date[32];
	FormatTime(date, 100, "%Y_%m_%d");
	BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/%s.log", date);
	File log = OpenFile(g_sPath_Log, "a");
	log.WriteLine("%N ADDED %s", client, buffer);
	delete log;
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

	char date[32];
	FormatTime(date, 100, "%Y_%m_%d");
	BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/%s.log", date);
	File log = OpenFile(g_sPath_Log, "a");
	log.WriteLine("%N REMOVED %s", client, mapname);
	delete log;
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
	char date[32];
	FormatTime(date, 100, "%Y_%m_%d");
	BuildPath(Path_SM, g_sPath_Log, sizeof(g_sPath_Log), "/logs/mapmanager/%s.log", date);
	File log = OpenFile(g_sPath_Log, "a");
	log.WriteLine("%N DELETED %s", client, mapname);
	delete log;
}

int GetFileExtension(char[] filename, int size, char[] extension, int size2) {
	int index;
	for (int i = 0; i < size && filename[i] != '\0'; i++) {
		if (filename[i] == '.') {
			index = i;
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