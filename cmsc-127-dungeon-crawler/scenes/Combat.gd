extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Combat.gd
#
# Wave counts per stage type:
#   NORMAL → 3 waves (same monster each wave)
#   ELITE  → 2 waves
#   BOSS   → 1 wave
#
# Passive abilities (applied here in damage calc):
#   MAGE      Arcane Affinity — all attacks build your ultimate
#   WARRIOR   Unyielding Spirit — 1.5x ATK boost at 30% HP
#   ARCHER    Eagle Eye       — 25% chance NORMAL attacks hit twice
#
# DAMAGE_BUFF potion: sets GameState.atk_buff_multiplier, consumed on next hit.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Combat state ─────────────────────────────────────────────────────────────
var enemy_current_hp: int   = 0
var combat_data: Dictionary = {}
var waves_total: int        = 1
var waves_done: int         = 0

# ─── Node refs — Player side ──────────────────────────────────────────────────
@onready var player_sprite:     ColorRect    = $BattleArea/PlayerSide/PlayerSprite
@onready var player_name_label: Label        = $BattleArea/PlayerSide/PlayerNameLabel
@onready var player_hp_bar:     ProgressBar  = $BattleArea/PlayerSide/PlayerHPBar
@onready var player_hp_label:   Label        = $BattleArea/PlayerSide/PlayerHPLabel
@onready var player_sp_bar:     ProgressBar  = $BattleArea/PlayerSide/PlayerSPBar
@onready var player_sp_label:   Label        = $BattleArea/PlayerSide/PlayerSPLabel
@onready var player_ult_label:  Label        = $BattleArea/PlayerSide/UltLabel

# ─── Node refs — Enemy side ───────────────────────────────────────────────────
@onready var enemy_sprite:      ColorRect    = $BattleArea/EnemySide/EnemySprite
@onready var enemy_name_label:  Label        = $BattleArea/EnemySide/EnemyNameLabel
@onready var enemy_hp_bar:      ProgressBar  = $BattleArea/EnemySide/EnemyHPBar
@onready var enemy_hp_label:    Label        = $BattleArea/EnemySide/EnemyHPLabel

# ─── Node refs — Bottom UI ────────────────────────────────────────────────────
@onready var wave_label:      Label         = $LogPanel/VBox/WaveLabel
@onready var log_label:       Label         = $LogPanel/VBox/LogLabel
@onready var skill_container: HBoxContainer = $SkillContainer
@onready var use_potion_btn:  Button        = $ActionRow/UsePotionButton
@onready var flee_btn:        Button        = $ActionRow/FleeButton


# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	combat_data = DatabaseManager.get_combat_data(GameState.current_node_id)

	if combat_data.is_empty():
		push_error("Combat: no combat data for node %d." % GameState.current_node_id)
		return

	# Wave count from stage type
	var stage: String = combat_data["node"]["stage_type"]
	match stage:
		"NORMAL": waves_total = 3
		"ELITE":  waves_total = 2
		"BOSS":   waves_total = 1

	enemy_current_hp = int(combat_data["monster"]["max_hp"])

	use_potion_btn.pressed.connect(_on_use_potion_pressed)
	flee_btn.pressed.connect(_on_flee_pressed)

	_build_skill_buttons()
	wave_label.text = "Wave 1 / %d" % waves_total
	_refresh_ui()
	_begin_player_turn()


# ─── Turn management ─────────────────────────────────────────────────────────

func _begin_player_turn() -> void:
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

	var damage: int = int(monster["attack_power"])
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


# ─── Skill buttons ────────────────────────────────────────────────────────────

func _build_skill_buttons() -> void:
	for child in skill_container.get_children():
		child.queue_free()

	var skills := DatabaseManager.get_player_skills()
	var player := DatabaseManager.get_player()
	var class_data := DatabaseManager.get_class_data(player["player_class"])
	var base_atk: int = int(class_data.get("base_atk", 10))
	
	for skill in skills:
		var btn := Button.new()
		var display_dmg: int = int(float(base_atk) * float(skill["dmg_multiplier"]))
		# Show effective SP cost — MAGE Arcane Affinity reduces SKILL cost by 1
		btn.text = "%s\n[%s]  SP:%d  ATK:%d" % [
			skill["skill_name"],
			skill["atk_type"],
			int(skill["sp_cost"]),
			display_dmg
		]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size   = Vector2(0, 70)
		# .bind() evaluates skill NOW (current loop value), avoiding closure-capture bug
		btn.pressed.connect(_on_skill_used.bind(skill))
		skill_container.add_child(btn)


