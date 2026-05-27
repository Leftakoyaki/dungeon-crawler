extends Node

# ─────────────────────────────────────────────────────────────────────────────
# DatabaseManager.gd  —  Autoload singleton
#
# Single source of truth for ALL SQL. No other script touches db directly.
# Register this as the SECOND autoload in Project Settings (after GameState).
#
# Public API summary:
#   Classes       → get_all_classes(), get_class(name)
#   Skills        → get_skills_for_class(name), get_skill(id)
#   Skill_Upgrades→ get_skill_upgrade(id, tier), get_all_tiers(id)
#   Monsters      → get_monster(id)
#   Potions       → get_potion(id)
#   Player_Status → get_player(), create_player(class), update_player_hp/sp/ult_pts/location()
#                   add_upg_pts(), spend_upg_pts(), delete_player()
#   Player_Skills → get_player_skills(), get_player_skill(id), add_player_skill(id), upgrade_skill(id)
#   Player_Inventory → get_inventory(), get_inventory_count(), add_to_inventory(), remove_from_inventory()
#   Dungeon_Floor → get_dungeon_node(id), get_available_paths(id), mark_node_cleared(id), reset_floor()
#   Game Flow     → start_new_game(class), get_combat_data(node_id)
# ─────────────────────────────────────────────────────────────────────────────

# ─── Constants ───────────────────────────────────────────────────────────────
const DB_PATH := "user://dungeon_crawler.db"

# ─── Signals ─────────────────────────────────────────────────────────────────
signal player_hp_changed(new_hp: int, max_hp: int)
signal player_moved(new_node_id: int)
signal combat_ended(result: String)   # "victory" | "defeat" | "fled"

# ─── Private Vars ────────────────────────────────────────────────────────────
var db: SQLite = null

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_initialize_database()


func _initialize_database() -> void:
	db = SQLite.new()
	db.path = DB_PATH
	db.verbosity_level = 1  # 0=quiet, 1=normal, 2=verbose, 3=very verbose

	if not db.open_db():
		push_error("DatabaseManager: Failed to open DB at '%s'." % DB_PATH)
		return

	db.query("PRAGMA foreign_keys = ON;")
	_create_tables()
	_seed_static_data()
	print("DatabaseManager: Ready.")


# ─────────────────────────────────────────────────────────────────────────────
# SCHEMA — CREATE TABLES
# All 9 tables. Safe to call on every boot (IF NOT EXISTS).
# Order matters: parents before children for FK references.
# ─────────────────────────────────────────────────────────────────────────────

