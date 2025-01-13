extends Node


@onready var lobby: Panel = $".."
@onready var players_vbox: VBoxContainer = $"../Frame/Main/Displays/PlayerLists/Players"
@onready var local: AudioStreamPlayer = $Local
@onready var network: AudioStreamPlayer = $Network

# Button
@onready var press_to_talk_button: Button = $"../Frame/SideBar/List/PressToTalk"
@onready var toggle_voice_button: Button = $"../Frame/SideBar/List/ToggleVoice"
@onready var loopback_button: Button = $"../Frame/SideBar/List/Loopback"
@onready var debug_button: Button = $"../Frame/SideBar/List/Debug"



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
	
	print("\n=== Initial Voice State ===")
	debug_voice_state()
	
	# Initialize Steam voice first
	Steam.stopVoiceRecording()
	await get_tree().create_timer(0.5).timeout
	
	# Initialize audio streams before starting voice
	init_audio_streams()
	
	# Start the audio players
	local.play()
	network.play()
	
	local_playback = local.get_stream_playback()
	network_playback = network.get_stream_playback()
	
	# Now start voice recording with proper sample rate
	current_sample_rate = 48000  # Force 48kHz
	Steam.startVoiceRecording()
	await get_tree().create_timer(1.0).timeout
	
	# Do a voice test
	var voice_test = await test_voice_recording()
	if not voice_test:
		print("[ERROR] Voice test failed, retrying with different sample rate...")
		current_sample_rate = 24000  # Try lower sample rate
		Steam.startVoiceRecording()
		await get_tree().create_timer(0.5).timeout
		voice_test = await test_voice_recording()
		
	print("\n=== Voice State After Initialization ===")
	debug_voice_state()
	
	update_button_states()

func disable_voice_features() -> void:
	toggle_voice_button.disabled = true
	press_to_talk_button.disabled = true
	loopback_button.disabled = true

var debug_timer: float = 0.0
const DEBUG_INTERVAL: float = 5.0  # Check every 5 seconds

func _process(delta: float) -> void:
	# Essentially checking for the local voice data then sending it to the networking
	# Plays locally if loopback is enabled
	check_for_voice()
	
	# Periodic debug output
	debug_timer += delta
	if debug_timer >= DEBUG_INTERVAL:
		debug_timer = 0.0
		if is_voice_toggled:  # Only debug when voice is active
			print("\n=== Periodic Voice State Check ===")
			debug_voice_state()



#################################################
# VOICE FUNCTIONS
#################################################
func test_voice_recording() -> bool:
	print("[VOICE] Testing voice recording...")
	
	var test_count = 0
	var max_tests = 10
	
	while test_count < max_tests:
		var voice_state = Steam.getAvailableVoice()
		if voice_state['result'] == Steam.VOICE_RESULT_OK:
			var voice_data = Steam.getVoice()
			if voice_data['result'] == Steam.VOICE_RESULT_OK:
				print("[VOICE] Test successful!")
				return true
		
		await get_tree().create_timer(0.1).timeout
		test_count += 1
	
	print("[VOICE] Test failed after", max_tests, "attempts")
	return false

func update_button_states() -> void:
	toggle_voice_button.button_pressed = is_voice_toggled
	loopback_button.button_pressed = loopback_enabled

func initialize_microphone() -> bool:
	print("[VOICE] Attempting to initialize microphone...")
	
	# Stop any existing recording
	Steam.stopVoiceRecording()
	await get_tree().create_timer(0.1).timeout
	
	# Start recording with proper sample rate
	Steam.startVoiceRecording()
	await get_tree().create_timer(0.5).timeout
	
	# Check if microphone is working
	var mic_test = Steam.getAvailableVoice()
	print("[VOICE] Microphone test result: ", mic_test)
	
	if mic_test['result'] != Steam.VOICE_RESULT_OK:
		print("[ERROR] Microphone initialization failed")
		return false
	
	# Try to get some actual voice data
	var voice_data = Steam.getVoice()
	if voice_data['result'] != Steam.VOICE_RESULT_OK:
		print("[ERROR] Failed to get voice data")
		return false
	
	print("[VOICE] Microphone initialized successfully")
	return true

# Add these helper functions
const SAMPLE_RATE: int = 48000
const BUFFER_SIZE: int = 1024

func init_audio_streams() -> void:
	# Configure local playback
	local.stream = AudioStreamGenerator.new()
	local.stream.mix_rate = SAMPLE_RATE
	local.stream.buffer_length = 0.1  # 100ms buffer
	local.volume_db = -6  # Reduce volume slightly
	
	# Configure network playback
	network.stream = AudioStreamGenerator.new()
	network.stream.mix_rate = SAMPLE_RATE
	network.stream.buffer_length = 0.1
	network.volume_db = -6

