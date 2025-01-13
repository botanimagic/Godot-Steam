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
	
	local.stream.mix_rate = current_sample_rate
	local.play()
	local_playback = local.get_stream_playback()


func _process(_delta: float) -> void:
	# Essentially checking for the local voice data then sending it to the networking
	# Plays locally if loopback is enabled
	check_for_voice()



#################################################
# VOICE FUNCTIONS
#################################################

#
func change_voice_status() -> void:
	var players_lists = players_vbox.get_children()
	print("players lists : ", players_lists)
	
	for player in players_lists :
		if player.steam_id == Global.steam_id :
			player.mic_on.set_visible(is_voice_toggled)
			player.mic_off.set_visible(!is_voice_toggled)
	
	# Let Steam know that the user is currently using voice chat in game. 
	# This will suppress the microphone for all voice communication in the Steam UI.
	Steam.setInGameVoiceSpeaking(Global.steam_id, is_voice_toggled)

	if is_voice_toggled:
		Steam.startVoiceRecording()
	else:
		Steam.stopVoiceRecording()

#
func check_for_voice() -> void:
	var available_voice: Dictionary = Steam.getAvailableVoice()
	if available_voice['result'] == Steam.VOICE_RESULT_OK and available_voice['buffer'] > 0:
		print("Voice message found")
		# Valve's getVoice uses 1024 but GodotSteam's is set at 8192?
		# Our sizes might be way off; internal GodotSteam notes that Valve suggests 8kb
		# However, this is not mentioned in the header nor the SpaceWar example but -is- in Valve's docs which are usually wrong
		var voice_data: Dictionary = Steam.getVoice()
		if voice_data['result'] == Steam.VOICE_RESULT_OK and voice_data['written']:
			print("Voice message has data: "+str(voice_data['result'])+" / "+str(voice_data['written']))
			Networking.send_message(voice_data['buffer'])
			# If loopback is enable, play it back at this point
			if loopback_enabled:
				print("Loopback on")
				process_voice_data(voice_data, "local")

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
	process_voice_data(voice_data, "remote")

#
func process_voice_data(voice_data: Dictionary, voice_source: String) -> void:
	get_sample_rate()
	
	var decompressed_voice: Dictionary = Steam.decompressVoice(
			voice_data['buffer'], 
			voice_data['written'], 
			current_sample_rate)
			
	if (
			not decompressed_voice['result'] == Steam.VOICE_RESULT_OK
			or decompressed_voice['size'] == 0
			or not voice_source == "local"
	):
		return
	
	if local_playback.get_frames_available() <= 0:
		return
	
	local_voice_buffer = decompressed_voice['uncompressed']
	local_voice_buffer.resize(decompressed_voice['size'])
	
	for i: int in range(0, mini(local_playback.get_frames_available() * 2, local_voice_buffer.size()), 2):
		# Combine the low and high bits to get full 16-bit value
		var raw_value: int = local_voice_buffer[0] | (local_voice_buffer[1] << 8)
		# Make it a 16-bit signed integer
		raw_value = (raw_value + 32768) & 0xffff
		# Convert the 16-bit integer to a float on from -1 to 1
		var amplitude: float = float(raw_value - 32768) / 32768.0
		local_playback.push_frame(Vector2(amplitude, amplitude))
		local_voice_buffer.remove_at(0)
		local_voice_buffer.remove_at(0)

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