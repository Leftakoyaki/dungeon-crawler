extends Control

# ─────────────────────────────────────────────────────────────────────────────
# UpgradeScreen.gd — Phase 4
#
# Lists all player skills. Each row shows current tier stats vs next tier stats.
# "Upgrade (1 pt)" button — disabled if tier is 3 or player has no upg_pts_bank.
# Back → Map.
# ─────────────────────────────────────────────────────────────────────────────

@onready var pts_label:   Label         = $MarginContainer/VBoxContainer/PtsLabel
@onready var skill_list:  VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SkillList
@onready var back_btn:    Button        = $MarginContainer/VBoxContainer/BackButton

# Add this helper near the top of the script
func _get_max_tier(skill_id: int) -> int:
	if skill_id in [1, 4, 7]:
		return 1
	return 3

func _ready() -> void:
	# --- ADDED: Keep Map Music going seamlessly ---
	MusicManager.play_map()
	
	back_btn.pressed.connect(_on_back_pressed)
	
	# --- ADDED: Click sound for back button ---
	_connect_click_sound(back_btn)
	
	_refresh()

# --- ADDED: Helper function for button clicks ---
func _connect_click_sound(btn: BaseButton) -> void:
	btn.button_down.connect(func(): MusicManager.play_click())


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

	# Get next tier data for comparison (empty if maxed)
	var next_data: Dictionary = {}
	if not is_maxed:
		next_data = DatabaseManager.get_skill_upgrade(int(skill["skill_id"]), current_tier + 1)

	# Row container
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	# Skill info label
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if is_maxed:
		info.text = "%s  [%s]\nTier %d  SP:%d  x%.1f  ← MAX" % [
			skill["skill_name"],
			skill["atk_type"],
			current_tier,
			skill["sp_cost"],
			skill["dmg_multiplier"]
		]
	else:
		info.text = "%s  [%s]\nTier %d → %d  |  SP:%d  x%.1f  →  SP:%d  x%.1f" % [
			skill["skill_name"],
			skill["atk_type"],
			current_tier,
			current_tier + 1,
			skill["sp_cost"],
			skill["dmg_multiplier"],
			next_data.get("sp_cost",        skill["sp_cost"]),
			next_data.get("dmg_multiplier", skill["dmg_multiplier"])
		]

	row.add_child(info)

	# Upgrade button
	var btn := Button.new()
	if is_maxed:
		btn.text     = "MAX"
		btn.disabled = true
	else:
		btn.text     = "Upgrade\n(1 pt)"
		btn.disabled = upg_pts < 1
		var sid: int = int(skill["skill_id"])
		btn.pressed.connect(func(): _on_upgrade_pressed(sid))
		
		# --- ADDED: Wire the click sound to every dynamically created Upgrade button ---
		_connect_click_sound(btn)

	row.add_child(btn)
	skill_list.add_child(row)

	# Separator
	var sep := HSeparator.new()
	skill_list.add_child(sep)


func _on_upgrade_pressed(skill_id: int) -> void:
	var spent: bool = DatabaseManager.spend_upg_pts(1)
	if not spent:
		return  # no points (shouldn't reach here if button was enabled)

	var upgraded: bool = DatabaseManager.upgrade_skill(skill_id)
	if not upgraded:
		# Rollback the point — skill must be maxed somehow
		DatabaseManager.add_upg_pts(1)
		return

	_refresh()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
