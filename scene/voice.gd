extends Node


@onready var lobby: Panel = $".."
@onready var players_vbox: VBoxContainer = $"../Frame/Main/Displays/PlayerLists/Players"
@onready var local: AudioStreamPlayer = $Local
@onready var network: AudioStreamPlayer = $Network

# Button
@onready var press_to_talk_button: Button = $"../Frame/SideBar/List/PressToTalk"
@onready var toggle_voice_button: Button = $"../Frame/SideBar/List/ToggleVoice"
@onready var loopback_button: Button = $"../Frame/SideBar/List/Loopback"


var current_sample_rate: int = 48000
var loopback_enabled: bool = false
var is_voice_toggled: bool = false
var use_optimal_sample_rate: bool = false
var local_playback: AudioStreamGeneratorPlayback = null
var local_voice_buffer: PackedByteArray = PackedByteArray()
var network_playback: AudioStreamGeneratorPlayback = null
var network_voice_buffer: PackedByteArray = PackedByteArray()
var packet_read_limit: int = 5


func _ready() -> void:
	# Buttons Connections
	buttons_signal_connections()
	
	# Initialize local voice playback
	local.stream.mix_rate = current_sample_rate
	local.play()
	local_playback = local.get_stream_playback()
	
	# Initialize network voice playback
	network.stream.mix_rate = current_sample_rate
	network.play()
	network_playback = network.get_stream_playback()

	await get_tree().create_timer(2.0).timeout  # Wait for everything to initialize
	debug_voice_setup()
	update_button_states()


func _process(_delta: float) -> void:
	# Essentially checking for the local voice data then sending it to the networking
	# Plays locally if loopback is enabled
	check_for_voice()



#################################################
# VOICE FUNCTIONS
#################################################
func update_button_states() -> void:
	toggle_voice_button.button_pressed = is_voice_toggled
	loopback_button.button_pressed = loopback_enabled


func debug_voice_setup() -> void:
	print("\n=== Voice Chat Debug ===")
	var mic_test = Steam.getAvailableVoice()
	if mic_test['result'] != Steam.VOICE_RESULT_OK:
		print("[ERROR] Microphone not available or not properly initialized")
		match mic_test['result']:
			1: print("OK")
			2: print("Not initialized")
			3: print("No data available")
			4: print("Buffer too small")
			_: print("Unknown error")
	else:
		print("[OK] Microphone initialized successfully")

#
func change_voice_status() -> void:
	if is_voice_toggled:
		# Try to initialize voice recording
		Steam.startVoiceRecording()
		var test = Steam.getAvailableVoice()
		if test['result'] != Steam.VOICE_RESULT_OK:
			print("[ERROR] Failed to start voice recording")
			is_voice_toggled = false
			return
	else:
		Steam.stopVoiceRecording()
	
	# Update UI
	var players_lists = players_vbox.get_children()
	for player in players_lists:
		if player.steam_id == Global.steam_id:
			player.mic_on.visible = is_voice_toggled
			player.mic_off.visible = !is_voice_toggled
	
	# Update Steam
	Steam.setInGameVoiceSpeaking(Global.steam_id, is_voice_toggled)

#
func check_for_voice() -> void:
	var available_voice: Dictionary = Steam.getAvailableVoice()
	
	if available_voice['result'] == Steam.VOICE_RESULT_OK and available_voice['buffer'] > 0:
		var voice_data: Dictionary = Steam.getVoice()
		
		if voice_data['result'] == Steam.VOICE_RESULT_OK and voice_data['written'] > 0:
			# Check if we're getting actual voice data (not just static)
			var is_valid_audio = false
			var buffer = voice_data['buffer']
			for i in range(min(10, buffer.size())):
				if buffer[i] != buffer[0]:
					is_valid_audio = true
					break
			
			if is_valid_audio:
				print("[VOICE] Valid voice data detected")
				if loopback_enabled:
					process_audio_data(local_playback, voice_data['buffer'])
				
				# Send to other players
				for user_id in Networking.connected_users:
					print("[VOICE] Sending voice to user: ", user_id)
					Networking.send_message(voice_data['buffer'], user_id)
			else:
				print("[VOICE] Skipping static/noise data")

