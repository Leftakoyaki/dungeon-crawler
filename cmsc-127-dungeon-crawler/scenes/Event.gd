extends Control

# event node handler that rolls outcomes on enter
# 1. +1 upg point (40%)
# 2. random pot (40%, skipped if full)
# 3. nothing (20%)

@onready var title_label:  Label  = $MarginContainer/VBoxContainer/TitleLabel
@onready var flavor_label: Label  = $MarginContainer/VBoxContainer/FlavorLabel
@onready var result_label: Label  = $MarginContainer/VBoxContainer/ResultLabel
@onready var continue_btn: Button = $MarginContainer/VBoxContainer/ContinueButton

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)
		
func _ready() -> void:
	#keep map music playing smoothly
	MusicManager.play_map()
	
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_error("Event: no active player.")
		return

	DatabaseManager.mark_node_cleared(GameState.current_node_id)

	title_label.text  = "✦  Strange Event"
	flavor_label.text = "You stumble upon something unusual in the dungeon..."

	_roll_reward()

	continue_btn.pressed.connect(_on_continue_pressed)
	
	#add click sound to button
	_connect_click_sound(continue_btn)

#helper for clicks
func _connect_click_sound(btn: BaseButton) -> void:
	btn.button_down.connect(func(): MusicManager.play_click())

func _roll_reward() -> void:
	var roll: float = randf()

	if roll < 0.40:
		#upgrade point
		DatabaseManager.add_upg_pts(1)
		result_label.text = "You found an ancient inscription.\n+1 Upgrade Point!"

	elif roll < 0.80:
		#random potion skip if full
		if DatabaseManager.get_inventory_count() >= 3:
			result_label.text = "You find a potion, but your bag is full.\nYou leave it behind."
			return

		var pot_id: int = randi_range(1, 3)
		var result := DatabaseManager.add_to_inventory(pot_id)
		if result["success"]:
			var potion: Dictionary = DatabaseManager.get_potion(pot_id)
			result_label.text = "You found a %s!" % potion.get("pot_name", "Potion")
		else:
			result_label.text = "Something was here, but it crumbled to dust."

	else:
		#nothing
		result_label.text = "The room is empty.\nYou find nothing of use."


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
