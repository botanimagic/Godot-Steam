extends Node
#################################################
# NETWORKING GLOBAL SCRIPT
################################################

var connection_handle: int = 0
var client_channel: int = 1
var host_channel: int = 0
var voice_channel: int = 2
var connected_users: Array = []

func _ready() -> void:
	# Connect P2P session request callback
	Helper.connect_signal(Steam.p2p_session_request, _on_p2p_session_request)
	Helper.connect_signal(Steam.p2p_session_connect_fail, _on_p2p_session_connect_fail)

func send_message(message_contents, target_id: int = 0) -> void:
	if target_id == 0:
		# Broadcast to all connected users
		for user in connected_users:
			Steam.sendP2PPacket(user, message_contents, Steam.P2P_SEND_RELIABLE, voice_channel)
	else:
		# Send to specific user
		Steam.sendP2PPacket(target_id, message_contents, Steam.P2P_SEND_RELIABLE, voice_channel)

func add_connection(steam_id: int) -> void:
	if not steam_id in connected_users:
		connected_users.append(steam_id)
		Steam.acceptP2PSessionWithUser(steam_id)

func remove_connection(steam_id: int) -> void:
	if steam_id in connected_users:
		connected_users.erase(steam_id)
		Steam.closeP2PSessionWithUser(steam_id)

func _on_p2p_session_request(remote_id: int) -> void:
	# Auto-accept P2P session request from other players
	print("P2P session request from: ", remote_id)
	Steam.acceptP2PSessionWithUser(remote_id)
	if not remote_id in connected_users:
		connected_users.append(remote_id)

func _on_p2p_session_connect_fail(remote_id: int, error: int) -> void:
	print("Failed to connect to ", remote_id, " with error: ", error)
	remove_connection(remote_id)
