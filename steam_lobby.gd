extends Node2D


enum lobby_status { Private, Friends, Public, Invisible }
enum search_distance { Close, Default, Far, Worldwide}

@onready var steam_name: Label = $SteamName
@onready var lobby_set_name: TextEdit = $CreateLobby/LobbySetName
@onready var lobby_get_name: Label = $Chat/LobbyGetName
@onready var lobby_output: RichTextLabel = $Chat/LobbyOutput
@onready var lobby_popup: Popup = $Popup
@onready var lobby_list: VBoxContainer = $Popup/Control/Panel/Scroll/VBoxContainer
@onready var player_count: Label = $Players/PlayerCount
@onready var player_list: RichTextLabel = $Players/PlayerList
@onready var chat_input: TextEdit = $SendMessage/ChatInput


# Buttons
@onready var create_lobby_button: Button = $CreateLobby
@onready var start_game_button: Button = $StartGame
@onready var join_lobby_button: Button = $JoinLobby
@onready var leave_lobby_button: Button = $LeaveLobby
@onready var send_message_button: Button = $SendMessage
@onready var close_list_button: Button = $Popup/Control/Panel/CloseList



func _ready() -> void:
	# Buttons Connections
	buttons_signal_connections()
	
	# Steam Name 
	steam_name.text = Global.steam_username
	
	# STEAM Connections
	#Steam.join_requested.connect(_on_lobby_join_requested) #
	#Steam.lobby_chat_update.connect(_on_lobby_chat_update) #
	Steam.lobby_created.connect(_on_lobby_created) #
	#Steam.lobby_data_update.connect(_on_lobby_data_update) #
	#Steam.lobby_invite.connect(_on_lobby_invite)
	#Steam.lobby_joined.connect(_on_lobby_joined) #
	#Steam.lobby_match_list.connect(_on_lobby_match_list) #
	#Steam.lobby_message.connect(_on_lobby_message) #
	#Steam.persona_state_change.connect(_on_persona_change)

	# Check for command line arguments
	check_command_line()


# 
func create_lobby():
	# Check no ther lobby is running
	if Global.lobby_id == 0:
		Steam.createLobby(lobby_status.Public, 4) 

#
func join_lobby(lobby_id):
	lobby_popup.hide()
	var name = Steam.getLobbyData(lobby_id, "name")
	display_message("Joining lobby: " + str(name) + "....")

	# Clear previous lobby members lists
	Global.lobby_members.clear()

	# Steam join request
	Steam.joinLobby(lobby_id)

#
func display_message(message):
	lobby_output.add_text("\n" + str(message))

# ===================================
# =====      STEAM Callbacks    =====
# ===================================
func _on_lobby_created(connect, lobby_id):
	if connect == 1:
		# Set lobby Id
		Global.lobby_id = lobby_id
		display_message("Created lobby: " + lobby_set_name.text)
		
		# Set Lobby Data
		Steam.setLobbyData(lobby_id, "name", lobby_set_name.text)
		var name = Steam.getLobbyData(lobby_id, "name")
		lobby_get_name.text = str(name)



# ===================================
# ===== COMMAND LINE ARGUMENTS  =====
# ===================================
func check_command_line() -> void:
	var these_arguments: Array = OS.get_cmdline_args()

	# There are arguments to process
	if these_arguments.size() > 0:

		# A Steam connection argument exists
		if these_arguments[0] == "+connect_lobby":

			# Lobby invite exists so try to connect to it
			if int(these_arguments[1]) > 0:

				# At this point, you'll probably want to change scenes
				# Something like a loading into lobby screen
				print("Command line lobby ID: %s" % these_arguments[1])
				#join_lobby(int(these_arguments[1]))


# =====================================
# ===== BUTTONS SIGNAL FUNCTIONS  =====
# =====================================
func buttons_signal_connections():
	create_lobby_button.connect("pressed", _on_create_lobby_pressed)
	start_game_button.connect("pressed", _on_start_game_pressed)
	join_lobby_button.connect("pressed", _on_join_lobby_pressed)
	leave_lobby_button.connect("pressed", _on_leave_lobby_pressed)
	send_message_button.connect("pressed", _on_send_message_pressed)
	close_list_button.connect("pressed", _on_close_list_pressed)

func _on_create_lobby_pressed():
	print("create lobby pressed")
	create_lobby()

func _on_start_game_pressed():
	print("start game pressed")

func _on_join_lobby_pressed():
	print("join lobby pressed")

func _on_leave_lobby_pressed():
	print("leave_lobby pressed")

func _on_send_message_pressed():
	print("send_message pressed")

func _on_close_list_pressed():
	print("close_list pressed")
