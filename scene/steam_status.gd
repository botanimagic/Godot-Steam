extends Panel
#################################################
# OUTPUT COMPONENT
#################################################
# Displays general Steamworks stuff

@onready var title: Label = $Status/Title
@onready var id: Label = $Status/ID
@onready var username: Label = $Status/Username
@onready var owns: Label = $Status/Owns



func _ready() -> void:
	if Global.is_online:
		title.set_text("Steamworks Status (Online)")
	else:
		title.set_text("Steamworks Status (Offline)")
	id.set_text("Steam ID: "+str(Global.steam_id))
	username.set_text("Username: "+str(Global.steam_username))
	owns.set_text("Owns App: "+str(Global.is_owned))
