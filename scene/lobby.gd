extends Panel

enum GAME_MODE { CLASSIC, RANKED }
enum LOBBY_AVAILABILITY { PRIVATE, FRIENDS, PUBLIC, INVISIBLE }

@onready var lobby_member_scene = preload("res://scene/lobby_member.tscn")
@onready var button_theme = preload("res://button_theme.tres")


@onready var output: RichTextLabel = $Frame/Main/Displays/Outputs/Output
@onready var label_lobby_id: Label = $Frame/Main/Displays/Outputs/Titles/LobbyID

@onready var create_lobby_button: Button = $Frame/SideBar/List/CreateLobby
@onready var open_lobby_list_button: Button = $Frame/SideBar/List/OpenLobbyList
@onready var get_lobby_data_button: Button = $Frame/SideBar/List/GetLobbyData
@onready var leave_button: Button = $Frame/SideBar/List/Leave
@onready var send_button: Button = $Frame/Main/Messaging/Send
@onready var matchmaking_button: Button = $Frame/SideBar/List/Matchmaking
@onready var game_mode_selector: OptionButton = $Frame/SideBar/List/GameModeSelector

@onready var chat_input: LineEdit = $Frame/Main/Messaging/Chat

@onready var player_list_title: Label = $Frame/Main/Displays/PlayerLists/Title
@onready var player_list_vbox: VBoxContainer = $Frame/Main/Displays/PlayerLists/Players


@onready var lobbies_panel: Panel = $Lobbies
@onready var lobbies_refresh_button: Button = $Lobbies/Refresh
@onready var close_lobbies_button: Button = $Lobbies/CloseLobbies
@onready var lobbies_list_vbox: VBoxContainer = $Lobbies/Scroll/List


var lobby_id: int = 0
var lobby_members: Array = []
var lobby_max_members: int = 10

var matchmaking_phase: int = 0  # Tracks which phase of matchmaking we're in
var auto_matchmaking_active: bool = false  # Tracks if auto-matchmaking is active

var rng = RandomNumberGenerator.new()

func _ready() -> void:
	# Buttons Connections
	buttons_signal_connections()
	
	Helper.connect_signal(Steam.lobby_created, _on_lobby_created)
	Helper.connect_signal(Steam.lobby_match_list, _on_lobby_match_list)
	Helper.connect_signal(Steam.lobby_joined, _on_lobby_joined)
	Helper.connect_signal(Steam.lobby_message, _on_lobby_message)
	Helper.connect_signal(Steam.lobby_chat_update, _on_lobby_chat_update)
	Helper.connect_signal(Steam.lobby_data_update, _on_lobby_data_update)
	Helper.connect_signal(Steam.lobby_invite, _on_lobby_invite)
	Helper.connect_signal(Steam.join_requested, _on_lobby_join_requested)
	Helper.connect_signal(Steam.persona_state_change, _on_persona_change)
	
	# Initialize random number generator
	rng.randomize()
	
	# Initialize game mode selector
	game_mode_selector.add_item("Classic", GAME_MODE.CLASSIC)
	game_mode_selector.add_item("Ranked", GAME_MODE.RANKED)
	game_mode_selector.select(0)  # Default to Classic
	
	# Check for command line arguments
	check_command_line()



# Send the message by pressing enter
func _input(ev: InputEvent) -> void:
	if ev.is_pressed() and !ev.is_echo() and ev.is_action("chat_send"):
		send_chat()


#################################################
# LOBBY FUNCTIONS
#################################################
# Creating a lobby
func _create_lobby() -> void:
	# Attempt to create a lobby
	create_lobby_for_player()
	output.append_text("[STEAM] Attempt to create a new lobby...\n")
	# Disable the create lobby button
	create_lobby_button.set_disabled(true)


# Getting associated metadata for the lobby
func _get_lobby_data() -> void:
	var data
	data = Steam.getLobbyData(lobby_id, "name")
	output.append_text("[STEAM] Lobby data, name: "+str(data)+"\n")
	data = Steam.getLobbyData(lobby_id, "mode")
	output.append_text("[STEAM] Lobby data, mode: "+str(data)+"\n")

# Kick player 
func _on_kick_player_in_lobby(kick_id: int) -> void:
	# Pass the kick message to Steam
	var IS_SENT: bool = Steam.sendLobbyChatMsg(lobby_id, "/kick:"+str(kick_id))
	# Was it send successfully?
	if not IS_SENT:
		print("[ERROR] Kick command failed to send.\n")