func _create_tables() -> void:
	# ── Static Entities ──────────────────────────────────────────────────────

	db.query("""
		CREATE TABLE IF NOT EXISTS Classes (
			class_name TEXT PRIMARY KEY,
			base_hp INTEGER NOT NULL,
			base_atk INTEGER NOT NULL,
			passive_description TEXT NOT NULL
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Skills (
			skill_id INTEGER PRIMARY KEY,
			skill_name TEXT NOT NULL,
			atk_type TEXT NOT NULL CHECK(atk_type IN ('NORMAL','SKILL','ULTIMATE')),
			class_restriction TEXT NOT NULL,
			ult_pts_mod INTEGER NOT NULL,
			FOREIGN KEY (class_restriction) REFERENCES Classes(class_name)
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Skill_Upgrades (
			skill_id INTEGER NOT NULL,
			upgrade_tier INTEGER NOT NULL CHECK(upgrade_tier IN (0,1,2,3)),
			sp_cost INTEGER NOT NULL,
			dmg_multiplier REAL NOT NULL,
			PRIMARY KEY (skill_id, upgrade_tier),
			FOREIGN KEY (skill_id) REFERENCES Skills(skill_id)
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Monsters (
			monster_id INTEGER PRIMARY KEY,
			mon_name TEXT NOT NULL,
			max_hp INTEGER NOT NULL,
			attack_power INTEGER NOT NULL,
			monster_type TEXT NOT NULL CHECK(monster_type IN ('NORMAL','ELITE','BOSS')),
			pot_drop_chance REAL NOT NULL,
			upg_point_chance REAL NOT NULL
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Potions (
			pot_id INTEGER PRIMARY KEY,
			pot_name TEXT NOT NULL,
			pot_type TEXT NOT NULL,
			potency_value REAL NOT NULL
		);
	""")

	# ── Runtime Entities ─────────────────────────────────────────────────────
	# Dungeon_Floor before Player_Status: Player_Status.current_node_id → Dungeon_Floor.node_id

	db.query("""
		CREATE TABLE IF NOT EXISTS Dungeon_Floor (
			node_id INTEGER PRIMARY KEY,
			stage_type TEXT NOT NULL CHECK(stage_type IN ('START','NORMAL','ELITE','EVENT','REST','BOSS')),
			monster_id INTEGER,
			is_cleared INTEGER NOT NULL DEFAULT 0,
			child_left_id INTEGER,
			child_right_id INTEGER,
			FOREIGN KEY (monster_id)      REFERENCES Monsters(monster_id),
			FOREIGN KEY (child_left_id)   REFERENCES Dungeon_Floor(node_id),
			FOREIGN KEY (child_right_id)  REFERENCES Dungeon_Floor(node_id)
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Player_Status (
			player_id INTEGER PRIMARY KEY,
			player_class TEXT NOT NULL,
			current_hp INTEGER NOT NULL,
			max_hp INTEGER NOT NULL,
			current_sp INTEGER NOT NULL,
			current_ult_pts INTEGER NOT NULL DEFAULT 0,
			upg_pts_bank INTEGER NOT NULL DEFAULT 0,
			current_node_id INTEGER NOT NULL,
			FOREIGN KEY (player_class)    REFERENCES Classes(class_name),
			FOREIGN KEY (current_node_id) REFERENCES Dungeon_Floor(node_id)
		);
	""")

	# Composite PK (player_id, skill_id)
	# Composite FK (skill_id, current_tier) → Skill_Upgrades(skill_id, upgrade_tier)
	db.query("""
		CREATE TABLE IF NOT EXISTS Player_Skills_Status (
			player_id INTEGER NOT NULL,
			skill_id INTEGER NOT NULL,
			current_tier INTEGER NOT NULL DEFAULT 0,
			PRIMARY KEY (player_id, skill_id),
			FOREIGN KEY (player_id) REFERENCES Player_Status(player_id),
			FOREIGN KEY (skill_id, current_tier) REFERENCES Skill_Upgrades(skill_id, upgrade_tier)
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Player_Inventory (
			inv_id INTEGER PRIMARY KEY AUTOINCREMENT,
			player_id INTEGER NOT NULL,
			pot_id INTEGER NOT NULL,
			FOREIGN KEY (player_id) REFERENCES Player_Status(player_id),
			FOREIGN KEY (pot_id)    REFERENCES Potions(pot_id)
		);
	""")

	print("DatabaseManager: Tables created.")


# ─────────────────────────────────────────────────────────────────────────────
# SEED — STATIC DATA
# Runs once. Guard checks Classes row count before inserting.
# ─────────────────────────────────────────────────────────────────────────────

func _seed_static_data() -> void:
	db.query("SELECT COUNT(*) AS cnt FROM Classes;")
	if not db.query_result.is_empty() and db.query_result[0].get("cnt", 0) > 0:
		return  # already seeded

	_seed_classes()
	_seed_skills()
	_seed_skill_upgrades()
	_seed_monsters()
	_seed_potions()
	_seed_dungeon_floor()
	print("DatabaseManager: Static data seeded.")


func _seed_classes() -> void:
	# TODO: Adjust base_hp, base_atk, and passive_description to match your design.
	var rows := [
		{
			"class_name":           "MAGE",
			"base_hp":              80,
			"base_atk":             30,
			"passive_description":  "Arcane Affinity: SKILL-type SP costs reduced by 1 (min 1)."
		},
		{
			"class_name":           "BERSERKER",
			"base_hp":              120,
			"base_atk":             40,
			"passive_description":  "Bloodlust: Gain +5 ATK for every 20% HP lost."
		},
		{
			"class_name":           "ARCHER",
			"base_hp":              100,
			"base_atk":             35,
			"passive_description":  "Eagle Eye: NORMAL attacks have a 25% chance to strike twice."
		},
	]
	for row in rows:
		db.insert_row("Classes", row)


