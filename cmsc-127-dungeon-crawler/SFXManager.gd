extends Node

const SFX_DIR = "res://assets/SFX/"

# Plays a sound and returns the AudioStreamPlayer instance so it can be manually stopped
func play_skill_sfx(sfx_name: String) -> AudioStreamPlayer:
	var path = SFX_DIR + sfx_name + ".mp3"
	
	if not ResourceLoader.exists(path):
		push_error("SFX file not found at path: " + path)
		return null
		
	var stream = load(path)
	var player = AudioStreamPlayer.new()
	player.stream = stream
	# player.bus = "SFX" # Optional: assign to an SFX audio bus if you have one
	add_child(player)
	player.play()
	
	# Clean up automatically if the sound completes fully on its own
	player.finished.connect(player.queue_free)
	
	return player


# Remove ": AudioStreamPlayer" so Godot allows a freed object to be passed in
func stop_sfx(player) -> void:
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
