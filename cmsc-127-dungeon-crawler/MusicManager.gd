extends Node

var player := AudioStreamPlayer.new()

# --- SFX Players ---
var click_player := AudioStreamPlayer.new()
var death_player := AudioStreamPlayer.new()
var scrape_player := AudioStreamPlayer.new()
var win_player := AudioStreamPlayer.new()
var combat_click_player := AudioStreamPlayer.new() # <-- New Combat Click Player

var menu_music = preload("res://assets/Music/main_menuMusic.mp3")
var map_music = preload("res://assets/Music/Map music.mp3")
var normal_combat = preload("res://assets/Music/CombatMusic.mp3")
var boss_combat = preload("res://assets/Music/bossMusic.mp3")

# --- SFX Tracks ---
var click_sfx = preload("res://assets/Music/clicksounds.mp3")
var death_sfx = preload("res://assets/Music/DeathSound.mp3")
var scrape_sfx = preload("res://assets/Music/swordscrape.mp3")
var win_sfx = preload("res://assets/Music/YouWin.mp3")
var combat_click_sfx = preload("res://assets/Music/combatclick.mp3") # <-- New Track

func _ready() -> void:
	# Add Music player
	add_child(player)
	
	# Add SFX players and assign their sounds
	add_child(click_player)
	click_player.stream = click_sfx
	
	add_child(death_player)
	death_player.stream = death_sfx
	
	add_child(scrape_player)
	scrape_player.stream = scrape_sfx
	
	add_child(win_player)
	win_player.stream = win_sfx
	
	# Wire up the new Combat Click player
	add_child(combat_click_player)
	combat_click_player.stream = combat_click_sfx
	
	print("🎵 MusicManager and SFX Autoload is awake and running!")

# --- Background Music Functions ---
func play_track(track: AudioStream, track_name: String) -> void:
	if player.stream == track and player.playing:
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

# --- SFX Functions ---
func play_click() -> void:
	click_player.play()

func play_death() -> void:
	death_player.play()

func start_scrape() -> void:
	if not scrape_player.playing:
		scrape_player.play()

func stop_scrape() -> void:
	scrape_player.stop()

func play_win() -> void:
	win_player.play()

# <-- New Combat Click Function
func play_combat_click() -> void:
	combat_click_player.play()