func _seed_skills() -> void:
	# 3 skills per class: 1 NORMAL, 1 SKILL, 1 ULTIMATE.
	# ult_pts_mod: NORMAL/SKILL charge ult (+1), ULTIMATE spends ult (-2).
	# TODO: Replace with your final skill names.
	var rows := [
		# ── MAGE ──────────────────────────────────────────────────────────
		{"skill_id": 1, "skill_name": "Staff Strike",    "atk_type": "NORMAL",   "class_restriction": "MAGE",      "ult_pts_mod":  1},
		{"skill_id": 2, "skill_name": "Fireball",         "atk_type": "SKILL",    "class_restriction": "MAGE",      "ult_pts_mod":  1},
		{"skill_id": 3, "skill_name": "Meteor Storm",     "atk_type": "ULTIMATE", "class_restriction": "MAGE",      "ult_pts_mod": -2},
		# ── BERSERKER ─────────────────────────────────────────────────────
		{"skill_id": 4, "skill_name": "Savage Slash",    "atk_type": "NORMAL",   "class_restriction": "BERSERKER", "ult_pts_mod":  1},
		{"skill_id": 5, "skill_name": "Cleave",           "atk_type": "SKILL",    "class_restriction": "BERSERKER", "ult_pts_mod":  1},
		{"skill_id": 6, "skill_name": "Rampage",          "atk_type": "ULTIMATE", "class_restriction": "BERSERKER", "ult_pts_mod": -2},
		# ── ARCHER ────────────────────────────────────────────────────────
		{"skill_id": 7, "skill_name": "Arrow Shot",      "atk_type": "NORMAL",   "class_restriction": "ARCHER",    "ult_pts_mod":  1},
		{"skill_id": 8, "skill_name": "Volley",           "atk_type": "SKILL",    "class_restriction": "ARCHER",    "ult_pts_mod":  1},
		{"skill_id": 9, "skill_name": "Rain of Arrows",  "atk_type": "ULTIMATE", "class_restriction": "ARCHER",    "ult_pts_mod": -2},
	]
	for row in rows:
		db.insert_row("Skills", row)


func _seed_skill_upgrades() -> void:
	# NORMAL  (ids 1,4,7): sp_cost=1, dmg scales 1.0 → 1.6
	# SKILL   (ids 2,5,8): sp_cost=2, dmg scales 1.5 → 2.4
	# ULTIMATE(ids 3,6,9): sp_cost=5 (locked per schema), dmg scales 2.5 → 4.0
	# TODO: Tune dmg_multiplier values for your combat balance.
	var upgrades: Array = []

	for sid in [1, 4, 7]:  # NORMAL
		upgrades.append({"skill_id": sid, "upgrade_tier": 0, "sp_cost": 1, "dmg_multiplier": 1.0})
		upgrades.append({"skill_id": sid, "upgrade_tier": 1, "sp_cost": 1, "dmg_multiplier": 1.2})
		upgrades.append({"skill_id": sid, "upgrade_tier": 2, "sp_cost": 1, "dmg_multiplier": 1.4})
		upgrades.append({"skill_id": sid, "upgrade_tier": 3, "sp_cost": 1, "dmg_multiplier": 1.6})

	for sid in [2, 5, 8]:  # SKILL
		upgrades.append({"skill_id": sid, "upgrade_tier": 0, "sp_cost": 2, "dmg_multiplier": 1.5})
		upgrades.append({"skill_id": sid, "upgrade_tier": 1, "sp_cost": 2, "dmg_multiplier": 1.8})
		upgrades.append({"skill_id": sid, "upgrade_tier": 2, "sp_cost": 2, "dmg_multiplier": 2.1})
		upgrades.append({"skill_id": sid, "upgrade_tier": 3, "sp_cost": 2, "dmg_multiplier": 2.4})

	for sid in [3, 6, 9]:  # ULTIMATE — sp_cost locked at 5 per schema
		upgrades.append({"skill_id": sid, "upgrade_tier": 0, "sp_cost": 5, "dmg_multiplier": 2.5})
		upgrades.append({"skill_id": sid, "upgrade_tier": 1, "sp_cost": 5, "dmg_multiplier": 3.0})
		upgrades.append({"skill_id": sid, "upgrade_tier": 2, "sp_cost": 5, "dmg_multiplier": 3.5})
		upgrades.append({"skill_id": sid, "upgrade_tier": 3, "sp_cost": 5, "dmg_multiplier": 4.0})

	for row in upgrades:
		db.insert_row("Skill_Upgrades", row)