# When the user starts a game with multiplayer enabled
func create_lobby_for_player() -> void:
	# Make sure a lobby is not already set
	if lobby_id == 0:
		# Set the lobby to public with ten members max
		Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, lobby_max_members)
		
		# Set game mode immediately after creation
		var mode_text = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
		Steam.setLobbyData(lobby_id, "mode", mode_text)


# When the player is joining a lobby
func join_lobby(_lobby_id: int) -> void:
	lobby_id = _lobby_id
	output.append_text("[STEAM] Attempting to join lobby "+str(lobby_id)+"...\n")
	# Close lobby panel if open
	_on_close_lobbies_pressed()
	# Clear any previous lobby lists
	lobby_members.clear()
	# Make the lobby join request to Steam
	Steam.joinLobby(lobby_id)


# When the player leaves a lobby for whatever reason
func leave_lobby() -> void:
	# If in a lobby, leave it
	if lobby_id != 0:
		# Append a new message
		output.append_text("[STEAM] Leaving lobby "+str(lobby_id)+".\n")
		# Send leave request to Steam
		Steam.leaveLobby(lobby_id)
		# Wipe the Steam lobby ID then display the default lobby ID and player list title
		lobby_id = 0

		label_lobby_id.set_text("Lobby ID: "+str(lobby_id))
		player_list_title.set_text("Player List (0)")
		# Close session with all users
		for MEMBERS in lobby_members:
			var SESSION_CLOSED: bool = Steam.closeP2PSessionWithUser(MEMBERS['steam_id'])
			print("[STEAM] P2P session closed with "+str(MEMBERS['steam_id'])+": "+str(SESSION_CLOSED))
		# Clear the local lobby list
		lobby_members.clear()
		for player in player_list_vbox.get_children():
			player.hide()
			player.queue_free()
			
		# Reset matchmaking state and button, and enable it
		auto_matchmaking_active = false
		matchmaking_button.text = "Matchmaking"
		matchmaking_button.set_disabled(false)  # Enable the button when leaving lobby
		game_mode_selector.set_disabled(false)  # Re-enable game mode selector when leaving lobby
		
		# Enable the create lobby button
		create_lobby_button.set_disabled(false)
		# Disable the leave lobby button and all test buttons
		change_button_states(true)


# Get the lobby members from Steam
func get_lobby_members() -> void:
	# Clear your previous lobby list
	lobby_members.clear()
	# Clear the original player list
	for MEMBER in player_list_vbox.get_children():
		MEMBER.hide()
		MEMBER.queue_free()
	# Get the number of members from this lobby from Steam
	var MEMBERS: int = Steam.getNumLobbyMembers(lobby_id)
	# Update the player list title
	player_list_title.set_text("Player List ("+str(MEMBERS)+")")
	# Get the data of these players from Steam
	for MEMBER in range(0, MEMBERS):
		print(MEMBER)
		# Get the member's Steam ID
		var MEMBER_STEAM_ID: int = Steam.getLobbyMemberByIndex(lobby_id, MEMBER)
		# Get the member's Steam name
		var MEMBER_STEAM_NAME: String = Steam.getFriendPersonaName(MEMBER_STEAM_ID)
		# Add them to the player list
		add_player_to_connect_list(MEMBER_STEAM_ID, MEMBER_STEAM_NAME)




#################################################
# LOBBY BROWSER
#################################################

# Open the lobby list
func open_lobby_list() -> void:
	lobbies_panel.show()
	# Set distance to worldwide
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	# Request the list
	output.append_text("[STEAM] Requesting a lobby list...\n")
	Steam.requestLobbyList()


# Refresh the lobby list
func _refresh_lobbies() -> void:
	# Clear all previous server entries
	for server in lobbies_list_vbox.get_children():
		server.free()
	# Disable the refresh button
	lobbies_refresh_button.set_disabled(true)
	# Set distance to world (or maybe change this option)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	# Request a new server list
	Steam.requestLobbyList()


#################################################
# LOBBY CHAT
#################################################


