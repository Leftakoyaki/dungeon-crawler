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
	# Run is complete — wipe save
	DatabaseManager.delete_player()
	GameState.reset()

	title_label.text = "YOU WIN!"
	sub_label.text   = "The dragon is slain. The dungeon is cleared."

	menu_btn.pressed.connect(_on_menu_pressed)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