func _seed_monsters() -> void:
	# TODO: Tune stats for balance. pot_drop_chance and upg_point_chance are
	# decimal probabilities (0.0–1.0) — roll against these in GDScript after combat.
	var rows := [
		{"monster_id": 1, "mon_name": "Goblin",      "max_hp": 40,  "attack_power": 8,  "monster_type": "NORMAL", "pot_drop_chance": 0.30, "upg_point_chance": 0.05},
		{"monster_id": 2, "mon_name": "Skeleton",    "max_hp": 35,  "attack_power": 7,  "monster_type": "NORMAL", "pot_drop_chance": 0.20, "upg_point_chance": 0.05},
		{"monster_id": 3, "mon_name": "Orc",         "max_hp": 60,  "attack_power": 12, "monster_type": "NORMAL", "pot_drop_chance": 0.25, "upg_point_chance": 0.05},
		{"monster_id": 4, "mon_name": "Dark Knight", "max_hp": 100, "attack_power": 18, "monster_type": "ELITE",  "pot_drop_chance": 0.50, "upg_point_chance": 0.60},
		{"monster_id": 5, "mon_name": "Troll",       "max_hp": 120, "attack_power": 20, "monster_type": "ELITE",  "pot_drop_chance": 0.55, "upg_point_chance": 0.60},
		{"monster_id": 6, "mon_name": "Dragon",      "max_hp": 200, "attack_power": 25, "monster_type": "BOSS",   "pot_drop_chance": 0.80, "upg_point_chance": 0.80},
	]
	for row in rows:
		db.insert_row("Monsters", row)


func _seed_potions() -> void:
	# pot_type drives the effect logic in GDScript (HEAL restores HP, DAMAGE_BUFF scales ATK).
	# TODO: Adjust potency_value. HEAL = flat HP restored. DAMAGE_BUFF = decimal multiplier.
	var rows := [
		{"pot_id": 1, "pot_name": "Health Potion",         "pot_type": "HEAL",        "potency_value": 50.0},
		{"pot_id": 2, "pot_name": "Greater Health Potion", "pot_type": "HEAL",        "potency_value": 100.0},
		{"pot_id": 3, "pot_name": "Attack Elixir",         "pot_type": "DAMAGE_BUFF", "potency_value": 0.25},
	]
	for row in rows:
		db.insert_row("Potions", row)


func _seed_dungeon_floor() -> void:
	# Self-referencing FK requires two-pass insert:
	# Pass 1 — insert all nodes with null child pointers (avoids FK violation).
	# Pass 2 — UPDATE child pointers now that all node_ids exist.
	#
	# Map layout (10 nodes, binary tree FSM):
	#
	#           1 (START)
	#          / \
	#         2   3        ← NORMAL encounters
	#        / \ / \
	#       4       5      ← 4=EVENT, 5=REST  (convergent — both paths reach same nodes)
	#      / \     / \
	#     6   7   6   7    ← 6=ELITE, 7=NORMAL  (same node_ids, shared children)
	#    / \ / \
	#   8       9          ← 8=REST, 9=EVENT   (shared)
	#    \     /
	#        10            ← BOSS
	#
	# Pass 1: insert with no children
	var nodes := [
		{"node_id": 1,  "stage_type": "START",  "is_cleared": 0},
		{"node_id": 2,  "stage_type": "NORMAL", "monster_id": 1, "is_cleared": 0},
		{"node_id": 3,  "stage_type": "NORMAL", "monster_id": 2, "is_cleared": 0},
		{"node_id": 4,  "stage_type": "EVENT",  "is_cleared": 0},
		{"node_id": 5,  "stage_type": "REST",   "is_cleared": 0},
		{"node_id": 6,  "stage_type": "ELITE",  "monster_id": 4, "is_cleared": 0},
		{"node_id": 7,  "stage_type": "NORMAL", "monster_id": 3, "is_cleared": 0},
		{"node_id": 8,  "stage_type": "REST",   "is_cleared": 0},
		{"node_id": 9,  "stage_type": "EVENT",  "is_cleared": 0},
		{"node_id": 10, "stage_type": "BOSS",   "monster_id": 6, "is_cleared": 0},
	]
	for row in nodes:
		db.insert_row("Dungeon_Floor", row)

	# Pass 2: set child pointers (node 10 is terminal — no update needed)
	var paths := [
		{"node_id": 1, "left": 2,  "right": 3},
		{"node_id": 2, "left": 4,  "right": 5},
		{"node_id": 3, "left": 4,  "right": 5},
		{"node_id": 4, "left": 6,  "right": 7},
		{"node_id": 5, "left": 6,  "right": 7},
		{"node_id": 6, "left": 8,  "right": 9},
		{"node_id": 7, "left": 8,  "right": 9},
		{"node_id": 8, "left": 10, "right": null},
		{"node_id": 9, "left": 10, "right": null},
	]
	for p in paths:
		db.update_rows("Dungeon_Floor", "node_id = %d" % p["node_id"], {
			"child_left_id":  p["left"],
			"child_right_id": p["right"]
		})


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — CLASSES
# ─────────────────────────────────────────────────────────────────────────────

