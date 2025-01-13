extends Panel

enum GAME_MODE { CLASSIC, RANKED }


@onready var lobby_member_scene = preload("res://scene/lobby_member.tscn")
@onready var button_theme = preload("res://button_theme.tres")


@onready var output: RichTextLabel = $Frame/Main/Displays/Outputs/Output
@onready var label_lobby_id: Label = $Frame/Main/Displays/Outputs/Titles/LobbyID
@onready var side_bar_list: VBoxContainer = $Frame/SideBar/List
@onready var voice: Node = $Voice



@onready var create_lobby_button: Button = $Frame/SideBar/List/CreateLobby
@onready var open_lobby_list_button: Button = $Frame/SideBar/List/OpenLobbyList
@onready var get_lobby_data_button: Button = $Frame/SideBar/List/GetLobbyData
@onready var leave_button: Button = $Frame/SideBar/List/Leave
@onready var send_button: Button = $Frame/Main/Messaging/Send
@onready var matchmaking_button: Button = $Frame/SideBar/List/FindMatch
@onready var game_mode_selector: OptionButton = $Frame/SideBar/List/GameModeSelector

@onready var chat_input: LineEdit = $Frame/Main/Messaging/Chat

@onready var player_list_title: Label = $Frame/Main/Displays/PlayerLists/Title
@onready var player_list_vbox: VBoxContainer = $Frame/Main/Displays/PlayerLists/Players


@onready var lobbies_panel: Panel = $Lobbies
@onready var lobbies_refresh_button: Button = $Lobbies/Refresh
@onready var close_lobbies_button: Button = $Lobbies/CloseLobbies
@onready var lobbies_list_vbox: VBoxContainer = $Lobbies/Scroll/List


# Party/Lobby System
var lobby_id: int = 0
var lobby_members: Array = []
var lobby_max_members: int = 10
const MIN_PLAYERS_TO_START: int = 4  # Minimum players needed to start a game
const MIN_PLAYERS_TO_MATCHMAKE: int = 1  # Minimum players needed to start matchmaking
const REQUIRED_PLAYERS: int = 4  # Number of players needed to start
var is_lobby_ready: bool = false

# Matchmaking System
var is_matchmaking: bool = false
var matchmaking_timer: float = 0.0
const MATCHMAKING_TIMEOUT: float = 180.0  # 3 minutes timeout
var matchmaking_start_time: float = 0.0
var matchmaking_phase: int = 0  # Add this with your other variables



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
	
	
	# Initialize game mode selector
	game_mode_selector.add_item("Classic", GAME_MODE.CLASSIC)
	game_mode_selector.add_item("Ranked", GAME_MODE.RANKED)
	game_mode_selector.select(0)  # Default to Classic
	
	
	# Check for command line arguments
	check_command_line()

func _process(delta: float) -> void:
	if is_matchmaking:
		matchmaking_timer += delta
		var elapsed_time = Time.get_unix_time_from_system() - matchmaking_start_time
		var current_players = Steam.getNumLobbyMembers(lobby_id)
		
		# Update button text with player count
		var minutes: int = int(floor(elapsed_time / 60))
		var seconds: int = int(floor(elapsed_time)) % 60
		matchmaking_button.text = "Cancel Search (%d/%d)\nSearching: %02d:%02d" % [
			current_players, 
			REQUIRED_PLAYERS,
			minutes, 
			seconds
		]
		
		# Check for timeout
		if matchmaking_timer >= MATCHMAKING_TIMEOUT:
			cancel_matchmaking()
			output.append_text("[STEAM] Matchmaking timed out after %d minutes\n" % [MATCHMAKING_TIMEOUT / 60])
	
	# Check for incoming voice packets
	check_voice_packets()

# Add this new function to handle voice packets
func check_voice_packets() -> void:
	# Get the number of available packets
	var available_packets = Steam.getAvailableP2PPacketSize(0)
	
	# Process up to packet_read_limit packets per frame
	var packets_read = 0
	while available_packets > 0 and packets_read < voice.packet_read_limit:
		var packet_data = Steam.readP2PPacket(available_packets, 0)
		
		if packet_data["data"].size() > 0:
			# Send voice data to voice node for playback
			var voice_data = {
				"buffer": packet_data["data"],
				"written": packet_data["data"].size()
			}
			voice.play_network_voice(voice_data)
		
		packets_read += 1
		available_packets = Steam.getAvailableP2PPacketSize(0)

