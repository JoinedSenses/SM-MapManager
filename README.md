# SM-MapManager 
This is probably a super niche plugin that I don't expect anyone else to use  

## Description
Synchronizes mapcycle/adminmenu_maplist on map end if mapcycle has changed - updates both on plugin start  
Logs errors when maps exist in mapcycle, but not in the map directory specified in the #define  

Edit MAPFOLDER to point to where your map dir is and recompile.  
This plugin works better if you use a custom directory instead of default gamefolder/maps directory  

Considering adding features to support checking against fastdl and the ability to interact with it in some manner  

## Commands  
`sm_addmap <mapname>` - Adds a map to mapcycle (Map must exist in map folder)  
`sm_removemap <mapname>` - Remmoves map from mapcycle  
`sm_deletemap <mapname>` - Deletes map file from server  
`sm_mapmanager` - Opens map manager menu  
