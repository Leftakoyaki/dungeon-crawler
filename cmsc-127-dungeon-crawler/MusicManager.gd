extends Node

var player := AudioStreamPlayer.new()

var menu_music = preload("res://assets/Music/main_menuMusic.mp3")
var map_music = preload("res://assets/Music/Map music.mp3")
var normal_combat = preload("res://assets/Music/CombatMusic.mp3")
var boss_combat = preload("res://assets/Music/bossMusic.mp3")

func _ready() -> void:
	add_child(player)
	print("🎵 MusicManager Autoload is awake and running!")

func play_track(track: AudioStream, track_name: String) -> void:
	if player.stream == track and player.playing:
		print("🎵 " + track_name + " is already playing, ignoring request.")
		return
		
	player.stream = track
	player.play()
	print("🎵 Now playing: " + track_name)

func play_menu() -> void:
	play_track(menu_music, "Main Menu Music")

func play_map() -> void:
	play_track(map_music, "Map Music")

func play_combat(is_boss: bool) -> void:
	if is_boss:
		play_track(boss_combat, "Boss Combat Music")
	else:
		play_track(normal_combat, "Normal Combat Music")
