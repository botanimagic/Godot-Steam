extends Control

@onready var players_label: Label = $PlayersLabel
@onready var center_label: Label = $Label

func _ready() -> void:
	# Get all players from the lobby using Global.current_lobby_id
	var lobby_id = Global.current_lobby_id
	var player_list = ""
	
	var num_members = Steam.getNumLobbyMembers(lobby_id)
	for i in range(num_members):
		var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name = Steam.getFriendPersonaName(member_id)
		player_list += "%s (ID: %s)\n" % [member_name, member_id]
	
	# Update the players label
	players_label.text = "Players in game:\n" + player_list
	
	# Update center label to include lobby ID
	center_label.text = "GamePlay BANGG\nComing Sun\nLobby ID: %s" % lobby_id
