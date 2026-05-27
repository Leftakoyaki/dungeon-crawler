extends Control

# ─────────────────────────────────────────────────────────────────────────────
# UpgradeScreen.gd — Phase 4
# ─────────────────────────────────────────────────────────────────────────────

@onready var pts_label:    Label         = $MarginContainer/VBoxContainer/PtsLabel
@onready var skill_list:   VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SkillList
@onready var back_btn:     Button        = $MarginContainer/VBoxContainer/BackButton

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)

func _get_max_tier(skill_id: int) -> int:
	# Skill IDs 1, 4, 7 are the NORMAL attacks, capped at Tier 1
	if skill_id in [1, 4, 7]:
		return 1
	return 3

func _ready() -> void:
	back_btn.pressed.connect(_on_back_pressed)
	_refresh()

func _refresh() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_error("UpgradeScreen: no active player.")
		return

	pts_label.text = "Upgrade Points: %d" % player["upg_pts_bank"]

	# Clear old rows
	for child in skill_list.get_children():
		child.queue_free()

	var skills := DatabaseManager.get_player_skills()
	for skill in skills:
		_build_skill_row(skill, int(player["upg_pts_bank"]))

func _build_skill_row(skill: Dictionary, upg_pts: int) -> void:
	var current_tier: int = int(skill["current_tier"])
	var max_tier: int     = _get_max_tier(int(skill["skill_id"]))
	var is_maxed: bool    = current_tier >= max_tier

	var next_data: Dictionary = {}
	if not is_maxed:
		next_data = DatabaseManager.get_skill_upgrade(int(skill["skill_id"]), current_tier + 1)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if is_maxed:
		info.text = "%s  [%s]\nTier %d  SP:%d  x%.1f  ← MAX" % [
			skill["skill_name"], skill["atk_type"], current_tier, skill["sp_cost"], skill["dmg_multiplier"]
		]
	else:
		info.text = "%s  [%s]\nTier %d → %d  |  SP:%d  x%.1f  →  SP:%d  x%.1f" % [
			skill["skill_name"], skill["atk_type"], current_tier, current_tier + 1,
			skill["sp_cost"], skill["dmg_multiplier"],
			next_data.get("sp_cost", skill["sp_cost"]),
			next_data.get("dmg_multiplier", skill["dmg_multiplier"])
		]

	row.add_child(info)

	var btn := Button.new()
	if is_maxed:
		btn.text     = "MAX"
		btn.disabled = true
	else:
		btn.text     = "Upgrade\n(1 pt)"
		btn.disabled = upg_pts < 1
		var sid: int = int(skill["skill_id"])
		btn.pressed.connect(func(): _on_upgrade_pressed(sid))

	row.add_child(btn)
	skill_list.add_child(row)

	var sep := HSeparator.new()
	skill_list.add_child(sep)

func _on_upgrade_pressed(skill_id: int) -> void:
	if DatabaseManager.spend_upg_pts(1):
		if not DatabaseManager.upgrade_skill(skill_id):
			DatabaseManager.add_upg_pts(1)
		_refresh()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")