# Send a chat message
func send_chat() -> void:
	# Get the entered chat message
	var MESSAGE: String = chat_input.get_text()
	# If there is even a message
	if MESSAGE.length() > 0:
		# Pass the message to Steam
		var IS_SENT: bool = Steam.sendLobbyChatMsg(lobby_id, MESSAGE)
		# Was it sent successfully?
		if not IS_SENT:
			output.append_text("[ERROR] Chat message '"+str(MESSAGE)+"' failed to send.\n")
		# Clear the chat input
		chat_input.clear()


# Using / delimiter for host commands like kick
func process_lobby_message(_result: int, user: int, message: String, type: int):
# We are only concerned with who is sending the message and what the message is
	var SENDER = Steam.getFriendPersonaName(user)
	# If this is a message or host command
	if type == 1:
		# If the lobby owner and the sender are the same, check for commands
		if user == Steam.getLobbyOwner(lobby_id) and message.begins_with("/"):
			print("Message sender is the lobby owner.")
			# Get any commands
			if message.begins_with("/kick"):
				# Get the user ID for kicking
				var COMMANDS: PackedStringArray = message.split(":", true)
				# If this is your ID, leave the lobby
				if Global.steam_id == int(COMMANDS[1]):
					leave_lobby()
		# Else this is just chat message
		else:
			# Print the output before showing the message
			print(str(SENDER)+" : "+str(message))
			output.append_text(str(SENDER)+" : "+str(message)+"\n")
	# Else this is a different type of message
	else:
		match type:
			2: output.append_text(str(SENDER)+" is typing...\n")
			3: output.append_text(str(SENDER)+" sent an invite that won't work in this chat!\n")
			4: output.append_text(str(SENDER)+" sent a text emote that is deprecated.\n")
			6: output.append_text(str(SENDER)+" has left the chat.\n")
			7: output.append_text(str(SENDER)+" has entered the chat.\n")
			8: output.append_text(str(SENDER)+" was kicked!\n")
			9: output.append_text(str(SENDER)+" was banned!\n")
			10: output.append_text(str(SENDER)+" disconnected.\n")
			11: output.append_text(str(SENDER)+" sent an old, offline message.\n")
			12: output.append_text(str(SENDER)+" sent a link that was removed by the chat filter.\n")



#################################################
# CALLBACKS
#################################################
# A lobby has been successfully created
func _on_lobby_created(connect_result: int, _lobby_id: int) -> void:
	if connect_result == 1:
		lobby_id = _lobby_id
		
		output.append_text("[STEAM] Created a lobby: "+str(lobby_id)+"\n")

		# Set lobby joinable as a test
		var SET_JOINABLE: bool = Steam.setLobbyJoinable(lobby_id, true)
		print("[STEAM] The lobby has been set joinable: "+str(SET_JOINABLE))

		# Print the lobby ID to a label
		label_lobby_id.text = "Lobby ID: " + str(lobby_id)

		# Set lobby data
		var SET_LOBBY_DATA: bool = false
		SET_LOBBY_DATA = Steam.setLobbyData(lobby_id, "name", str(Global.steam_username)+"'s Lobby")
		print("[STEAM] Setting lobby name data successful: "+str(SET_LOBBY_DATA))
		
		# Set game mode with the current selected mode
		var mode_text = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
		SET_LOBBY_DATA = Steam.setLobbyData(lobby_id, "mode", mode_text)
		output.append_text("[STEAM] Created new "+mode_text.to_upper()+" mode lobby\n")
		print("[STEAM] Setting game mode data successful: "+str(SET_LOBBY_DATA))

		# Allow P2P connections to fallback to being relayed through Steam if needed
		var IS_RELAY: bool = Steam.allowP2PPacketRelay(true)
		output.append_text("[STEAM] Allowing Steam to be relay backup: "+str(IS_RELAY)+"\n")

 		# Reset matchmaking state and button, and disable them
		auto_matchmaking_active = false
		matchmaking_button.text = "Matchmaking"
		matchmaking_button.set_disabled(true)  # Disable the button when creating lobby
		game_mode_selector.set_disabled(true)  # Disable game mode selector when creating lobby

		# Enable the leave lobby button and all testing buttons
		change_button_states(false)
	else:
		output.append_text("[STEAM] Failed to create lobby\n")


