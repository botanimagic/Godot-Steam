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


#
func _ready() -> void:
	# Buttons Connections
	buttons_signal_connections()
	
	# Steam Name 
	steam_name.text = Global.steam_username
	
	# STEAM Connections
	Steam.join_requested.connect(_on_lobby_join_requested) #
	Steam.lobby_chat_update.connect(_on_lobby_chat_update) #
	Steam.lobby_created.connect(_on_lobby_created) #
	Steam.lobby_data_update.connect(_on_lobby_data_update) #
	#Steam.lobby_invite.connect(_on_lobby_invite)
	Steam.lobby_joined.connect(_on_lobby_joined) #
	Steam.lobby_match_list.connect(_on_lobby_match_list) #
	Steam.lobby_message.connect(_on_lobby_message) #
	#Steam.persona_state_change.connect(_on_persona_change)

	# Check for command line arguments
	check_command_line()


# 
func create_lobby():
	# Check no ther lobby is running
	if Global.lobby_id == 0:
		Steam.createLobby(lobby_status.Public, 4) 

#
func join_lobby(_lobby_id):
	lobby_popup.hide()
	var _name = Steam.getLobbyData(_lobby_id, "name")
	display_message("Joining lobby: " + str(_name) + "....")

	# Clear previous lobby members lists
	Global.lobby_members.clear()

	# Steam join request
	Steam.joinLobby(_lobby_id)


#
func get_lobby_members():
	# Clear previous lobby member lists
	Global.lobby_members.clear()

	# Get number of members in lobby
	var members_count = Steam.getNumLobbyMembers(Global.lobby_id)
	# Update player list count 
	player_count.set_text("Players ("+ str(members_count)+")")

	# Get member data
	for member in range(0, members_count):
		# Members Steam Id
		var member_steam_id = Steam.getLobbyMemberByIndex(Global.lobby_id, member)
		# Members Steam Name
		var member_steam_name = Steam.getFriendPersonaName(member_steam_id)
		# Add members to list
		add_player_list(member_steam_id, member_steam_name)

# 
func send_chat_message():
	# Get chat input
	var message = chat_input.text
	# Pass message to steam
	var sent = Steam.sendLobbyChatMsg(Global.lobby_id, message)
	# Check message sent
	if not sent:
		display_message("ERROR: Chat message failed to send")
	# Clear
	chat_input.text = ""


# 
func leave_lobby():
	# If in lobby, leave it
	if Global.lobby_id != 0:
		display_message("Leaving lobby...")
		# Send leave request
		Steam.leaveLobby(Global.lobby_id)
		# Wipe lobby id
		Global.lobby_id = 0
		
		lobby_get_name.text = "Lobby Name"
		player_count.text = "Players (0)"
		player_list.clear()
		
		# Cloase session with all users
		for member in Global.lobby_members:
			Steam.closeP2PSessionWithUser(member["steam_id"])
		
		# Clear lobby list
		Global.lobby_members.clear()

#
func display_message(_message):
	lobby_output.add_text("\n" + str(_message))

# 
func add_player_list(_steam_id, _steam_name):
	# Add player to list
	Global.lobby_members.append({"steam_id": _steam_id, "steam_name":_steam_name})
	# Ensure list is clear
	player_list.clear()
	# Populate player list
	for member in Global.lobby_members:
		player_list.add_text(str(member["steam_name"]) + "\n")

# ===================================
# =====      STEAM Callbacks    =====
# ===================================
#
func _on_lobby_created(_connect, _lobby_id):
	if _connect == 1:
		# Set lobby Id
		Global.lobby_id = _lobby_id
		display_message("Created lobby: " + lobby_set_name.text)
		
		# Set Lobby Data
		Steam.setLobbyData(_lobby_id, "name", lobby_set_name.text)
		var _name = Steam.getLobbyData(_lobby_id, "name")
		lobby_get_name.text = str(_name)

