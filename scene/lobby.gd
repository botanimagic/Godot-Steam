extends Panel

enum LOBBY_AVAILABILITY { PRIVATE, FRIENDS, PUBLIC, INVISIBLE }

@onready var lobby_member_scene = preload("res://scene/lobby_member.tscn")

@onready var output: RichTextLabel = $Frame/Main/Displays/Outputs/Output
@onready var label_lobby_id: Label = $Frame/Main/Displays/Outputs/Titles/LobbyID

@onready var create_lobby_button: Button = $Frame/SideBar/List/CreateLobby
@onready var get_lobby_data_button: Button = $Frame/SideBar/List/GetLobbyData
@onready var leave_button: Button = $Frame/SideBar/List/Leave
@onready var send_button: Button = $Frame/Main/Messaging/Send

@onready var chat_input: LineEdit = $Frame/Main/Messaging/Chat

@onready var player_list_title: Label = $Frame/Main/Displays/PlayerLists/Title
@onready var player_list_vbox: VBoxContainer = $Frame/Main/Displays/PlayerLists/Players


@onready var lobbies_panel: Panel = $Lobbies
@onready var button_lobbies_refresh: Button = $Lobbies/Refresh
@onready var close_lobbies: Button = $Lobbies/CloseLobbies
@onready var lobbies_list_vbox: VBoxContainer = $Lobbies/ScrollContainer/List


var lobby_id: int = 0
var lobby_members: Array = []
var lobby_max_members: int = 10


func _ready() -> void:
	# Buttons Connections
	buttons_signal_connections()
	
	Helper.connect_signal(Steam.lobby_created, _on_lobby_created)


func _process(_delta: float) -> void:
	# Get packets only if lobby is joined
	if lobby_id > 0:
		read_p2p_packet()

# Send the message by pressing enter
func _input(ev: InputEvent) -> void:
	if ev.is_pressed() and !ev.is_echo() and ev.is_action("chat_send"):
		_on_send_chat_pressed()


#################################################
# LOBBY FUNCTIONS
#################################################
# Creating a lobby
func _on_create_lobby() -> void:
	# Attempt to create a lobby
	create_lobby()
	output.append_text("[STEAM] Attempt to create a new lobby...\n")
	# Disable the create lobby button
	create_lobby_button.set_disabled(true)


# Getting associated metadata for the lobby
func _on_get_lobby_data_pressed() -> void:
	var data
	data = Steam.getLobbyData(lobby_id, "name")
	output.append_text("[STEAM] Lobby data, name: "+str(data)+"\n")
	data = Steam.getLobbyData(lobby_id, "mode")
	output.append_text("[STEAM] Lobby data, mode: "+str(data)+"\n")


# When the user starts a game with multiplayer enabled
func create_lobby() -> void:
	# Make sure a lobby is not already set
	if lobby_id == 0:
		# Set the lobby to public with ten members max
		Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, lobby_max_members)


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


func _on_lobby_kick_pressed(kick_id: int) -> void:
	# Pass the kick message to Steam
	var IS_SENT: bool = Steam.sendLobbyChatMsg(lobby_id, "/kick:"+str(kick_id))
	# Was it send successfully?
	if not IS_SENT:
		print("[ERROR] Kick command failed to send.\n")


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
		# Enable the create lobby button
		create_lobby_button.set_disabled(false)
		# Disable the leave lobby button and all test buttons
		change_button_states(true)


# Get the lobby members from Steam
func get_lobby_members() -> void:
	# Clear your previous lobby list
	lobby_members.clear()
	# Clear the original player list
	for MEMBER in $Frame/Main/Displays/PlayerList/Players.get_children():
		MEMBER.hide()
		MEMBER.queue_free()
	# Get the number of members from this lobby from Steam
	var MEMBERS: int = Steam.getNumLobbyMembers(lobby_id)
	# Update the player list title
	$Frame/Main/Displays/PlayerList/Title.set_text("Player List ("+str(MEMBERS)+")")
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
# P2P NETWORKING FUNCTIONS
#################################################

# Make a Steam P2P handshake so the other users get our details
func make_p2p_handshake() -> void:
	output.append_text("[STEAM] Sending P2P handshake to the lobby...\n")
	send_p2p_packet(0, {"message":"handshake", "from":Global.steam_id})


# Send test packet information
func send_test_info() -> void:
	output.append_text("[STEAM] Sending test packet data...\n")
	var TEST_DATA: Dictionary = {"title":"This is a test packet", "player_id":Global.steam_id, "player_hp":"5", "player_coord":"56,40"}
	send_p2p_packet(0, TEST_DATA)


