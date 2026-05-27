extends Control

@onready var new_game_btn:  Button = $CenterContainer/VBoxContainer/NewGameButton
@onready var continue_btn:  Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var quit_btn:      Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	# Disable Continue if no active save exists
	continue_btn.disabled = DatabaseManager.get_player().is_empty()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ClassSelect.tscn")


func _on_continue_pressed() -> void:
	GameState.sync_from_db()
	get_tree().change_scene_to_file("res://scenes/Map.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