# Send the message by pressing enter
func _input(ev: InputEvent) -> void:
	if ev.is_pressed() and !ev.is_echo() and ev.is_action("chat_send"):
		send_chat()


func transition_to_game() -> void:
	output.append_text("[STEAM] Starting game with " + str(Steam.getNumLobbyMembers(lobby_id)) + " players...\n")
	
	# Store the lobby ID in Global singleton
	Global.current_lobby_id = lobby_id
	
	# Change to the game scene
	get_tree().change_scene_to_file("res://scene/game_play.tscn")

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

		 # Set voice chat permissions - remove invalid function call
		Steam.allowP2PPacketRelay(true)
		



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
	if lobby_id != 0:
		output.append_text("[STEAM] Leaving lobby "+str(lobby_id)+".\n")
		Steam.leaveLobby(lobby_id)
		lobby_id = 0

		label_lobby_id.set_text("Lobby ID: "+str(lobby_id))
		player_list_title.set_text("Player List (0)")
		
		for MEMBERS in lobby_members:
			var SESSION_CLOSED: bool = Steam.closeP2PSessionWithUser(MEMBERS['steam_id'])
			print("[STEAM] P2P session closed with "+str(MEMBERS['steam_id'])+": "+str(SESSION_CLOSED))
			
		lobby_members.clear()
		for player in player_list_vbox.get_children():
			player.hide()
			player.queue_free()
			
		# Reset matchmaking state
		is_matchmaking = false
		matchmaking_button.text = "Find Match"
		matchmaking_button.set_disabled(false)
		game_mode_selector.set_disabled(false)
		
		create_lobby_button.set_disabled(false)
		change_button_states(true)


# Get the lobby members from Steam
func get_lobby_members() -> void:
	# Clear your previous lobby list
	lobby_members.clear()
	for MEMBER in player_list_vbox.get_children():
		MEMBER.hide()
		MEMBER.queue_free()
		
	# Get current members
	var MEMBERS: int = Steam.getNumLobbyMembers(lobby_id)
	player_list_title.set_text("Player List ("+str(MEMBERS)+")")
	
	# Add all members to the list
	for MEMBER in range(0, MEMBERS):
		var MEMBER_STEAM_ID: int = Steam.getLobbyMemberByIndex(lobby_id, MEMBER)
		var MEMBER_STEAM_NAME: String = Steam.getFriendPersonaName(MEMBER_STEAM_ID)
		add_player_to_connect_list(MEMBER_STEAM_ID, MEMBER_STEAM_NAME)
	
	print("\nPlayer lists")
	print("players list vbox : ", player_list_vbox.get_children())
	# Set player list node to voice.players_lists
	#for player in player_list_vbox.get_children():
		#print("player : ", player)
		#if player is Control:
			#voice.players_lists.append(player)
	#print("player lists : ", voice.players_lists)
	
	# Update matchmaking button state for lobby owner
	if Global.steam_id == Steam.getLobbyOwner(lobby_id):
		matchmaking_button.set_disabled(false)
	else:
		matchmaking_button.set_disabled(true)
	
	# Check if we should start the game
	if MEMBERS >= REQUIRED_PLAYERS and not is_lobby_ready:
		is_lobby_ready = true
		
		# If we're the host, initiate the game start
		if Global.steam_id == Steam.getLobbyOwner(lobby_id):
			output.append_text("[STEAM] Required players reached! Starting game...\n")
			# Notify all players to start
			Steam.setLobbyData(lobby_id, "game_starting", "true")
			await get_tree().create_timer(3.0).timeout  # Give time for notification
			transition_to_game()



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

		# Enable matchmaking button since we're the lobby owner
		matchmaking_button.text = "Find Match"
		matchmaking_button.disabled = false  # Enable matchmaking for new lobby
		game_mode_selector.disabled = true

		# Enable other buttons
		change_button_states(false)
	else:
		output.append_text("[STEAM] Failed to create lobby\n")


