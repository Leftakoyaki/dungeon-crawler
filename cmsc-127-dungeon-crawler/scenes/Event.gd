extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Event.gd — EVENT node handler
#
# Rolls one of three outcomes on enter:
#   1. +1 Upgrade Point  (40% weight)
#   2. Random potion     (40% weight, skipped if inventory full)
#   3. Nothing           (20% fallback — or when inventory full and potion rolled)
#
# Marks node cleared and shows the result. Player clicks Continue → Map.
# ─────────────────────────────────────────────────────────────────────────────

@onready var title_label:   Label  = $MarginContainer/VBoxContainer/TitleLabel
@onready var flavor_label:  Label  = $MarginContainer/VBoxContainer/FlavorLabel
@onready var result_label:  Label  = $MarginContainer/VBoxContainer/ResultLabel
@onready var continue_btn:  Button = $MarginContainer/VBoxContainer/ContinueButton

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		print("Click detected! State: ", event.pressed) # This will show up in the Output console
		GameState.update_cursor(event.pressed)
		
func _ready() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_error("Event: no active player.")
		return

	DatabaseManager.mark_node_cleared(GameState.current_node_id)

	title_label.text  = "✦  Strange Event"
	flavor_label.text = "You stumble upon something unusual in the dungeon..."

	_roll_reward()

	continue_btn.pressed.connect(_on_continue_pressed)


func _roll_reward() -> void:
	var roll: float = randf()

	if roll < 0.40:
		# Upgrade point
		DatabaseManager.add_upg_pts(1)
		result_label.text = "You found an ancient inscription.\n+1 Upgrade Point!"

	elif roll < 0.80:
		# Random potion — skip if inventory full
		if DatabaseManager.get_inventory_count() >= 3:
			result_label.text = "You find a potion, but your bag is full.\nYou leave it behind."
			return

		var pot_id: int = randi_range(1, 3)
		var added: bool = DatabaseManager.add_to_inventory(pot_id)
		if added:
			var potion: Dictionary = DatabaseManager.get_potion(pot_id)
			result_label.text = "You found a %s!" % potion.get("pot_name", "Potion")
		else:
			result_label.text = "Something was here, but it crumbled to dust."

	else:
		# Nothing
		result_label.text = "The room is empty.\nYou find nothing of use."


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
