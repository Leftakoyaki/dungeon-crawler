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
	# Classes Table
	db.query("""
		CREATE TABLE IF NOT EXISTS Classes (
			class_name TEXT PRIMARY KEY,
			base_hp INTEGER NOT NULL,
			base_atk INTEGER NOT NULL,
			base_sp INTEGER NOT NULL,
			passive_description TEXT NOT NULL
		);
	""")

	# Skills Master Registry (2NF Base Info)
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
			is_cleared INTEGER NOT NULL DEFAULT 0,
			child_left_id INTEGER,
			child_right_id INTEGER,
			FOREIGN KEY (child_left_id)   REFERENCES Dungeon_Floor(node_id),
			FOREIGN KEY (child_right_id)  REFERENCES Dungeon_Floor(node_id)
		);
	""")
	db.query("""
		CREATE TABLE IF NOT EXISTS Hosts (
			node_id INTEGER,
			monster_id INTEGER,
			PRIMARY KEY (node_id, monster_id)
			FOREIGN KEY (node_id)   REFERENCES Dungeon_Floor(node_id),
			FOREIGN KEY (monster_id)  REFERENCES Monsters(monster_id)
		);
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS Player_Status (
			player_id INTEGER PRIMARY KEY,
			player_class TEXT NOT NULL,
			current_hp INTEGER NOT NULL,
			max_hp INTEGER NOT NULL,
			current_sp INTEGER NOT NULL,
			max_sp INTEGER NOT NULL,
			current_inv INTEGER NOT NULL,
			max_inv INTEGER NOT NULL,
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
	        inv_id INTEGER NOT NULL CHECK(inv_id IN (1,2,3)),
	        player_id INTEGER NOT NULL,
	        pot_id INTEGER NOT NULL,
	        PRIMARY KEY (inv_id, player_id),
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
	var rows := [
		{
			"class_name":          "MAGE",
			"base_hp":             70,
			"base_atk":            15,
			"base_sp":             5,
			"passive_description": "Arcane Affinity: Normal and skill actions build ult points."
		},
		{
			"class_name":          "WARRIOR",
			"base_hp":             120,
			"base_atk":            10,
			"base_sp":             5,
			"passive_description": "Unyielding Spirit: Increase damage by 1.5x when HP drops below 30%."
		},
		{
			"class_name":          "ARCHER",
			"base_hp":             100,
			"base_atk":            13,
			"base_sp":             5,
			"passive_description": "Eagle Eye: Normal Attacks and Basic Skill have a 30% chance to strike twice."
		},
	]
	for row in rows:
		db.insert_row("Classes", row)


func _seed_skills() -> void:
	var rows := [
		# ── MAGE ──────────────────────────────────────────────────────────
		{"skill_id": 1, "skill_name": "Fireball",        "atk_type": "NORMAL",   "class_restriction": "MAGE",    "ult_pts_mod":  1},
		{"skill_id": 2, "skill_name": "Infernal Blaze",  "atk_type": "SKILL",    "class_restriction": "MAGE",    "ult_pts_mod":  1},
		{"skill_id": 3, "skill_name": "Supernova",       "atk_type": "ULTIMATE", "class_restriction": "MAGE",    "ult_pts_mod": -2},
		# ── WARRIOR ───────────────────────────────────────────────────────
		{"skill_id": 4, "skill_name": "Iron Cleave",     "atk_type": "NORMAL",   "class_restriction": "WARRIOR", "ult_pts_mod":  0},
		{"skill_id": 5, "skill_name": "Crusader's Fury", "atk_type": "SKILL",    "class_restriction": "WARRIOR", "ult_pts_mod":  1},
		{"skill_id": 6, "skill_name": "Kingdom's Ruin",  "atk_type": "ULTIMATE", "class_restriction": "WARRIOR", "ult_pts_mod": -2},
		# ── ARCHER ────────────────────────────────────────────────────────
		{"skill_id": 7, "skill_name": "Arrow Shot",      "atk_type": "NORMAL",   "class_restriction": "ARCHER",  "ult_pts_mod":  0},
		{"skill_id": 8, "skill_name": "Piercing Arrow",  "atk_type": "SKILL",    "class_restriction": "ARCHER",  "ult_pts_mod":  1},
		{"skill_id": 9, "skill_name": "Rain of Arrows",  "atk_type": "ULTIMATE", "class_restriction": "ARCHER",  "ult_pts_mod": -2},
	]
	for row in rows:
		db.insert_row("Skills", row)


func _seed_skill_upgrades() -> void:
	var upgrades: Array = []

	# MAGE
	# NORMAL ATTACK
	upgrades.append({"skill_id": 1, "upgrade_tier": 0, "sp_cost": 1, "dmg_multiplier": 0.6})
	upgrades.append({"skill_id": 1, "upgrade_tier": 1, "sp_cost": 1, "dmg_multiplier": 0.7})
	# BASIC SKILL
	upgrades.append({"skill_id": 2, "upgrade_tier": 0, "sp_cost": 3, "dmg_multiplier": 2.5})
	upgrades.append({"skill_id": 2, "upgrade_tier": 1, "sp_cost": 3, "dmg_multiplier": 3.0})
	upgrades.append({"skill_id": 2, "upgrade_tier": 2, "sp_cost": 2, "dmg_multiplier": 3.0})
	upgrades.append({"skill_id": 2, "upgrade_tier": 3, "sp_cost": 1, "dmg_multiplier": 3.5})
	# ULTIMATE
	upgrades.append({"skill_id": 3, "upgrade_tier": 0, "sp_cost": 5, "dmg_multiplier": 4.5})
	upgrades.append({"skill_id": 3, "upgrade_tier": 1, "sp_cost": 5, "dmg_multiplier": 5.5})
	upgrades.append({"skill_id": 3, "upgrade_tier": 2, "sp_cost": 5, "dmg_multiplier": 6.5})
	upgrades.append({"skill_id": 3, "upgrade_tier": 3, "sp_cost": 5, "dmg_multiplier": 8.0})

	# WARRIOR
	# NORMAL ATTACK
	upgrades.append({"skill_id": 4, "upgrade_tier": 0, "sp_cost": 1, "dmg_multiplier": 0.6})
	upgrades.append({"skill_id": 4, "upgrade_tier": 1, "sp_cost": 1, "dmg_multiplier": 0.7})
	# BASIC SKILL
	upgrades.append({"skill_id": 5, "upgrade_tier": 0, "sp_cost": 3, "dmg_multiplier": 2.2})
	upgrades.append({"skill_id": 5, "upgrade_tier": 1, "sp_cost": 3, "dmg_multiplier": 2.6})
	upgrades.append({"skill_id": 5, "upgrade_tier": 2, "sp_cost": 2, "dmg_multiplier": 2.6})
	upgrades.append({"skill_id": 5, "upgrade_tier": 3, "sp_cost": 1, "dmg_multiplier": 3.0})
	# ULTIMATE
	upgrades.append({"skill_id": 6, "upgrade_tier": 0, "sp_cost": 5, "dmg_multiplier": 4.0})
	upgrades.append({"skill_id": 6, "upgrade_tier": 1, "sp_cost": 5, "dmg_multiplier": 5.0})
	upgrades.append({"skill_id": 6, "upgrade_tier": 2, "sp_cost": 5, "dmg_multiplier": 6.0})
	upgrades.append({"skill_id": 6, "upgrade_tier": 3, "sp_cost": 5, "dmg_multiplier": 7.0})

	# ARCHER
	# NORMAL ATTACK
	upgrades.append({"skill_id": 7, "upgrade_tier": 0, "sp_cost": 1, "dmg_multiplier": 0.53})
	upgrades.append({"skill_id": 7, "upgrade_tier": 1, "sp_cost": 1, "dmg_multiplier": 0.63})
	# BASIC SKILL
	upgrades.append({"skill_id": 8, "upgrade_tier": 0, "sp_cost": 3, "dmg_multiplier": 2.2})
	upgrades.append({"skill_id": 8, "upgrade_tier": 1, "sp_cost": 3, "dmg_multiplier": 2.4})
	upgrades.append({"skill_id": 8, "upgrade_tier": 2, "sp_cost": 3, "dmg_multiplier": 2.6})
	upgrades.append({"skill_id": 8, "upgrade_tier": 3, "sp_cost": 2, "dmg_multiplier": 2.8})
	# ULTIMATE
	upgrades.append({"skill_id": 9, "upgrade_tier": 0, "sp_cost": 5, "dmg_multiplier": 4.0})
	upgrades.append({"skill_id": 9, "upgrade_tier": 1, "sp_cost": 5, "dmg_multiplier": 5.0})
	upgrades.append({"skill_id": 9, "upgrade_tier": 2, "sp_cost": 5, "dmg_multiplier": 6.0})
	upgrades.append({"skill_id": 9, "upgrade_tier": 3, "sp_cost": 5, "dmg_multiplier": 7.0})

	for row in upgrades:
		db.insert_row("Skill_Upgrades", row)


func _seed_monsters() -> void:
	var rows := [
		{"monster_id": 1, "mon_name": "Troll",          "max_hp": 45,  "attack_power": 8,  "monster_type": "NORMAL", "pot_drop_chance": 0.4, "upg_point_chance": 0.05},
		{"monster_id": 2, "mon_name": "Jumping Demon", "max_hp": 35,  "attack_power": 12, "monster_type": "NORMAL", "pot_drop_chance": 0.4, "upg_point_chance": 0.05},
		{"monster_id": 3, "mon_name": "Dark Knight",   "max_hp": 40,  "attack_power": 10, "monster_type": "NORMAL", "pot_drop_chance": 0.4, "upg_point_chance": 0.05},
		{"monster_id": 4, "mon_name": "Nightmare",     "max_hp": 110, "attack_power": 18, "monster_type": "ELITE",  "pot_drop_chance": 0.20, "upg_point_chance": 0.60},
		{"monster_id": 5, "mon_name": "Centaur",       "max_hp": 85,  "attack_power": 24, "monster_type": "ELITE",  "pot_drop_chance": 0.20, "upg_point_chance": 0.60},
		{"monster_id": 6, "mon_name": "Demon",         "max_hp": 200, "attack_power": 25, "monster_type": "BOSS",   "pot_drop_chance": 0.00, "upg_point_chance": 0.00},
	]
	for row in rows:
		db.insert_row("Monsters", row)


func _seed_potions() -> void:
	var rows := [
		{"pot_id": 1, "pot_name": "Health Potion",     "pot_type": "HEAL",        "potency_value": 25.0},
		{"pot_id": 2, "pot_name": "Elixir of Healing", "pot_type": "HEAL",        "potency_value": 60.0},
		{"pot_id": 3, "pot_name": "Attack Elixir",     "pot_type": "DAMAGE_BUFF", "potency_value": 1.3},
		{"pot_id": 4, "pot_name": "Adrenaline Shot",   "pot_type": "SP_RECOVER",  "potency_value": 3.0},
	]
	for row in rows:
		db.insert_row("Potions", row)


func _seed_dungeon_floor() -> void:
	# Randomise which monsters appear each run so all 5 non-boss monsters can be encountered.
	# NORMAL pool: Troll (1), Jumping Demon (2), Dark Knight (3) — pick 2 distinct ones
	# ELITE  pool: Nightmare (4), Centaur (5) — pick 1
	var normal_pool := [1, 2, 3]
	normal_pool.shuffle()
	var normal_1: int = normal_pool[0]
	var normal_2: int = normal_pool[1]
	var elite_id: int = randi_range(4, 5)

	var nodes := [
		{"node_id": 1, "stage_type": "START",  "is_cleared": 0},
		{"node_id": 2, "stage_type": "NORMAL", "is_cleared": 0},
		{"node_id": 3, "stage_type": "EVENT",  "is_cleared": 0},
		{"node_id": 4, "stage_type": "NORMAL", "is_cleared": 0},
		{"node_id": 5, "stage_type": "REST",   "is_cleared": 0},
		{"node_id": 6, "stage_type": "ELITE",  "is_cleared": 0},
		{"node_id": 7, "stage_type": "REST",   "is_cleared": 0},
		{"node_id": 8, "stage_type": "BOSS",   "is_cleared": 0},
	]
	for row in nodes:
		db.insert_row("Dungeon_Floor", row)

	var paths := [
		{"node_id": 1, "left": 3, "right": 2},
		{"node_id": 2, "left": 5, "right": 4},
		{"node_id": 3, "left": 6, "right": null},
		{"node_id": 4, "left": 7, "right": null},
		{"node_id": 5, "left": 7, "right": null},
		{"node_id": 6, "left": 7, "right": null},
		{"node_id": 7, "left": 8, "right": null},
	]
	for p in paths:
		db.update_rows("Dungeon_Floor", "node_id = %d" % p["node_id"], {
			"child_left_id":  p["left"],
			"child_right_id": p["right"]
		})
		
	var hosts := [
		{"node_id": 2, "monster_id": normal_1},
		{"node_id": 4, "monster_id": normal_2},
		{"node_id": 6, "monster_id": elite_id},
		{"node_id": 8, "monster_id": 6},
	]
	for row in hosts:
		db.insert_row("Hosts", row)


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — CLASSES
# ─────────────────────────────────────────────────────────────────────────────

func get_all_classes() -> Array:
	db.select_rows("Classes", "", ["*"])
	return db.query_result.duplicate()


func get_class_data(cls_name: String) -> Dictionary:
	db.select_rows("Classes", "class_name = '%s'" % cls_name, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — SKILLS
# ─────────────────────────────────────────────────────────────────────────────

func get_skills_for_class(cls_name: String) -> Array:
	db.select_rows("Skills", "class_restriction = '%s'" % cls_name, ["*"])
	return db.query_result.duplicate()


func get_skill(skill_id: int) -> Dictionary:
	db.select_rows("Skills", "skill_id = %d" % skill_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — SKILL UPGRADES
# ─────────────────────────────────────────────────────────────────────────────

func get_skill_upgrade(skill_id: int, tier: int) -> Dictionary:
	db.select_rows("Skill_Upgrades",
		"skill_id = %d AND upgrade_tier = %d" % [skill_id, tier], ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func get_all_tiers(skill_id: int) -> Array:
	db.select_rows("Skill_Upgrades", "skill_id = %d" % skill_id, ["*"])
	return db.query_result.duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — MONSTERS
# ─────────────────────────────────────────────────────────────────────────────

func get_monster(monster_id: int) -> Dictionary:
	db.select_rows("Monsters", "monster_id = %d" % monster_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — POTIONS
# ─────────────────────────────────────────────────────────────────────────────

func get_potion(pot_id: int) -> Dictionary:
	db.select_rows("Potions", "pot_id = %d" % pot_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER STATUS
# ─────────────────────────────────────────────────────────────────────────────

func get_player() -> Dictionary:
	db.select_rows("Player_Status", "player_id = 1", ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


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
		"current_sp":      class_data.get("base_sp", 5),
		"max_sp":          class_data.get("base_sp", 5),
		"current_inv":     0,
		"max_inv":         3,
		"current_ult_pts": 0,
		"upg_pts_bank":    0,
		"current_node_id": starting_node_id
	})


func update_player_hp(new_hp: int) -> bool:
	var player := get_player()
	if player.is_empty():
		return false
	var ok := db.update_rows("Player_Status", "player_id = 1", {"current_hp": new_hp})
	if ok:
		player_hp_changed.emit(new_hp, player["max_hp"])
	return ok


func update_player_sp(new_sp: int) -> bool:
	return db.update_rows("Player_Status", "player_id = 1", {"current_sp": new_sp})


func reset_player_sp() -> bool:
	var player := get_player()
	if player.is_empty():
		return false
	return update_player_sp(player["max_sp"])


func update_player_ult_pts(new_pts: int) -> bool:
	return db.update_rows("Player_Status", "player_id = 1", {"current_ult_pts": new_pts})


func update_player_location(node_id: int) -> bool:
	var ok := db.update_rows("Player_Status", "player_id = 1", {"current_node_id": node_id})
	if ok:
		reset_player_sp()
		GameState.current_node_id = node_id
		player_moved.emit(node_id)
	return ok


func add_upg_pts(amount: int) -> bool:
	var player := get_player()
	if player.is_empty():
		return false
	return db.update_rows("Player_Status", "player_id = 1",
		{"upg_pts_bank": player["upg_pts_bank"] + amount})


func spend_upg_pts(amount: int) -> bool:
	var player := get_player()
	if player.is_empty() or player["upg_pts_bank"] < amount:
		return false
	return db.update_rows("Player_Status", "player_id = 1",
		{"upg_pts_bank": player["upg_pts_bank"] - amount})


func delete_player() -> void:
	db.delete_rows("Player_Skills_Status", "player_id = 1")
	db.delete_rows("Player_Inventory",     "player_id = 1")
	db.delete_rows("Player_Status",        "player_id = 1")
	db.query("UPDATE Dungeon_Floor SET is_cleared = 0;")


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER SKILLS
# ─────────────────────────────────────────────────────────────────────────────

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


func add_player_skill(skill_id: int) -> bool:
	return db.insert_row("Player_Skills_Status", {
		"player_id":    1,
		"skill_id":     skill_id,
		"current_tier": 0
	})


func upgrade_skill(skill_id: int) -> bool:
	var skill := get_player_skill(skill_id)
	if skill.is_empty():
		push_error("DatabaseManager.upgrade_skill: Skill %d not on player." % skill_id)
		return false
	var max_tier: int = 1 if skill_id in [1, 4, 7] else 3
	if skill["current_tier"] >= max_tier:
		return false
	return db.update_rows("Player_Skills_Status",
		"player_id = 1 AND skill_id = %d" % skill_id,
		{"current_tier": skill["current_tier"] + 1})


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — PLAYER INVENTORY
# ─────────────────────────────────────────────────────────────────────────────

func get_inventory() -> Array:
	db.query("""
		SELECT pi.inv_id, pi.pot_id,
		       p.pot_name, p.pot_type, p.potency_value
		FROM Player_Inventory pi
		JOIN Potions p ON pi.pot_id = p.pot_id
		WHERE pi.player_id = 1;
	""")
	return db.query_result.duplicate()


func get_inventory_count() -> int:
	var player := get_player()
	if player.is_empty():
		return 0
	return int(player.get("current_inv", 0))


## Adds a potion to inventory. Enforces 3-slot cap. Returns dict {success, reason}.
func add_to_inventory(pot_id: int) -> Dictionary:
	var player := get_player()
	if player.is_empty():
		return {"success": false, "reason": "NO_PLAYER"}

	if player["current_inv"] >= player["max_inv"]:
		return {"success": false, "reason": "FULL"}

	# Find the first free slot (1, 2, or 3)
	var used_slots: Array = []
	var current_inv := get_inventory()
	for item in current_inv:
		used_slots.append(int(item["inv_id"]))

	var free_slot: int = -1
	for slot in [1, 2, 3]:
		if slot not in used_slots:
			free_slot = slot
			break

	if free_slot == -1:
		return {"success": false, "reason": "FULL"}

	if not db.insert_row("Player_Inventory", {"inv_id": free_slot, "player_id": 1, "pot_id": pot_id}):
		return {"success": false, "reason": "DB_FAIL"}

	var ok: bool = db.update_rows(
		"Player_Status",
		"player_id = 1",
		{"current_inv": player["current_inv"] + 1}
	)

	if not ok:
		return {"success": false, "reason": "DB_FAIL_UPDATE"}

	return {"success": true, "reason": "OK"}


func remove_from_inventory(inv_id: int) -> bool:
	var player := get_player()
	if player.is_empty():
		return false

	if not db.delete_rows("Player_Inventory",
		"inv_id = %d AND player_id = 1" % inv_id):
		return false

	var new_count: int = max(0, int(player["current_inv"]) - 1)

	return db.update_rows(
		"Player_Status",
		"player_id = 1",
		{"current_inv": new_count}
	)


# ─────────────────────────────────────────────────────────────────────────────
# QUERY HELPERS — DUNGEON FLOOR
# ─────────────────────────────────────────────────────────────────────────────

func get_dungeon_node(node_id: int) -> Dictionary:
	db.select_rows("Dungeon_Floor", "node_id = %d" % node_id, ["*"])
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


func get_available_paths(node_id: int) -> Array:
	db.query("""
		SELECT 'LEFT' AS direction,
		       c.node_id, c.stage_type, c.is_cleared,
		       h.monster_id
		FROM Dungeon_Floor p
		JOIN Dungeon_Floor c ON c.node_id = p.child_left_id
		LEFT JOIN Hosts h ON h.node_id = c.node_id
		WHERE p.node_id = %d AND p.child_left_id IS NOT NULL
		UNION ALL
		SELECT 'RIGHT' AS direction,
		       c.node_id, c.stage_type, c.is_cleared,
		       h.monster_id
		FROM Dungeon_Floor p
		JOIN Dungeon_Floor c ON c.node_id = p.child_right_id
		LEFT JOIN Hosts h ON h.node_id = c.node_id
		WHERE p.node_id = %d AND p.child_right_id IS NOT NULL;
	""" % [node_id, node_id])
	return db.query_result.duplicate()


func mark_node_cleared(node_id: int) -> bool:
	return db.update_rows("Dungeon_Floor", "node_id = %d" % node_id, {"is_cleared": 1})
	
func reset_floor() -> bool:
	return db.query("UPDATE Dungeon_Floor SET is_cleared = 0;")


# ─────────────────────────────────────────────────────────────────────────────
# COMPOSITE HELPERS — GAME FLOW
# ─────────────────────────────────────────────────────────────────────────────

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

	GameState.player_class    = chosen_class
	GameState.current_node_id = 1
	GameState.enemy_id        = -1

	return true


func get_combat_data(node_id: int) -> Dictionary:
	var node := get_dungeon_node(node_id)
	if node.is_empty():
		return {}

	db.select_rows("Hosts", "node_id = %d" % node_id, ["monster_id"])
	if db.query_result.is_empty():
		return {}
	var monster_id: int = int(db.query_result[0]["monster_id"])

	var monster := get_monster(monster_id)
	var player  := get_player()

	if monster.is_empty() or player.is_empty():
		return {}

	return {"node": node, "monster": monster, "player": player}