#
func _on_lobby_joined(_lobby_id, _permission, _locked, _response):
	# Set lobby ID
	Global.lobby_id = _lobby_id
	
	# Get the lobby Id name
	var _name = Steam.getLobbyData(_lobby_id, "name")
	lobby_get_name.text = str(_name)
	
	# Get lobby members
	get_lobby_members()

#
func _on_lobby_join_requested(_lobby_id, _friend_id):
	# Get lobby owners name
	var owner_name = Steam.getFriendPersonaName(_lobby_id)
	display_message("Joining " + str(owner_name) + "loby...")
	
	# Joined Lobby
	join_lobby(_lobby_id)

# When lobby metadata has changed
func _on_lobby_data_update(_succes, _lobby_id, _member_id, _key):
	print("Succes: " + str(_succes)+", Lobby ID: "+ str(_lobby_id)+", Member ID: "+ str(_member_id)+ ", Key:" + str(_key))

#
func _on_lobby_chat_update(_lobby_id, _change_id, _making_change_id, chat_state):
	# User who made lobby change
	var changer = Steam.getFriendPersonaName(_making_change_id)

	# Chat State change made
	if chat_state == 1:
		display_message(str(changer) + "has joined the lobby")
	elif chat_state == 2:
		display_message(str(changer) + "has left the lobby")
	elif chat_state == 4:
		display_message(str(changer) + "has disconnected the lobby")
	elif chat_state == 8:
		display_message(str(changer) + "has been kicked from the lobby")
	elif chat_state == 16:
		display_message(str(changer) + "has been banned from the lobby")
	else: 
		display_message(str(changer) + "did... something.")

	# Udpate Lobby
	get_lobby_members()


#
func _on_lobby_match_list(_lobbies):
	for lobby in _lobbies:
		# Grab desired lobby data
		var lobby_name = Steam.getLobbyData(lobby, "name")
		
		# Get the current number of members
		var lobby_members = Steam.getNumLobbyMembers(lobby)
		
		# Create button for each lobby
		var lobby_button = Button.new()
		lobby_button.set_text("Lobby " + str(lobby) + ": " + str(lobby_name) + " - [" + str(lobby_members) + "] Player(s)")
		lobby_button.set_size(Vector2(800,50))
		lobby_button.set_name("lobby_" +str(lobby))
		lobby_button.connect("pressed", join_lobby.bind(lobby))
		
		# Add lobby to the list
		lobby_list.add_child(lobby_button)


# 
func _on_lobby_message(_result, _user, _message, _type):
	# Sender and their message
	var sender = Steam.getFriendPersonaName(_user)
	display_message(str(sender) + " : " + str(_message))


# ===================================
# ===== COMMAND LINE ARGUMENTS  =====
# ===================================
#
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
				join_lobby(int(these_arguments[1]))


# =====================================
# ===== BUTTONS SIGNAL FUNCTIONS  =====
# =====================================
#
func buttons_signal_connections():
	create_lobby_button.connect("pressed", _on_create_lobby_pressed)
	start_game_button.connect("pressed", _on_start_game_pressed)
	join_lobby_button.connect("pressed", _on_join_lobby_pressed)
	leave_lobby_button.connect("pressed", _on_leave_lobby_pressed)
	send_message_button.connect("pressed", _on_send_message_pressed)
	close_list_button.connect("pressed", _on_close_list_pressed)

#
func _on_create_lobby_pressed():
	print("create lobby pressed")
	create_lobby()

#
func _on_start_game_pressed():
	print("start game pressed")

#
func _on_join_lobby_pressed():
	print("join lobby pressed")
	lobby_popup.popup()
	# Set server search distacne to worldwide
	Steam.addRequestLobbyListDistanceFilter(search_distance.Worldwide)
	display_message("searching for lobbies...")

	Steam.requestLobbyList()

#
func _on_leave_lobby_pressed():
	print("leave_lobby pressed")
	leave_lobby()

#
func _on_send_message_pressed():
	print("send_message pressed")
	send_chat_message()

#
func _on_close_list_pressed():
	print("close_list pressed")
	lobby_popup.hide()