# When a lobby is joined
func _on_lobby_joined(_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response == 1:
		lobby_id = _lobby_id
		label_lobby_id.text = "Lobby ID: " + str(_lobby_id)
		output.append_text("[STEAM] Joined lobby "+str(_lobby_id)+".\n")
	
		# Reset matchmaking state
		is_matchmaking = false
		matchmaking_button.text = "Find Match"
		
		# Only enable matchmaking button for the lobby owner
		if Global.steam_id == Steam.getLobbyOwner(lobby_id):
			matchmaking_button.set_disabled(false)
		else:
			matchmaking_button.set_disabled(true)
		
		game_mode_selector.set_disabled(true)
		
		# Set up P2P networking for voice chat - remove invalid function call
		Steam.allowP2PPacketRelay(true)
		
		# Accept P2P sessions from lobby members
		for member in lobby_members:
			if member["steam_id"] != Global.steam_id:
				Steam.acceptP2PSessionWithUser(member["steam_id"])
		
		# Check if this join makes a full lobby
		var current_members = Steam.getNumLobbyMembers(lobby_id)
		if current_members >= REQUIRED_PLAYERS:
			output.append_text("[STEAM] Lobby is now full! Starting game...\n")
			# If we're the host, initiate the game start
			if Global.steam_id == Steam.getLobbyOwner(lobby_id):
				Steam.setLobbyData(lobby_id, "game_starting", "true")
				await get_tree().create_timer(3.0).timeout
				transition_to_game()
		
		get_lobby_members()
		change_button_states(false)
	else:
		var FAIL_REASON: String
		match response:
			2: FAIL_REASON = "This lobby no longer exists."
			3: FAIL_REASON = "You don't have permission to join this lobby."
			4: FAIL_REASON = "The lobby is now full."
			5: FAIL_REASON = "Uh... something unexpected happened!"
			6: FAIL_REASON = "You are banned from this lobby."
			7: FAIL_REASON = "You cannot join due to having a limited account."
			8: FAIL_REASON = "This lobby is locked or disabled."
			9: FAIL_REASON = "This lobby is community locked."
			10: FAIL_REASON = "A user in the lobby has blocked you from joining."
			11: FAIL_REASON = "A user you have blocked is in the lobby."
			_: FAIL_REASON = "Unknown error."
		
		output.append_text("[STEAM] Failed joining lobby "+str(_lobby_id)+": "+str(FAIL_REASON)+"\n")
		_on_open_lobby_list_pressed()

# When a lobby message is received
func _on_lobby_message(_result: int, user: int, message: String, type: int) -> void:
	process_lobby_message(_result, user, message, type)


# Getting a lobby match list
func _on_lobby_match_list(lobbies: Array) -> void:
	if is_matchmaking:
		var matching_lobbies: Array = []
		var our_party_size = Steam.getNumLobbyMembers(lobby_id)
		
		output.append_text("[STEAM] Found %d potential lobbies in phase %d\n" % [lobbies.size(), matchmaking_phase])
		
		# First, find all potential matching lobbies
		for potential_lobby in lobbies:
			if potential_lobby == lobby_id:  # Skip our own lobby
				continue
				
			var lobby_member_count = Steam.getNumLobbyMembers(potential_lobby)
			var total_players = lobby_member_count + our_party_size
			
			# Only consider lobbies that would make a full game (2 players)
			if total_players == REQUIRED_PLAYERS:
				var lobby_mode = Steam.getLobbyData(potential_lobby, "mode")
				var our_mode = game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC
				
				# Make sure game modes match
				if (lobby_mode == "classic") == our_mode:
					matching_lobbies.append({
						"id": potential_lobby,
						"members": lobby_member_count
					})
		
		# If we found any matching lobbies that would make a full game
		if matching_lobbies.size() > 0:
			# Sort by member count (highest first)
			matching_lobbies.sort_custom(func(a, b): return a.members > b.members)
			
			# Merge with the fullest compatible lobby
			var target_lobby = matching_lobbies[0]
			output.append_text("[STEAM] Found matching lobby to make a full game! Merging...\n")
			merge_parties(target_lobby.id)
			return
		
		# No matches found that would make a full game, continue searching
		matchmaking_phase += 1
		await get_tree().create_timer(5.0).timeout
		if is_matchmaking:
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
	# Check if this is the game start signal
	if Steam.getLobbyData(lobby_id, "game_starting") == "true" and not is_lobby_ready:
		is_lobby_ready = true
		output.append_text("[STEAM] Host is starting the game!\n")
		await get_tree().create_timer(3.0).timeout
		transition_to_game()

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
func start_party_matchmaking() -> void:
	# Make sure we're in a lobby
	if lobby_id == 0:
		output.append_text("[STEAM] Must be in a lobby to start matchmaking\n")
		return
	
	if Global.steam_id != Steam.getLobbyOwner(lobby_id):
		output.append_text("[STEAM] Only the party leader can start matchmaking\n")
		return
	
	# Reset matchmaking variables
	matchmaking_phase = 0
	is_matchmaking = true
	matchmaking_timer = 0.0
	matchmaking_start_time = Time.get_unix_time_from_system()
	
	var current_players = Steam.getNumLobbyMembers(lobby_id)
	# Update button text with initial player count
	matchmaking_button.text = "Cancel Search (%d/%d)\nSearching: 00:00" % [current_players, REQUIRED_PLAYERS]
	
	# Mark our lobby as searching
	Steam.setLobbyData(lobby_id, "status", "searching")
	
	output.append_text("[STEAM] Starting matchmaking with %d players...\n" % current_players)
	
	# Start the matchmaking loop
	matchmaking_loop()

func search_for_match() -> void:
	if not is_matchmaking:
		return
	
	# Get our current party size
	var our_party_size = Steam.getNumLobbyMembers(lobby_id)
	
	# Set up lobby search filters
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	
	# Filter by game mode
	var mode_text = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
	Steam.addRequestLobbyListStringFilter("mode", mode_text, Steam.LOBBY_COMPARISON_EQUAL)
	
	# Filter by status (only look for other searching lobbies)
	Steam.addRequestLobbyListStringFilter("status", "searching", Steam.LOBBY_COMPARISON_EQUAL)
	
	# Add filter for available slots
	# Steam.LOBBY_COMPARISON_EQUAL = 0
	# Steam.LOBBY_COMPARISON_NOT_EQUAL = 3
	# Steam.LOBBY_COMPARISON_LESS_THAN = 1
	# Steam.LOBBY_COMPARISON_GREATER_THAN = 2
	Steam.addRequestLobbyListNumericalFilter(
		"member_count",
		lobby_max_members - our_party_size,
		1  # LOBBY_COMPARISON_LESS_THAN
	)
	
	# Request the lobby list
	Steam.requestLobbyList()

func merge_parties(target_lobby: int) -> void:
	output.append_text("[STEAM] Found compatible lobby, merging parties...\n")
	
	# Store our party members
	var our_members = lobby_members.duplicate()
	
	# Leave our current lobby
	var our_old_lobby = lobby_id
	leave_lobby()
	
	# Join the target lobby
	join_lobby(target_lobby)
	
	# Set status to starting since we know this will make a full lobby
	Steam.setLobbyData(target_lobby, "game_starting", "true")
	
	# Notify all our previous party members to join
	for member in our_members:
		if member.steam_id != Global.steam_id:
			Steam.sendLobbyChatMsg(our_old_lobby, "/join_new_lobby:" + str(target_lobby))

func cancel_matchmaking() -> void:
	if not is_matchmaking:
		return
		
	is_matchmaking = false
	matchmaking_timer = 0.0
	
	# Update lobby status
	Steam.setLobbyData(lobby_id, "status", "idle")
	
	# Reset button text
	matchmaking_button.text = "Find Match"
	
	output.append_text("[STEAM] Matchmaking cancelled\n")

func matchmaking_loop() -> void:
	# If this matchmake_phase is 3 or less, keep going
	if matchmaking_phase < 4 and is_matchmaking:
		output.append_text("[STEAM] Searching in phase " + str(matchmaking_phase) + "...\n")
		
		# Set up filters
		# Set the distance filter based on phase
		Steam.addRequestLobbyListDistanceFilter(matchmaking_phase)
		
		# Filter by game mode
		var mode_text = "classic" if game_mode_selector.get_selected_id() == GAME_MODE.CLASSIC else "ranked"
		Steam.addRequestLobbyListStringFilter("mode", mode_text, Steam.LOBBY_COMPARISON_EQUAL)
		
		# Filter by status (only look for other searching lobbies)
		Steam.addRequestLobbyListStringFilter("status", "searching", Steam.LOBBY_COMPARISON_EQUAL)
		
		# Request the lobby list
		Steam.requestLobbyList()
	else:
		output.append_text("[STEAM] No matches found in any phase.\n")
		cancel_matchmaking()

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
	if is_matchmaking:
		cancel_matchmaking()
	else:
		start_party_matchmaking()

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
