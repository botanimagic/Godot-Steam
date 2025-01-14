extends Control

@onready var players_container = $PlayerList/Players

var players_data: Array = []

func _ready() -> void:
	# Get players data passed from lobby
	if Global.current_players_data.size() > 0:
		players_data = Global.current_players_data
		display_players()

func display_players() -> void:
	# Clear existing player labels
	for child in players_container.get_children():
		child.queue_free()
	
	# Create labels for each player
	for player in players_data:
		var player_label = Label.new()
		player_label.text = "Player: " + player.steam_name + " (ID: " + str(player.steam_id) + ")"
		#player_label.font_size = 20
		players_container.add_child(player_label)