func _set_skill_buttons_enabled(enabled: bool) -> void:
	for btn in skill_container.get_children():
		btn.disabled = not enabled


# ─── Skill use ────────────────────────────────────────────────────────────────

func _on_skill_used(skill: Dictionary) -> void:
	# Prevent double-firing while processing
	_set_skill_buttons_enabled(false)
	
	var player := DatabaseManager.get_player()

	var effective_sp_cost: int = int(skill["sp_cost"])

	# Validation
	if int(player["current_sp"]) < effective_sp_cost:
		log_label.text = "Not enough SP!"
		_set_skill_buttons_enabled(true)
		return
	if skill["atk_type"] == "ULTIMATE" and int(player["current_ult_pts"]) < GameState.ULT_PTS_MAX:
		log_label.text = "Need %d ULT points to use Ultimate!" % GameState.ULT_PTS_MAX
		_set_skill_buttons_enabled(true)
		return

	# ── Base ATK from class ───────────────────────────────────────────────────
	var class_data: Dictionary = DatabaseManager.get_class_data(player["player_class"])
	var base_atk: int = int(class_data.get("base_atk", 10))

	# ── Passive: WARRIOR — Unyielding Spirit (1.5x ATK boost at 30% HP) ─────────
	if player["player_class"] == "WARRIOR":
		var hp_ratio: float = float(player["current_hp"]) / float(player["max_hp"])
		if hp_ratio <= 0.3:
			base_atk = int(base_atk * 1.5)

	# ── Damage calculation ────────────────────────────────────────────────────
	var damage: int = int(float(base_atk) * float(skill["dmg_multiplier"]))

	# ── Apply DAMAGE_BUFF if active (consumed on hit) ─────────────────────────
	if GameState.atk_buff_multiplier != 1.0:
		damage = int(float(damage) * GameState.atk_buff_multiplier)
		GameState.atk_buff_multiplier = 1.0

	var log_msg: String = "You used %s for %d damage!" % [skill["skill_name"], damage]

# ── Override log if Warrior Bloodlust is active ───────────────────────────
	if player["player_class"] == "WARRIOR":
		var hp_ratio: float = float(player["current_hp"]) / float(player["max_hp"])
		if hp_ratio <= 0.3:
			log_msg = "Your Unyielding Spirit is showing! %s deals %d damage!" % [skill["skill_name"], damage]
			
	# ── Passive: ARCHER — Eagle Eye (25% double strike on NORMAL) ────────────
	if player["player_class"] == "ARCHER" and (skill["atk_type"] == "NORMAL" or skill["atk_type"] == "SKILL") and randf() < 0.30:
		damage *= 2
		log_msg = "Eagle Eye! %s hits TWICE for %d damage!" % [skill["skill_name"], damage]

	enemy_current_hp -= damage
	log_label.text = log_msg

	# Consume SP (effective cost respects MAGE passive)
	DatabaseManager.update_player_sp(int(player["current_sp"]) - effective_sp_cost)

	# Update ult points
	var new_ult: int = clampi(int(player["current_ult_pts"]) + int(skill["ult_pts_mod"]), 0, GameState.ULT_PTS_MAX)
	DatabaseManager.update_player_ult_pts(new_ult)

	_refresh_ui()

	if enemy_current_hp <= 0:
		await get_tree().create_timer(0.5).timeout
		_on_wave_cleared()
		return
		
	# ── Check remaining SP — end turn only if out of SP ──────────────────────
	var updated_player := DatabaseManager.get_player()
	var can_still_act: bool = false
	var current_skills := DatabaseManager.get_player_skills()
	for s in current_skills:
		var cost: int = int(s["sp_cost"])
		if int(updated_player["current_sp"]) >= cost:
			can_still_act = true
			break

	if not can_still_act:
		DatabaseManager.reset_player_sp()
		_end_player_turn()
	else:
		# Re-enable buttons only if player can still act
		_set_skill_buttons_enabled(true)


