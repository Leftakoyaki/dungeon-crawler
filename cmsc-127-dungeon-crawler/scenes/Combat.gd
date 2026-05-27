extends Control

# ─── Combat state (GDScript-owned, not in DB) ────────────────────────────────
var enemy_current_hp: int    = 0
var combat_data: Dictionary  = {}  # keys: node, monster, player

# ─── Node refs — Player side ──────────────────────────────────────────────────
@onready var player_sprite:     ColorRect   = $BattleArea/PlayerSide/PlayerSprite
@onready var player_name_label: Label       = $BattleArea/PlayerSide/PlayerNameLabel
@onready var player_hp_bar:     ProgressBar = $BattleArea/PlayerSide/PlayerHPBar
@onready var player_hp_label:   Label       = $BattleArea/PlayerSide/PlayerHPLabel
@onready var player_sp_bar:     ProgressBar = $BattleArea/PlayerSide/PlayerSPBar
@onready var player_sp_label:   Label       = $BattleArea/PlayerSide/PlayerSPLabel
@onready var player_ult_label:  Label       = $BattleArea/PlayerSide/UltLabel

# ─── Node refs — Enemy side ───────────────────────────────────────────────────
@onready var enemy_sprite:      ColorRect   = $BattleArea/EnemySide/EnemySprite
@onready var enemy_name_label:  Label       = $BattleArea/EnemySide/EnemyNameLabel
@onready var enemy_hp_bar:      ProgressBar = $BattleArea/EnemySide/EnemyHPBar
@onready var enemy_hp_label:    Label       = $BattleArea/EnemySide/EnemyHPLabel

# ─── Node refs — Bottom UI ───────────────────────────────────────────────────
@onready var log_label:         Label        = $LogPanel/LogLabel
@onready var skill_container:   HBoxContainer = $SkillContainer
@onready var use_potion_btn:    Button       = $ActionRow/UsePotionButton
@onready var flee_btn:          Button       = $ActionRow/FleeButton


# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	combat_data = DatabaseManager.get_combat_data(GameState.current_node_id)

	if combat_data.is_empty():
		push_error("Combat: no combat data for node %d." % GameState.current_node_id)
		return

	enemy_current_hp = combat_data["monster"]["max_hp"]

	use_potion_btn.pressed.connect(_on_use_potion_pressed)
	flee_btn.pressed.connect(_on_flee_pressed)

	_build_skill_buttons()
	_refresh_ui()
	_begin_player_turn()


# ─── Turn management ─────────────────────────────────────────────────────────

func _begin_player_turn() -> void:
	DatabaseManager.update_player_sp(GameState.current_max_sp())
	_set_skill_buttons_enabled(true)
	use_potion_btn.disabled = false
	flee_btn.disabled       = false
	_refresh_ui()


func _end_player_turn() -> void:
	_set_skill_buttons_enabled(false)
	use_potion_btn.disabled = true
	flee_btn.disabled       = true
	await get_tree().create_timer(0.8).timeout
	_enemy_turn()


func _enemy_turn() -> void:
	var player:  Dictionary = DatabaseManager.get_player()
	var monster: Dictionary = combat_data["monster"]

	var damage: int = monster["attack_power"]
	var new_hp: int = max(int(player["current_hp"]) - damage, 0)

	log_label.text = "%s attacks for %d damage!" % [monster["mon_name"], damage]
	DatabaseManager.update_player_hp(new_hp)
	_refresh_ui()

	if new_hp <= 0:
		await get_tree().create_timer(0.5).timeout
		_on_defeat()
		return

	use_potion_btn.disabled = false
	flee_btn.disabled       = false
	_begin_player_turn()


# ─── Skill buttons ───────────────────────────────────────────────────────────

func _build_skill_buttons() -> void:
	for child in skill_container.get_children():
		child.queue_free()

	var skills := DatabaseManager.get_player_skills()
	for skill in skills:
		var btn := Button.new()
		# Multi-line label: name on top, stats below
		btn.text = "%s\n[%s]  SP:%d  x%.1f" % [
			skill["skill_name"],
			skill["atk_type"],
			skill["sp_cost"],
			skill["dmg_multiplier"]
		]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, 70)
		btn.pressed.connect(func(): _on_skill_used(skill))
		skill_container.add_child(btn)


func _set_skill_buttons_enabled(enabled: bool) -> void:
	for btn in skill_container.get_children():
		btn.disabled = not enabled


# ─── Skill use ───────────────────────────────────────────────────────────────

