extends Control

# ─────────────────────────────────────────────────────────────────────────────
# GameOver.gd — shown after player HP hits 0 in Combat
#
# Wipes the save (delete_player) and resets GameState on scene enter.
# Only one action: return to Main Menu.
# ─────────────────────────────────────────────────────────────────────────────

@onready var title_label:  Label  = $CenterContainer/VBoxContainer/TitleLabel
@onready var sub_label:    Label  = $CenterContainer/VBoxContainer/SubLabel
@onready var menu_btn:     Button = $CenterContainer/VBoxContainer/MenuButton

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)
		
func _ready() -> void:
	# Wipe save so Continue is disabled on next visit to Main Menu
	DatabaseManager.delete_player()
	GameState.reset()

	title_label.text = "YOU DIED"
	sub_label.text   = "The dungeon claims another soul."

	menu_btn.pressed.connect(_on_menu_pressed)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
