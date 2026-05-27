extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Rest.gd — REST node handler
#
# Two choices:
#   Tend the Campfire — heals HP to max
#   Forge             — grants +2 upgrade points
#
# Node is marked cleared after either choice.
# ─────────────────────────────────────────────────────────────────────────────

const FORGE_POINTS: int = 2

@onready var title_label:  Label  = $MarginContainer/VBoxContainer/TitleLabel
@onready var heal_label:   Label  = $MarginContainer/VBoxContainer/HealLabel
@onready var hp_label:     Label  = $MarginContainer/VBoxContainer/HPLabel
@onready var continue_btn: Button = $MarginContainer/VBoxContainer/ContinueButton

# New buttons — add these to your scene under VBoxContainer
@onready var campfire_btn: Button = $MarginContainer/VBoxContainer/CampfireButton
@onready var forge_btn:    Button = $MarginContainer/VBoxContainer/ForgeButton


func _ready() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_error("Rest: no active player.")
		return

	var old_hp: int = int(player["current_hp"])
	var max_hp: int = int(player["max_hp"])
	var healed: int = max_hp - old_hp

	title_label.text = "⛺  Rest Site"
	heal_label.text  = "HP: %d / %d     UPG: %d" % [old_hp, max_hp, player["upg_pts_bank"]]
	hp_label.text    = "What will you do?"

	campfire_btn.text = "Tend the Campfire  (+%d HP)" % healed if healed > 0 else "Tend the Campfire  (Already full)"
	forge_btn.text    = "Forge  (+%d Upgrade Points)" % FORGE_POINTS

	continue_btn.hide()

	campfire_btn.pressed.connect(_on_campfire_pressed)
	forge_btn.pressed.connect(_on_forge_pressed)


func _on_campfire_pressed() -> void:
	campfire_btn.disabled = true
	forge_btn.disabled    = true

	var player: Dictionary = DatabaseManager.get_player()
	var old_hp: int = int(player["current_hp"])
	var max_hp: int = int(player["max_hp"])
	var healed: int = max_hp - old_hp

	DatabaseManager.update_player_hp(max_hp)
	DatabaseManager.mark_node_cleared(GameState.current_node_id)

	if healed > 0:
		heal_label.text = "You rest by the fire and recover +%d HP." % healed
	else:
		heal_label.text = "You are already at full health."

	hp_label.text = "HP: %d / %d" % [max_hp, max_hp]
	continue_btn.show()
	continue_btn.pressed.connect(_on_continue_pressed)


func _on_forge_pressed() -> void:
	campfire_btn.disabled = true
	forge_btn.disabled    = true

	DatabaseManager.add_upg_pts(FORGE_POINTS)
	DatabaseManager.mark_node_cleared(GameState.current_node_id)

	var player: Dictionary = DatabaseManager.get_player()
	heal_label.text = "You sharpen your skills at the forge."
	hp_label.text   = "UPG: %d  (+%d)" % [player["upg_pts_bank"], FORGE_POINTS]
	continue_btn.show()
	continue_btn.pressed.connect(_on_continue_pressed)


func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
