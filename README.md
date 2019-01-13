# SM-MapManager 
This is probably a super niche plugin that I don't expect anyone else to use  
This plugin assumes that your mapcycle.txt and adminmenu_maplist.ini contain the same maps  

## Description
Synchronizes mapcycle/adminmenu_maplist on map end if mapcycle has changed - updates both on plugin start  
Sorts both files alphabetically  
Logs errors when maps exist in mapcycle, but not in the map directory specified in the #define  
Logs changes to addons/sourcemod/logs/mapmanager/

Edit MAPFOLDER to point to where your map dir is and recompile.  
This plugin works better if you use a custom directory instead of default gamefolder/maps directory  

Considering adding features to support checking against fastdl and the ability to interact with it in some manner  

## Commands  
`sm_addmap <mapname>` - Adds a map to mapcycle (Map must exist in map folder) \[ADMINFLAG_RCON]  
`sm_removemap <mapname>` - Remmoves map from mapcycle \[ADMINFLAG_RCON]  
`sm_deletemap <mapname>` - Deletes map file from server \[ADMFLAG_ROOT]  
`sm_mapmanager` - Opens map manager menu \[ADMINFLAG_RCON]  