## Returns Array[Dictionary] of all class rows. Empty array on failure.
func get_all_classes() -> Array:
	db.select_rows("Classes", "", ["*"])
	return db.query_result.duplicate()


## Returns Dictionary for one class by name. Empty {} if not found.
func get_class_data(cls_name: String) -> Dictionary:
	db.select_rows("Classes", "class_name = '%s'" % cls_name, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — SKILLS
# ─────────────────────────────────────────────────────────────────────────────

## Returns Array[Dictionary] of all skills belonging to a class.
func get_skills_for_class(cls_name: String) -> Array:
	db.select_rows("Skills", "class_restriction = '%s'" % cls_name, ["*"])
	return db.query_result.duplicate()


## Returns Dictionary for one skill by id. Empty {} if not found.
func get_skill(skill_id: int) -> Dictionary:
	db.select_rows("Skills", "skill_id = %d" % skill_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — SKILL UPGRADES
# ─────────────────────────────────────────────────────────────────────────────

## Returns Dictionary for a specific (skill_id, tier) pair. Empty {} if not found.
func get_skill_upgrade(skill_id: int, tier: int) -> Dictionary:
	db.select_rows("Skill_Upgrades",
		"skill_id = %d AND upgrade_tier = %d" % [skill_id, tier], ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Returns all 4 upgrade tier rows for a skill (tiers 0–3).
func get_all_tiers(skill_id: int) -> Array:
	db.select_rows("Skill_Upgrades", "skill_id = %d" % skill_id, ["*"])
	return db.query_result.duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — MONSTERS
# ─────────────────────────────────────────────────────────────────────────────

## Returns Dictionary for one monster by id. Empty {} if not found.
func get_monster(monster_id: int) -> Dictionary:
	db.select_rows("Monsters", "monster_id = %d" % monster_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — POTIONS
# ─────────────────────────────────────────────────────────────────────────────

## Returns Dictionary for one potion blueprint by id. Empty {} if not found.
func get_potion(pot_id: int) -> Dictionary:
	db.select_rows("Potions", "pot_id = %d" % pot_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER STATUS
# ─────────────────────────────────────────────────────────────────────────────

## Returns full Player_Status row. Empty {} if no active save.
func get_player() -> Dictionary:
	db.select_rows("Player_Status", "player_id = 1", ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Inserts a new Player_Status row. Call from start_new_game() only.
## Reads class base_hp for starting HP. Returns true on success.
func create_player(chosen_class: String, starting_node_id: int = 1) -> bool:
	var class_data := get_class_data(chosen_class)
	if class_data.is_empty():
		push_error("DatabaseManager.create_player: Unknown class '%s'." % chosen_class)
		return false

	return db.insert_row("Player_Status", {
		"player_id":       1,
		"player_class":    chosen_class,
		"current_hp":      class_data["base_hp"],
		"max_hp":          class_data["base_hp"],
		"current_sp":      GameState.max_sp_for_class(chosen_class),
		"current_ult_pts": 0,
		"upg_pts_bank":    0,
		"current_node_id": starting_node_id
	})


## Updates current_hp and emits player_hp_changed(new_hp, max_hp).
func update_player_hp(new_hp: int) -> bool:
	var player := get_player()
	if player.is_empty():
		return false
	var ok := db.update_rows("Player_Status", "player_id = 1", {"current_hp": new_hp})
	if ok:
		player_hp_changed.emit(new_hp, player["max_hp"])
	return ok


## Updates current_sp (remaining SP this turn). Called at turn start and after spending SP.
func update_player_sp(new_sp: int) -> bool:
	return db.update_rows("Player_Status", "player_id = 1", {"current_sp": new_sp})


## Updates current_ult_pts. Caller must clamp to [0, GameState.ULT_PTS_MAX] before calling.
func update_player_ult_pts(new_pts: int) -> bool:
	return db.update_rows("Player_Status", "player_id = 1", {"current_ult_pts": new_pts})


## Moves player to a new node and emits player_moved(new_node_id).
func update_player_location(node_id: int) -> bool:
	var ok := db.update_rows("Player_Status", "player_id = 1", {"current_node_id": node_id})
	if ok:
		GameState.current_node_id = node_id
		player_moved.emit(node_id)
	return ok


## Adds upgrade points won from combat drops.
func add_upg_pts(amount: int) -> bool:
	var player := get_player()
	if player.is_empty():
		return false
	return db.update_rows("Player_Status", "player_id = 1",
		{"upg_pts_bank": player["upg_pts_bank"] + amount})


## Spends upgrade points (e.g., at upgrade screen). Returns false if insufficient.
func spend_upg_pts(amount: int) -> bool:
	var player := get_player()
	if player.is_empty() or player["upg_pts_bank"] < amount:
		return false
	return db.update_rows("Player_Status", "player_id = 1",
		{"upg_pts_bank": player["upg_pts_bank"] - amount})


## Wipes all runtime player data. Deletes in FK dependency order (children first).
## Also resets the dungeon floor cleared state.
func delete_player() -> void:
	db.delete_rows("Player_Skills_Status", "player_id = 1")
	db.delete_rows("Player_Inventory",     "player_id = 1")
	db.delete_rows("Player_Status",        "player_id = 1")
	db.query("UPDATE Dungeon_Floor SET is_cleared = 0;")


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER SKILLS
# ─────────────────────────────────────────────────────────────────────────────

## Returns Array[Dictionary] of all player skills joined with full skill and upgrade data.
## Each dict has: skill_id, current_tier, skill_name, atk_type, ult_pts_mod, sp_cost, dmg_multiplier
func get_player_skills() -> Array:
	db.query("""
		SELECT pss.skill_id, pss.current_tier,
		       s.skill_name, s.atk_type, s.ult_pts_mod,
		       su.sp_cost, su.dmg_multiplier
		FROM Player_Skills_Status pss
		JOIN Skills s
		  ON pss.skill_id = s.skill_id
		JOIN Skill_Upgrades su
		  ON pss.skill_id = su.skill_id
		 AND pss.current_tier = su.upgrade_tier
		WHERE pss.player_id = 1;
	""")
	return db.query_result.duplicate()


## Returns one player skill row with full joined data. Empty {} if not found.
func get_player_skill(skill_id: int) -> Dictionary:
	db.query("""
		SELECT pss.skill_id, pss.current_tier,
		       s.skill_name, s.atk_type, s.ult_pts_mod,
		       su.sp_cost, su.dmg_multiplier
		FROM Player_Skills_Status pss
		JOIN Skills s
		  ON pss.skill_id = s.skill_id
		JOIN Skill_Upgrades su
		  ON pss.skill_id = su.skill_id
		 AND pss.current_tier = su.upgrade_tier
		WHERE pss.player_id = 1 AND pss.skill_id = %d;
	""" % skill_id)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Grants a skill to the player at tier 0. Use during new game setup.
func add_player_skill(skill_id: int) -> bool:
	return db.insert_row("Player_Skills_Status", {
		"player_id":    1,
		"skill_id":     skill_id,
		"current_tier": 0
	})


## Upgrades a player skill by 1 tier. Returns false if already at tier 3 or not found.
func upgrade_skill(skill_id: int) -> bool:
	var skill := get_player_skill(skill_id)
	if skill.is_empty():
		push_error("DatabaseManager.upgrade_skill: Skill %d not on player." % skill_id)
		return false
	if skill["current_tier"] >= 3:
		return false  # already max tier
	return db.update_rows("Player_Skills_Status",
		"player_id = 1 AND skill_id = %d" % skill_id,
		{"current_tier": skill["current_tier"] + 1})


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER INVENTORY
# ─────────────────────────────────────────────────────────────────────────────

## Returns Array[Dictionary] of inventory slots joined with potion blueprint data.
## Each dict has: inv_id, pot_id, pot_name, pot_type, potency_value
func get_inventory() -> Array:
	db.query("""
		SELECT pi.inv_id, pi.pot_id,
		       p.pot_name, p.pot_type, p.potency_value
		FROM Player_Inventory pi
		JOIN Potions p ON pi.pot_id = p.pot_id
		WHERE pi.player_id = 1;
	""")
	return db.query_result.duplicate()


## Returns current number of held items. Max capacity is 3 (enforced in add_to_inventory).
func get_inventory_count() -> int:
	db.query("SELECT COUNT(*) AS cnt FROM Player_Inventory WHERE player_id = 1;")
	if db.query_result.is_empty():
		return 0
	return db.query_result[0].get("cnt", 0)


## Adds a potion to inventory. Enforces 3-slot cap. Returns false if full.
func add_to_inventory(pot_id: int) -> bool:
	if get_inventory_count() >= 3:
		return false
	return db.insert_row("Player_Inventory", {"player_id": 1, "pot_id": pot_id})


## Removes one inventory slot by inv_id (call after using or discarding a potion).
func remove_from_inventory(inv_id: int) -> bool:
	return db.delete_rows("Player_Inventory",
		"inv_id = %d AND player_id = 1" % inv_id)


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — DUNGEON FLOOR
# ─────────────────────────────────────────────────────────────────────────────

## Returns Dictionary for one dungeon node. Empty {} if not found.
func get_dungeon_node(node_id: int) -> Dictionary:
	db.select_rows("Dungeon_Floor", "node_id = %d" % node_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Returns Array[Dictionary] of reachable child nodes from a given node.
## Each dict has: direction ("LEFT"|"RIGHT"), node_id, stage_type, is_cleared, monster_id.
## Use this to populate the map path buttons.
func get_available_paths(node_id: int) -> Array:
	db.query("""
		SELECT 'LEFT' AS direction,
		       c.node_id, c.stage_type, c.is_cleared, c.monster_id
		FROM Dungeon_Floor p
		JOIN Dungeon_Floor c ON c.node_id = p.child_left_id
		WHERE p.node_id = %d AND p.child_left_id IS NOT NULL
		UNION ALL
		SELECT 'RIGHT' AS direction,
		       c.node_id, c.stage_type, c.is_cleared, c.monster_id
		FROM Dungeon_Floor p
		JOIN Dungeon_Floor c ON c.node_id = p.child_right_id
		WHERE p.node_id = %d AND p.child_right_id IS NOT NULL;
	""" % [node_id, node_id])
	return db.query_result.duplicate()


## Marks a node as cleared (is_cleared = 1). Call after combat victory or event completion.
func mark_node_cleared(node_id: int) -> bool:
	return db.update_rows("Dungeon_Floor", "node_id = %d" % node_id, {"is_cleared": 1})


## Resets all floor nodes to uncleared. Called as part of delete_player() on new game.
func reset_floor() -> bool:
	return db.query("UPDATE Dungeon_Floor SET is_cleared = 0;")


# ─────────────────────────────────────────────────────────────────────────────
# COMPOSITE HELPERS — GAME FLOW
# ─────────────────────────────────────────────────────────────────────────────

## Full new game setup wrapped in a transaction.
## Wipes old save → creates player → grants class skills → syncs GameState.
## Returns true on full success, false on any failure (auto-rolls back).
func start_new_game(chosen_class: String) -> bool:
	delete_player()

	if not create_player(chosen_class):
		push_error("DatabaseManager.start_new_game: create_player failed.")
		return false

	var skills := get_skills_for_class(chosen_class)
	if skills.is_empty():
		push_error("DatabaseManager.start_new_game: No skills found for class '%s'." % chosen_class)
		return false

	for skill in skills:
		if not add_player_skill(skill["skill_id"]):
			push_error("DatabaseManager.start_new_game: Failed to grant skill %d." % skill["skill_id"])
			return false

	# Sync runtime state
	GameState.player_class    = chosen_class
	GameState.current_node_id = 1
	GameState.enemy_id        = -1

	return true


## Returns all data needed to start a combat encounter at a node.
## Returns {"node": {...}, "monster": {...}, "player": {...}}
## Returns empty {} if node has no monster or data is missing.
func get_combat_data(node_id: int) -> Dictionary:
	var node := get_dungeon_node(node_id)
	if node.is_empty() or node.get("monster_id") == null:
		return {}

	var monster := get_monster(node["monster_id"])
	var player  := get_player()

	if monster.is_empty() or player.is_empty():
		return {}

	return {"node": node, "monster": monster, "player": player}
	