# When a lobby is joined
func _on_lobby_joined(_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# If joining succeed, this will be 1
	if response == 1:
		# Set this lobby ID as your lobby ID
		lobby_id = _lobby_id
		# Print the lobby ID to a label
		label_lobby_id.text = "Lobby ID: " + str(_lobby_id)
		# Append to output
		output.append_text("[STEAM] Joined lobby "+str(_lobby_id)+".\n")
		
		# Reset matchmaking state and button, and disable it
		auto_matchmaking_active = false
		matchmaking_button.text = "Matchmaking"
		matchmaking_button.set_disabled(true)  # Disable the button when in lobby
		game_mode_selector.set_disabled(true)  # Disable game mode selector when in lobby
		
		# Get the lobby members
		get_lobby_members()
		# Enable all necessary buttons
		change_button_states(false)
	# Else it failed for some reason
	else:
		# Get the failure reason
		var FAIL_REASON: String
		match response:
			2:    FAIL_REASON = "This lobby no longer exists."
			3:    FAIL_REASON = "You don't have permission to join this lobby."
			4:    FAIL_REASON = "The lobby is now full."
			5:    FAIL_REASON = "Uh... something unexpected happened!"
			6:    FAIL_REASON = "You are banned from this lobby."
			7:    FAIL_REASON = "You cannot join due to having a limited account."
			8:    FAIL_REASON = "This lobby is locked or disabled."
			9:    FAIL_REASON = "This lobby is community locked."
			10:    FAIL_REASON = "A user in the lobby has blocked you from joining."
			11:    FAIL_REASON = "A user you have blocked is in the lobby."
		output.append_text("[STEAM] Failed joining lobby "+str(_lobby_id)+": "+str(FAIL_REASON)+"\n")
		# Reopen the server list
		_on_open_lobby_list_pressed()


# When a lobby message is received
func _on_lobby_message(_result: int, user: int, message: String, type: int) -> void:
	process_lobby_message(_result, user, message, type)


# Getting a lobby match list
func _on_lobby_match_list(lobbies: Array) -> void:
	if auto_matchmaking_active:
		var selected_mode = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
		var matching_lobbies: Array = []
		
		output.append_text("[STEAM] Found "+str(lobbies.size())+" total lobbies\n")
		output.append_text("[STEAM] Looking for "+selected_mode.to_upper()+" mode lobbies\n")
		
		# First, collect all matching lobbies
		for _lobby_id in lobbies:
			var lobby_member_count: int = Steam.getNumLobbyMembers(_lobby_id)
			var lobby_mode: String = Steam.getLobbyData(_lobby_id, "mode")
			var lobby_name: String = Steam.getLobbyData(_lobby_id, "name")
			
			output.append_text("[STEAM] Checking lobby "+str(_lobby_id)+": Mode="+lobby_mode+" Players="+str(lobby_member_count)+" Name="+lobby_name+"\n")
			
			# Add to matching lobbies if criteria matches
			if lobby_member_count < lobby_max_members and lobby_mode == selected_mode:
				matching_lobbies.append(_lobby_id)
		
		# If we found matching lobbies, randomly select one
		if matching_lobbies.size() > 0:
			# Randomize the matching lobbies
			matching_lobbies.shuffle()
			
			# Get the first (random) lobby from the shuffled list
			var selected_lobby = matching_lobbies[0]
			var lobby_name = Steam.getLobbyData(selected_lobby, "name")
			
			output.append_text("[STEAM] Randomly selected lobby: "+lobby_name+"\n")
			join_lobby(selected_lobby)
		else:
			output.append_text("[STEAM] No matching "+selected_mode.to_upper()+" lobbies in phase "+str(matchmaking_phase)+"\n")
			matchmaking_phase += 1
			matchmaking_loop()
	else:
		# Original lobby list code for manual selection
		for _lobby_id in lobbies:
			var lobby_name: String = Steam.getLobbyData(_lobby_id, "name")
			var lobby_mode: String = Steam.getLobbyData(_lobby_id, "mode").to_upper()
			var lobby_member_count: int = Steam.getNumLobbyMembers(_lobby_id)
			
			# Create a button for the lobby
			var lobby_button: Button = Button.new()
			lobby_button.set_text("Lobby "+str(_lobby_id)+": "+str(lobby_name)+" ["+str(lobby_mode)+"] - "+str(lobby_member_count)+" Player(s)")
			lobby_button.set_size(Vector2(800, 50))
			lobby_button.set_name("lobby_"+str(_lobby_id))
			lobby_button.set_text_alignment(HORIZONTAL_ALIGNMENT_LEFT)
			lobby_button.set_theme(button_theme)
			lobby_button.pressed.connect(join_lobby.bind(_lobby_id))
			
			# Add the new lobby to the list
			lobbies_list_vbox.add_child(lobby_button)
			
		# Enable the refresh button
		lobbies_refresh_button.set_disabled(false)

# When a lobby chat is updated
func _on_lobby_chat_update(_lobby_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	# Note that chat state changes is: 1 - entered, 2 - left, 4 - user disconnected before leaving, 8 - user was kicked, 16 - user was banned
	print("[STEAM] Lobby ID: "+str(_lobby_id)+", Changed ID: "+str(changed_id)+", Making Change: "+str(making_change_id)+", Chat State: "+str(chat_state))
	# Get the user who has made the lobby change
	var CHANGER = Steam.getFriendPersonaName(changed_id)
	# If a player has joined the lobby
	if chat_state == 1:
		output.append_text("[STEAM] "+str(CHANGER)+" has joined the lobby.\n")
	# Else if a player has left the lobby
	elif chat_state == 2:
		output.append_text("[STEAM] "+str(CHANGER)+" has left the lobby.\n")
	# Else if a player has been kicked
	elif chat_state == 8:
		output.append_text("[STEAM] "+str(CHANGER)+" has been kicked from the lobby.\n")
	# Else if a player has been banned
	elif chat_state == 16:
		output.append_text("[STEAM] "+str(CHANGER)+" has been banned from the lobby.\n")
	# Else there was some unknown change
	else:
		output.append_text("[STEAM] "+str(CHANGER)+" did... something.\n")
	# Update the lobby now that a change has occurred
	get_lobby_members()


# Whan lobby metadata has changed
func _on_lobby_data_update(_lobby_id: int, memberID: int, key: int) -> void:
	print("[STEAM] Success, Lobby ID: "+str(_lobby_id)+", Member ID: "+str(memberID)+", Key: "+str(key)+"\n\n")

# When getting a lobby invitation
func _on_lobby_invite(inviter: int, _lobby_id: int, game_id: int) -> void:
	output.append_text("[STEAM] You have received an invite from "+str(Steam.getFriendPersonaName(inviter))+" to join lobby "+str(_lobby_id)+" / game "+str(game_id)+"\n")

# When accepting an invite
func _on_lobby_join_requested(_lobby_id: int, friend_id: int) -> void:
	# Get the lobby owner's name
	var OWNER_NAME = Steam.getFriendPersonaName(friend_id)
	output.append_text("[STEAM] Joining "+str(OWNER_NAME)+"'s lobby...\n")
	# Attempt to join the lobby
	join_lobby(_lobby_id)

# A user's information has changed
func _on_persona_change(steam_id: int, _flag: int) -> void:
	print("[STEAM] A user ("+str(steam_id)+") had information change, update the lobby list")
	# Update the player list
	get_lobby_members()

#################################################
# HELPER FUNCTIONS
#################################################

# Add a new Steam user to the connect users list
func add_player_to_connect_list(steam_id: int, steam_name: String) -> void:
	print("Adding new player to the list: "+str(steam_id)+" / "+str(steam_name))
	# Add them to the list
	lobby_members.append({"steam_id":steam_id, "steam_name":steam_name})
	# Instance the lobby member object
	var lobby_member: LobbyMember = lobby_member_scene.instantiate()
	# Add their Steam name and ID
	lobby_member.name = str(steam_id)
	lobby_member.set_member(steam_id, steam_name)
	# Connect the kick signal
	Helper.connect_signal(lobby_member.kick_player, _on_kick_player_in_lobby)
	player_list_vbox.add_child(lobby_member)
	
	# If you are the host, enable the kick button
	if Global.steam_id == Steam.getLobbyOwner(lobby_id):
		lobby_member.button_kick.set_disabled(false)
	else:
		lobby_member.button_kick.set_disabled(true)


# Enable or disable a gang of buttons
func change_button_states(toggle: bool) -> void:
	leave_button.set_disabled(toggle)
	get_lobby_data_button.set_disabled(toggle)
	send_button.set_disabled(toggle)
	# Caveat for the lineedit
	if toggle:
		chat_input.set_editable(false)
	else:
		chat_input.set_editable(true)


#################################################
# COMMAND LINE ARGUMENTS
#################################################

# Check the command line for arguments
# Used primarily if a player accepts an invite and does not have the game opened
func check_command_line():
	var ARGUMENTS = OS.get_cmdline_args()
	# There are arguments to process
	if ARGUMENTS.size() > 0:
		# There is a connect lobby argument
		if ARGUMENTS[0] == "+connect_lobby":
			if int(ARGUMENTS[1]) > 0:
				print("CMD Line Lobby ID: "+str(ARGUMENTS[1]))
				join_lobby(int(ARGUMENTS[1]))


#################################################
# Auto Matchmaking
#################################################
# Auto-matchmaking functions
func start_auto_matchmaking() -> void:
	matchmaking_phase = 0
	auto_matchmaking_active = true
	output.append_text("[STEAM] Starting auto-matchmaking...\n")
	
	# Update button text to show Cancel
	matchmaking_button.text = "Cancel Matchmaking"
	
	# Disable the game mode selector during matchmaking
	game_mode_selector.set_disabled(true)
	
	matchmaking_loop()

func cancel_auto_matchmaking() -> void:
	auto_matchmaking_active = false
	matchmaking_phase = 0
	output.append_text("[STEAM] Auto-matchmaking cancelled.\n")
	
	# Reset button text
	matchmaking_button.text = "Matchmaking"
	
	# Re-enable the game mode selector
	game_mode_selector.set_disabled(false)

func matchmaking_loop() -> void:
	if matchmaking_phase < 4 and auto_matchmaking_active:
		# Set the distance filter based on phase
		Steam.addRequestLobbyListDistanceFilter(matchmaking_phase)
		
		# Add game mode filter
		var mode_text = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
		Steam.addRequestLobbyListStringFilter("mode", mode_text, Steam.LOBBY_COMPARISON_EQUAL)
		
		# Debug output
		output.append_text("[STEAM] Searching for "+mode_text.to_upper()+" lobbies in phase "+str(matchmaking_phase)+"...\n")
		
		# Request the lobby list
		Steam.requestLobbyList()
	else:
		auto_matchmaking_active = false
		matchmaking_button.text = "Matchmaking"
		# Create a lobby if none found
		output.append_text("[STEAM] No suitable lobbies found. Creating new lobby...\n")
		_create_lobby()

func is_valid_game_mode_match(_lobby_id: int) -> bool:
	var lobby_mode: String = Steam.getLobbyData(_lobby_id, "mode")
	var selected_mode = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
	return lobby_mode == selected_mode

# =====================================
# ===== BUTTONS SIGNAL FUNCTIONS  =====
# =====================================
#
func buttons_signal_connections():
	create_lobby_button.connect("pressed", _on_create_lobby_pressed)
	open_lobby_list_button.connect("pressed", _on_open_lobby_list_pressed)
	matchmaking_button.connect("pressed", _on_matchmaking_pressed)
	get_lobby_data_button.connect("pressed", _on_get_lobby_data_pressed)
	#start_game_button.connect("pressed", _on_start_game_pressed)
	leave_button.connect("pressed", _on_leave_lobby_pressed)
	send_button.connect("pressed", _on_send_message_pressed)
	close_lobbies_button.connect("pressed", _on_close_lobbies_pressed)
	lobbies_refresh_button.connect("pressed", _on_refresh_lobbies_pressed)

#
func _on_create_lobby_pressed():
	print("create lobby pressed")
	_create_lobby()

#
func _on_open_lobby_list_pressed():
	print("open lobby list pressed")
	open_lobby_list()


#
func _on_matchmaking_pressed():
	print("matchmaking pressed")
	if auto_matchmaking_active:
		print("canceling matchmaking")
		cancel_auto_matchmaking()
	else:
		print("starting matchmaking")
		start_auto_matchmaking()

#
func _on_get_lobby_data_pressed():
	print("get lobbyt data")
	_get_lobby_data()

#
func _on_leave_lobby_pressed():
	print("leave lobby pressed")
	leave_lobby()

#
func _on_send_message_pressed():
	print("send message pressed")
	send_chat()

#
func _on_close_lobbies_pressed():
	print("close lobbies pressed")
	lobbies_panel.hide()

#
func _on_refresh_lobbies_pressed():
	print("refresh lobbies pressed")
	_refresh_lobbies()