func debug_voice_setup() -> void:
	print("\n=== Voice Chat Debug ===")
	var mic_test = Steam.getAvailableVoice()
	print("mic test : ", mic_test)
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

func debug_voice_state() -> void:
	print("\n=== Voice State Debug ===")
	print("Sample rate: ", current_sample_rate)
	print("Voice enabled: ", is_voice_toggled)
	print("Loopback enabled: ", loopback_enabled)
	
	var voice_state = Steam.getAvailableVoice()
	print("Voice state: ", voice_state)
	
	if voice_state['result'] == Steam.VOICE_RESULT_OK:
		var voice_data = Steam.getVoice()
		print("Voice data size: ", voice_data['written'])
		if voice_data['written'] > 0:
			print("First bytes: ", Array(voice_data['buffer'].slice(0, 8)))
	
	print("Local playback ready: ", local_playback != null)
	print("Network playback ready: ", network_playback != null)
	print("========================\n")

#
func change_voice_status() -> void:
	print("[VOICE DEBUG] Changing voice status to: ", is_voice_toggled)
	
	if is_voice_toggled:
		Steam.startVoiceRecording()
	else:
		Steam.stopVoiceRecording()
	
	print("\n=== Voice State After Status Change ===")
	debug_voice_state()
	
	var players_lists = players_vbox.get_children()
	print("[VOICE DEBUG] Players list: ", players_lists)
	
	# Update UI
	for player in players_lists:
		if player.steam_id == Global.steam_id:
			player.mic_on.visible = is_voice_toggled
			player.mic_off.visible = !is_voice_toggled
	
	# Update Steam
	Steam.setInGameVoiceSpeaking(Global.steam_id, is_voice_toggled)
	Steam.setInGameVoiceSpeaking(Global.steam_id, is_voice_toggled)


# Update the troubleshooting function
func troubleshoot_microphone() -> void:
	print("\n=== Microphone Troubleshooting ===")
	
	# Check Steam initialization
	print("Steam running: ", Steam.isSteamRunning())
	
	# Check voice status
	var voice_status = Steam.getAvailableVoice()
	print("Voice status: ", voice_status)
	print("Voice result: ", match_voice_result(voice_status['result']))
	
	# Check sample rate
	print("Current sample rate: ", current_sample_rate)
	print("Optimal sample rate: ", Steam.getVoiceOptimalSampleRate())
	
	# Check audio devices
	print("Audio playback ready: ", local_playback != null and network_playback != null)
	
	# Add detailed voice state debug
	debug_voice_state()

# Helper function to convert voice result to string
func match_voice_result(result: int) -> String:
	match result:
		Steam.VOICE_RESULT_OK: return "OK"
		Steam.VOICE_RESULT_NOT_INITIALIZED: return "Not initialized"
		Steam.VOICE_RESULT_NOT_RECORDING: return "Not recording"
		Steam.VOICE_RESULT_NO_DATE: return "No data"
		Steam.VOICE_RESULT_BUFFER_TOO_SMALL: return "Buffer too small"
		Steam.VOICE_RESULT_DATA_CORRUPTED: return "Data corrupted"
		Steam.VOICE_RESULT_RESTRICTED: return "Restricted"
		_: return "Unknown error"


# Modify check_for_voice to include basic audio processing
func check_for_voice() -> void:
	if not is_voice_toggled:
		return
		
	var available_voice: Dictionary = Steam.getAvailableVoice()
	
	if available_voice['result'] == Steam.VOICE_RESULT_OK and available_voice['buffer'] > 0:
		var voice_data: Dictionary = Steam.getVoice()
		
		if voice_data['result'] == Steam.VOICE_RESULT_OK and voice_data['written'] > 0:
			print("[VOICE DEBUG] Voice buffer size: ", voice_data['written'])
			
			# Try to decompress the voice data
			var decompressed = Steam.decompressVoice(
				voice_data['buffer'],
				voice_data['written'],
				current_sample_rate
			)
			
			if decompressed['result'] == Steam.VOICE_RESULT_OK:
				print("[VOICE DEBUG] Successfully decompressed voice data")
				
				if loopback_enabled:
					process_audio_data(local_playback, decompressed['uncompressed'])
				
				# Send to other players
				for user_id in Networking.connected_users:
					if user_id != Global.steam_id:
						Steam.setInGameVoiceSpeaking(Global.steam_id, true)
						Networking.send_message(voice_data['buffer'], user_id)
			else:
				print("[VOICE ERROR] Failed to decompress voice data: ", decompressed['result'])
				# Try reinitializing with different sample rate
				if current_sample_rate == 48000:
					current_sample_rate = 24000
					Steam.startVoiceRecording()
				elif current_sample_rate == 24000:
					current_sample_rate = 11025
					Steam.startVoiceRecording()