func _on_skill_used(skill: Dictionary) -> void:
	var player := DatabaseManager.get_player()

	# Validation
	if player["current_sp"] < skill["sp_cost"]:
		log_label.text = "Not enough SP!"
		return
	if skill["atk_type"] == "ULTIMATE" and player["current_ult_pts"] < GameState.ULT_PTS_MAX:
		log_label.text = "Need %d ULT points to use Ultimate!" % GameState.ULT_PTS_MAX
		return

	# Damage
	var class_data: Dictionary = DatabaseManager.get_class_data(player["player_class"])
	var base_atk: int = class_data.get("base_atk", 10)
	var damage: int = int(base_atk * float(skill["dmg_multiplier"]))

	enemy_current_hp -= damage
	log_label.text = "You used %s for %d damage!" % [skill["skill_name"], damage]

	# Consume SP
	DatabaseManager.update_player_sp(player["current_sp"] - skill["sp_cost"])

	# Update ult points
	var new_ult: int = clampi(int(player["current_ult_pts"]) + int(skill["ult_pts_mod"]), 0, GameState.ULT_PTS_MAX)
	DatabaseManager.update_player_ult_pts(new_ult)

	_refresh_ui()

	if enemy_current_hp <= 0:
		await get_tree().create_timer(0.5).timeout
		_on_victory()
		return

	_end_player_turn()


# ─── Potion use ──────────────────────────────────────────────────────────────

func _on_use_potion_pressed() -> void:
	var inventory := DatabaseManager.get_inventory()
	if inventory.is_empty():
		log_label.text = "No potions!"
		return

	var item:   Dictionary = inventory[0]
	var player: Dictionary = DatabaseManager.get_player()

	match item["pot_type"]:
		"HEAL":
			var new_hp := mini(player["current_hp"] + int(item["potency_value"]), player["max_hp"])
			DatabaseManager.update_player_hp(new_hp)
			log_label.text = "Used %s — restored %d HP." % [item["pot_name"], int(item["potency_value"])]
		"DAMAGE_BUFF":
			# TODO: store buff in GameState and apply as multiplier on next hit
			log_label.text = "Used %s — ATK +%d%% next hit." % [item["pot_name"], int(item["potency_value"] * 100)]

	DatabaseManager.remove_from_inventory(item["inv_id"])
	_refresh_ui()


# ─── Flee ────────────────────────────────────────────────────────────────────

func _on_flee_pressed() -> void:
	if randf() < 0.5:
		log_label.text = "You fled!"
		DatabaseManager.combat_ended.emit("fled")
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file("res://scenes/Map.tscn")
	else:
		log_label.text = "Couldn't escape!"
		_end_player_turn()


# ─── Resolution ──────────────────────────────────────────────────────────────

func _on_victory() -> void:
	log_label.text = "Victory!"
	_set_skill_buttons_enabled(false)
	use_potion_btn.disabled = true
	flee_btn.disabled       = true

	DatabaseManager.mark_node_cleared(GameState.current_node_id)
	_roll_drops()
	DatabaseManager.combat_ended.emit("victory")

	var node: Dictionary = combat_data["node"]
	await get_tree().create_timer(1.0).timeout
	if node["stage_type"] == "BOSS":
		get_tree().change_scene_to_file("res://scenes/WinScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Map.tscn")


func _on_defeat() -> void:
	log_label.text = "You have been defeated..."
	_set_skill_buttons_enabled(false)
	use_potion_btn.disabled = true
	flee_btn.disabled       = true
	DatabaseManager.combat_ended.emit("defeat")
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/GameOver.tscn")


# ─── Drop rolls ──────────────────────────────────────────────────────────────

func _roll_drops() -> void:
	var monster: Dictionary = combat_data["monster"]
	if randf() < monster["pot_drop_chance"]:
		var pot_id := randi_range(1, 3)
		if DatabaseManager.add_to_inventory(pot_id):
			var potion := DatabaseManager.get_potion(pot_id)
			log_label.text += "\nDrop: %s!" % potion.get("pot_name", "Potion")
	if randf() < monster["upg_point_chance"]:
		DatabaseManager.add_upg_pts(1)
		log_label.text += "\nDrop: +1 Upgrade Point!"


# ─── UI refresh ──────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	var player:  Dictionary = DatabaseManager.get_player()
	var monster: Dictionary = combat_data.get("monster", {})

	if not player.is_empty():
		player_name_label.text = "%s  (%s)" % [GameState.player_class, combat_data.get("node", {}).get("stage_type", "")]
		player_hp_bar.max_value = player["max_hp"]
		player_hp_bar.value     = player["current_hp"]
		player_hp_label.text    = "HP  %d / %d" % [player["current_hp"], player["max_hp"]]
		player_sp_bar.max_value = GameState.current_max_sp()
		player_sp_bar.value     = player["current_sp"]
		player_sp_label.text    = "SP  %d / %d" % [player["current_sp"], GameState.current_max_sp()]
		player_ult_label.text   = "ULT  %d / %d" % [player["current_ult_pts"], GameState.ULT_PTS_MAX]

	if not monster.is_empty():
		enemy_name_label.text    = "%s  [%s]" % [monster["mon_name"], monster["monster_type"]]
		enemy_hp_bar.max_value   = monster["max_hp"]
		enemy_hp_bar.value       = max(enemy_current_hp, 0)
		enemy_hp_label.text      = "HP  %d / %d" % [max(enemy_current_hp, 0), monster["max_hp"]]