func process_audio_data(playback: AudioStreamGeneratorPlayback, buffer: PackedByteArray) -> void:
	if playback.get_frames_available() <= 0:
		return
		
	print("[VOICE DEBUG] Processing audio data of size: ", buffer.size())
	
	for i in range(0, mini(playback.get_frames_available() * 2, buffer.size()), 2):
		if i + 1 >= buffer.size():
			break
			
		# Convert the bytes to audio samples
		var sample: float = float(buffer[i] | (buffer[i + 1] << 8)) / 32768.0
		playback.push_frame(Vector2(sample, sample))

#func play_network_voice(voice_data: Dictionary) -> void:
	#if voice_data['written'] <= 0 or not voice_data['buffer']:
		#return
		#
	#var decompressed_voice: Dictionary = Steam.decompressVoice(
		#voice_data['buffer'],
		#voice_data['written'],
		#current_sample_rate
	#)
	#
	#if decompressed_voice['result'] == Steam.VOICE_RESULT_OK:
		#network_voice_buffer = decompressed_voice['uncompressed']
		#process_audio_data(network_playback, network_voice_buffer)

#
func get_sample_rate() -> void:
	var optimal_sample_rate: int = Steam.getVoiceOptimalSampleRate()
	# SpaceWar uses 11000 for sample rate?!
	# If are using Steam's "optimal" rate, set it; otherwise we default to 48000
	if use_optimal_sample_rate:
		current_sample_rate = optimal_sample_rate
	else:
		current_sample_rate = 48000
	print("Current sample rate: "+str(current_sample_rate))

# A network voice packet exists, process it
func play_network_voice(voice_data: Dictionary) -> void:
	print("[VOICE DEBUG] Received network voice data: ", voice_data)  # Debug output
	
	# Skip if the voice data is empty or invalid
	if voice_data['written'] <= 0 or not voice_data['buffer']:
		print("[VOICE DEBUG] Invalid voice data received")
		return
		
	# Process the network voice data
	var decompressed_voice: Dictionary = Steam.decompressVoice(
		voice_data['buffer'],
		voice_data['written'],
		current_sample_rate
	)
	
	print("[VOICE DEBUG] Decompressed voice data: ", decompressed_voice)  # Debug output
	
	if decompressed_voice['result'] != Steam.VOICE_RESULT_OK or decompressed_voice['size'] == 0:
		return
	
	if network_playback.get_frames_available() <= 0:
		return
	
	# Prepare the voice buffer
	network_voice_buffer = decompressed_voice['uncompressed']
	network_voice_buffer.resize(decompressed_voice['size'])
	
	# Process and play the audio frames
	for i in range(0, mini(network_playback.get_frames_available() * 2, network_voice_buffer.size()), 2):
		# Combine the low and high bits to get full 16-bit value
		var raw_value: int = network_voice_buffer[i] | (network_voice_buffer[i + 1] << 8)
		# Make it a 16-bit signed integer
		raw_value = (raw_value + 32768) & 0xffff
		# Convert the 16-bit integer to a float from -1 to 1
		var amplitude: float = float(raw_value - 32768) / 32768.0
		network_playback.push_frame(Vector2(amplitude, amplitude))

#################################################
# BUTTON HANDLING
#################################################

#
func buttons_signal_connections():
	press_to_talk_button.connect("button_down", _on_press_to_talk_button_down)
	press_to_talk_button.connect("button_up", _on_press_to_talk_button_up)
	toggle_voice_button.connect("pressed", _on_toggle_voice_pressed)
	loopback_button.connect("pressed", _on_loopback_pressed)

#
func _on_press_to_talk_button_down():
	print("press to talk button down")
	is_voice_toggled = true
	change_voice_status()

#
func _on_press_to_talk_button_up():
	print("press to talk button up")
	is_voice_toggled = false
	change_voice_status()

#
func _on_toggle_voice_pressed():
	print("toggle voice pressed")
	is_voice_toggled = !is_voice_toggled
	print("Toggling voice chat: "+str(is_voice_toggled))
	change_voice_status()

#
func _on_loopback_pressed():
	print("loopback pressed")
	loopback_enabled = !loopback_enabled
	print("Loopback enabled: "+str(loopback_enabled))
	
	var players_lists = players_vbox.get_children()
	print("players lists : ", players_lists)
	
	for player in players_lists :
		if player.steam_id == Global.steam_id :
			player.loopback.set_visible(loopback_enabled)