# ─── Wave management ──────────────────────────────────────────────────────────

func _on_wave_cleared() -> void:
	waves_done += 1

	if waves_done < waves_total:
		# More waves — reset enemy, update label, continue
		var next_wave: int = waves_done + 1
		log_label.text    = "Wave %d cleared! Next wave incoming..." % waves_done
		wave_label.text   = "Wave %d / %d" % [next_wave, waves_total]
		enemy_current_hp  = int(combat_data["monster"]["max_hp"])
		var current_player := DatabaseManager.get_player()
		if int(current_player["current_sp"]) <= 0:
			DatabaseManager.reset_player_sp()
		_refresh_ui()
		await get_tree().create_timer(1.2).timeout
		_begin_player_turn()
	else:
		_on_victory()


# ─── Resolution ───────────────────────────────────────────────────────────────

func _on_victory() -> void:
	log_label.text  = "Victory!"
	wave_label.text = "All waves cleared!"
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


# ─── Potion use ───────────────────────────────────────────────────────────────

func _on_use_potion_pressed() -> void:
	var inventory := DatabaseManager.get_inventory()
	if inventory.is_empty():
		log_label.text = "No potions!"
		return

	var item:   Dictionary = inventory[0]
	var player: Dictionary = DatabaseManager.get_player()

	match item["pot_type"]:
		"HEAL":
			var new_hp := mini(int(player["current_hp"]) + int(item["potency_value"]), int(player["max_hp"]))
			DatabaseManager.update_player_hp(new_hp)
			log_label.text = "Used %s — restored %d HP." % [item["pot_name"], int(item["potency_value"])]
		"DAMAGE_BUFF":
			GameState.atk_buff_multiplier = 1.0 + float(item["potency_value"])
			log_label.text = "Used %s — ATK +%d%% on next hit!" % [item["pot_name"], int(item["potency_value"] * 100.0)]

	DatabaseManager.remove_from_inventory(item["inv_id"])
	_refresh_ui()


# ─── Flee ─────────────────────────────────────────────────────────────────────

func _on_flee_pressed() -> void:
	if randf() < 0.5:
		log_label.text = "You fled!"
		DatabaseManager.combat_ended.emit("fled")
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file("res://scenes/Map.tscn")
	else:
		log_label.text = "Couldn't escape!"
		_end_player_turn()


# ─── Drop rolls ───────────────────────────────────────────────────────────────

func _roll_drops() -> void:
	var monster: Dictionary = combat_data["monster"]
	if randf() < float(monster["pot_drop_chance"]):
		var pot_id := randi_range(1, 3)
		if DatabaseManager.add_to_inventory(pot_id):
			var potion := DatabaseManager.get_potion(pot_id)
			log_label.text += "\nDrop: %s!" % potion.get("pot_name", "Potion")
	if randf() < float(monster["upg_point_chance"]):
		DatabaseManager.add_upg_pts(1)
		log_label.text += "\nDrop: +1 Upgrade Point!"


# ─── UI refresh ───────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	var player:  Dictionary = DatabaseManager.get_player()
	var monster: Dictionary = combat_data.get("monster", {})

	if not player.is_empty():
		player_name_label.text = GameState.player_class
		player_hp_bar.max_value = int(player["max_hp"])
		player_hp_bar.value     = int(player["current_hp"])
		player_hp_label.text    = "HP  %d / %d" % [player["current_hp"], player["max_hp"]]
		player_sp_bar.max_value = int(player["max_sp"])
		player_sp_bar.value     = int(player["current_sp"])
		player_sp_label.text    = "SP  %d / %d" % [player["current_sp"], player["max_sp"]]
		player_ult_label.text   = "ULT  %d / %d" % [player["current_ult_pts"], GameState.ULT_PTS_MAX]

	if not monster.is_empty():
		enemy_name_label.text  = "%s  [%s]" % [monster["mon_name"], monster["monster_type"]]
		enemy_hp_bar.max_value = int(monster["max_hp"])
		enemy_hp_bar.value     = max(enemy_current_hp, 0)
		enemy_hp_label.text    = "HP  %d / %d" % [max(enemy_current_hp, 0), monster["max_hp"]]
