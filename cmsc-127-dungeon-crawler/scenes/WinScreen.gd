extends Control

# ─────────────────────────────────────────────────────────────────────────────
# WinScreen.gd — shown after BOSS is defeated in Combat
#
# Wipes the save and resets GameState on scene enter (run is complete).
# Only one action: return to Main Menu.
# ─────────────────────────────────────────────────────────────────────────────

@onready var title_label:  Label  = $CenterContainer/VBoxContainer/TitleLabel
@onready var sub_label:    Label  = $CenterContainer/VBoxContainer/SubLabel
@onready var menu_btn:     Button = $CenterContainer/VBoxContainer/MenuButton

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)

func _ready() -> void:
	# Shift the music back to the menu theme to signal the end of the run
	MusicManager.play_menu()
	
	# --- ADDED: Play the triumphant win SFX! ---
	MusicManager.play_win()
	
	# Run is complete — wipe save
	DatabaseManager.delete_player()
	GameState.reset()

	title_label.text = "YOU WIN!"
	sub_label.text   = "The dragon is slain. The dungeon is cleared."

	menu_btn.pressed.connect(_on_menu_pressed)
	
	_connect_click_sound(menu_btn)

# Helper function to trigger click SFX
func _connect_click_sound(btn: BaseButton) -> void:
	btn.button_down.connect(func(): MusicManager.play_click())

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
