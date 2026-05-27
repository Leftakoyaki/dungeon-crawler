extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Rest.gd — REST node handler
#
# On enter: restore player HP to max, mark node cleared.
# Player sees HP before/after, then clicks Continue to return to Map.
# ─────────────────────────────────────────────────────────────────────────────

@onready var title_label:    Label  = $MarginContainer/VBoxContainer/TitleLabel
@onready var heal_label:     Label  = $MarginContainer/VBoxContainer/HealLabel
@onready var hp_label:       Label  = $MarginContainer/VBoxContainer/HPLabel
@onready var continue_btn:   Button = $MarginContainer/VBoxContainer/ContinueButton


func _ready() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_error("Rest: no active player.")
		return

	var old_hp: int = int(player["current_hp"])
	var max_hp: int = int(player["max_hp"])
	var healed: int = max_hp - old_hp

	# Restore HP
	DatabaseManager.update_player_hp(max_hp)
	DatabaseManager.mark_node_cleared(GameState.current_node_id)

	# Update UI
	title_label.text = "⛺  Rest Site"
	if healed > 0:
		heal_label.text = "You rest and recover +%d HP." % healed
	else:
		heal_label.text = "You are already at full health."
	hp_label.text = "HP: %d / %d" % [max_hp, max_hp]

	continue_btn.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