func read_p2p_packet() -> void:
	var PACKET_SIZE: int = Steam.getAvailableP2PPacketSize(0)
	# There is a packet
	if PACKET_SIZE > 0:
		print("[STEAM] There is a packet available.")
		# Get the packet
		var PACKET: Dictionary = Steam.readP2PPacket(PACKET_SIZE, 0)
		# If it is empty, set a warning
		if PACKET.is_empty():
			print("[WARNING] Read an empty packet with non-zero size!")
		# Get the remote user's ID
		var PACKET_SENDER: String = str(PACKET['steam_id_remote'])
		var PACKET_CODE: PackedByteArray = PACKET['data']
		# Make the packet data readable
		var READABLE: Dictionary = bytes_to_var(PACKET_CODE)
		# Print the packet to output
		output.append_text("[STEAM] Packet from "+str(PACKET_SENDER)+": "+str(READABLE)+"\n")
		# Append logic here to deal with packet data
		if READABLE['message'] == "start":
			output.append_text("[STEAM] Starting P2P game...\n")


func send_p2p_packet(target: int, packet_data: Dictionary) -> void:
	# Set the send_type and channel
	var SEND_TYPE: int = Steam.P2P_SEND_RELIABLE
	var CHANNEL: int = 0
	# Create a data array to send the data through
	var PACKET_DATA: PackedByteArray = []
	PACKET_DATA.append_array(var_to_bytes(packet_data))
	# If sending a packet to everyone
	var SEND_RESPONSE: bool
	if target == 0:
		# If there is more than one user, send packets
		if lobby_members.size() > 1:
			# Loop through all members that aren't you
			for MEMBER in lobby_members:
				if MEMBER['steam_id'] != Global.steam_id:
					SEND_RESPONSE = Steam.sendP2PPacket(MEMBER['steam_id'], PACKET_DATA, SEND_TYPE, CHANNEL)
	# Else send the packet to a particular user
	else:
		# Send this packet
		SEND_RESPONSE = Steam.sendP2PPacket(target, PACKET_DATA, SEND_TYPE, CHANNEL)
	# The packets send response is...?
	output.append_text("[STEAM] P2P packet sent successfully? "+str(SEND_RESPONSE)+"\n")


#################################################
# LOBBY BROWSER
#################################################

# Open the lobby list
func _on_open_lobby_list_pressed() -> void:
	lobbies_panel.show()
	# Set distance to worldwide
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	# Request the list
	output.append_text("[STEAM] Requesting a lobby list...\n")
	Steam.requestLobbyList()


# Refresh the lobby list
func _on_refresh_pressed() -> void:
	# Clear all previous server entries
	for server in lobbies_list_vbox.get_children():
		server.free()
	# Disable the refresh button
	button_lobbies_refresh.set_disabled(true)
	# Set distance to world (or maybe change this option)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	# Request a new server list
	Steam.requestLobbyList()


#################################################
# LOBBY CHAT
#################################################


# Send a chat message
func _on_send_chat_pressed() -> void:
	# Get the entered chat message
	var MESSAGE: String = $Frame/Main/Messaging/Chat.get_text()
	# If there is even a message
	if MESSAGE.length() > 0:
		# Pass the message to Steam
		var IS_SENT: bool = Steam.sendLobbyChatMsg(lobby_id, MESSAGE)
		# Was it sent successfully?
		if not IS_SENT:
			output.append_text("[ERROR] Chat message '"+str(MESSAGE)+"' failed to send.\n")
		# Clear the chat input
		$Frame/Main/Messaging/Chat.clear()


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
			# Print the outpubt before showing the message
			print(str(SENDER)+" says: "+str(message))
			output.append_text(str(SENDER)+" says '"+str(message)+"'\n")
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

		# Set some lobby data
		var SET_LOBBY_DATA: bool = false
		SET_LOBBY_DATA = Steam.setLobbyData(lobby_id, "name", str(Global.steam_username)+"'s Lobby")
		print("[STEAM] Setting lobby name data successful: "+str(SET_LOBBY_DATA))
		SET_LOBBY_DATA = Steam.setLobbyData(lobby_id, "mode", "GodotSteam test")
		print("[STEAM] Setting lobby mode data successful: "+str(SET_LOBBY_DATA))

		# Allow P2P connections to fallback to being relayed through Steam if needed
		var IS_RELAY: bool = Steam.allowP2PPacketRelay(true)
		output.append_text("[STEAM] Allowing Steam to be relay backup: "+str(IS_RELAY)+"\n")

		# Enable the leave lobby button and all testing buttons
		change_button_states(false)
	else:
		output.append_text("[STEAM] Failed to create lobby\n")

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
	Helper.connect_signal(lobby_member.kick_player, _on_lobby_kick_pressed)
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


# =====================================
# ===== BUTTONS SIGNAL FUNCTIONS  =====
# =====================================
#
func buttons_signal_connections():
	create_lobby_button.connect("pressed", _on_create_lobby_pressed)
	#start_game_button.connect("pressed", _on_start_game_pressed)
	leave_button.connect("pressed", _on_leave_lobby_pressed)
	send_button.connect("pressed", _on_send_message_pressed)
	close_lobbies.connect("pressed", _on_close_lobbies_pressed)

#
func _on_create_lobby_pressed():
	print("create lobby")
	create_lobby()

func _on_leave_lobby_pressed():
	print("leave lobby pressed")
	leave_lobby()

func _on_send_message_pressed():
	print("send message pressed")
	_on_send_chat_pressed()

func _on_close_lobbies_pressed():
	print("close lobbies pressed")
	lobbies_panel.hide()