func process_audio_data(playback: AudioStreamGeneratorPlayback, buffer: PackedByteArray) -> void:
	if playback.get_frames_available() <= 0:
		return
		
	# Add debug output for buffer content
	print("[VOICE DEBUG] Processing audio buffer size: ", buffer.size())
	if buffer.size() > 0:
		var sum = 0.0
		var count = 0
		
		# Convert raw PCM data to audio samples
		var frame_count = buffer.size() / 2  # 16-bit samples = 2 bytes per sample
		var frames_to_process = mini(playback.get_frames_available(), frame_count)
		
		for i in range(0, frames_to_process * 2, 2):
			if i + 1 >= buffer.size():
				break
				
			# Combine bytes into 16-bit signed PCM value
			var low_byte = buffer[i]
			var high_byte = buffer[i + 1]
			var sample_value = (high_byte << 8) | low_byte
			
			# Convert to signed 16-bit
			if sample_value > 32767:
				sample_value -= 65536
				
			# Normalize to -1.0 to 1.0 range
			var amplitude: float = float(sample_value) / 32768.0
			
			# Calculate average amplitude for debugging
			sum += abs(amplitude)
			count += 1
			
			# Optional: Apply simple noise gate
			if abs(amplitude) < 0.01:  # Adjust threshold as needed
				amplitude = 0.0
				
			# Optional: Apply soft limiting to prevent clipping
			amplitude = clamp(amplitude, -0.95, 0.95)
			
			# Push stereo frame (left and right channels)
			playback.push_frame(Vector2(amplitude, amplitude))
		
		# Print debug info about the audio
		if count > 0:
			print("[VOICE DEBUG] Average amplitude: ", sum / count)


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
# Add audio effect processing (optional)
func apply_audio_effects(buffer: PackedByteArray) -> PackedByteArray:
	var processed = PackedByteArray()
	processed.resize(buffer.size())
	
	for i in range(0, buffer.size(), 2):
		if i + 1 >= buffer.size():
			break
			
		# Get sample
		var sample = (buffer[i + 1] << 8) | buffer[i]
		if sample > 32767:
			sample -= 65536
			
		# Convert to float
		var value = float(sample) / 32768.0
		
		# Apply effects
		
		# 1. Noise gate
		if abs(value) < 0.01:
			value = 0.0
			
		# 2. Compression
		var threshold = 0.5
		var ratio = 0.7
		if abs(value) > threshold:
			var excess = abs(value) - threshold
			value = (threshold + excess * ratio) * sign(value)
			
		# 3. Soft clipping
		value = clamp(value, -0.95, 0.95)
		
		# Convert back to 16-bit PCM
		sample = int(value * 32768.0)
		if sample < 0:
			sample += 65536
			
		# Store processed sample
		processed[i] = sample & 0xFF
		processed[i + 1] = (sample >> 8) & 0xFF
	
	return processed


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
	if voice_data['written'] <= 0 or not voice_data['buffer']:
		print("[VOICE DEBUG] Invalid voice data received")
		return
		
	print("[VOICE DEBUG] Attempting to play voice data of size: ", voice_data['written'])
	
	# Try decompressing with different sample rates if first attempt fails
	var sample_rates = [48000, 24000, 11025]
	var decompressed_voice: Dictionary
	
	for rate in sample_rates:
		decompressed_voice = Steam.decompressVoice(
			voice_data['buffer'],
			voice_data['written'],
			rate
		)
		
		if decompressed_voice['result'] == Steam.VOICE_RESULT_OK:
			print("[VOICE DEBUG] Successfully decompressed with sample rate: ", rate)
			current_sample_rate = rate  # Update to working sample rate
			break
		else:
			print("[VOICE DEBUG] Failed to decompress with sample rate: ", rate)
	
	if decompressed_voice['result'] != Steam.VOICE_RESULT_OK:
		print("[VOICE ERROR] Failed to decompress with any sample rate")
		return
	
	# Process the audio
	process_audio_data(network_playback, decompressed_voice['uncompressed'])
	
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
	debug_button.connect("pressed", _on_debug_voice_pressed)

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

#
func _on_debug_voice_pressed() -> void:
	print("\n=== Manual Voice Debug ===")
	debug_voice_state()
	
	print("\nTesting voice recording...")
	Steam.stopVoiceRecording()
	await get_tree().create_timer(0.2).timeout
	Steam.startVoiceRecording()
	
	await get_tree().create_timer(0.5).timeout
	var voice_test = Steam.getAvailableVoice()
	print("Voice test result: ", voice_test)
	
	if voice_test['result'] == Steam.VOICE_RESULT_OK:
		var voice_data = Steam.getVoice()
		print("Voice data: ", voice_data)
