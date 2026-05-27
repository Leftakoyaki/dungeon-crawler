extends Node

# The SQLite plugin class wrapper
var db: SQLite = null
const DB_PATH: String = "user://dungeon_crawler.db" # Saves safely in user's local AppData directory

func _ready() -> void:
	# 1. Initialize and open the database connection stream
	db = SQLite.new()
	db.path = DB_PATH
	db.open_db()
	
	# 2. Build the structural layout
	create_static_tables()
	create_runtime_tables()
	seed_static_data()
	
	print("🎉 DATABASE bedrock initialized perfectly without errors!")

func create_static_tables() -> void:
	# Classes Table
	db.query("CREATE TABLE IF NOT EXISTS Classes (
		class_name TEXT PRIMARY KEY,
		base_hp INTEGER NOT NULL,
		base_atk INTEGER NOT NULL,
		passive_description TEXT NOT NULL
	);")
	
	# Skills Master Registry (2NF Base Info)
	db.query("CREATE TABLE IF NOT EXISTS Skills (
		skill_id INTEGER PRIMARY KEY AUTOINCREMENT,
		skill_name TEXT NOT NULL,
		atk_type TEXT NOT NULL,
		class_restriction TEXT NOT NULL,
		ult_points_mod INTEGER NOT NULL,
		FOREIGN KEY (class_restriction) REFERENCES Classes(class_name)
	);")
	
	# Skill Upgrades Balance Matrix (Composite Primary Key)
	db.query("CREATE TABLE IF NOT EXISTS Skill_Upgrades (
		skill_id INTEGER,
		upgrade_tier INTEGER,
		sp_cost INTEGER NOT NULL,
		damage_multiplier REAL NOT NULL,
		PRIMARY KEY (skill_id, upgrade_tier),
		FOREIGN KEY (skill_id) REFERENCES Skills(skill_id)
	);")
	
	# Monsters Table
	db.query("CREATE TABLE IF NOT EXISTS Monsters (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		max_hp INTEGER NOT NULL,
		attack_power INTEGER NOT NULL,
		monster_type TEXT NOT NULL,
		potion_drop_chance REAL NOT NULL,
		upgrade_point_chance REAL NOT NULL
	);")
	
	# Potions Blueprints
	db.query("CREATE TABLE IF NOT EXISTS Potions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		potion_type TEXT NOT NULL,
		potency_value REAL NOT NULL
	);")

func create_runtime_tables() -> void:
	# Dungeon Floor Graph Layout Nodes
	db.query("CREATE TABLE IF NOT EXISTS Dungeon_Floor (
		node_id INTEGER PRIMARY KEY,
		stage_type TEXT NOT NULL,
		monster_id INTEGER,
		is_cleared INTEGER NOT NULL DEFAULT 0,
		child_left_id INTEGER,
		child_right_id INTEGER,
		FOREIGN KEY (monster_id) REFERENCES Monsters(id),
		FOREIGN KEY (child_left_id) REFERENCES Dungeon_Floor(node_id),
		FOREIGN KEY (child_right_id) REFERENCES Dungeon_Floor(node_id)
	);")

	# Live Active Player Vitals
	db.query("CREATE TABLE IF NOT EXISTS Player_Status (
		player_id INTEGER PRIMARY KEY,
		character_class TEXT,
		current_hp INTEGER NOT NULL,
		max_hp INTEGER NOT NULL,
		current_sp INTEGER NOT NULL,
		current_ult_points INTEGER NOT NULL,
		upgrade_points_bank INTEGER NOT NULL,
		current_node_id INTEGER,
		FOREIGN KEY (character_class) REFERENCES Classes(class_name),
		FOREIGN KEY (current_node_id) REFERENCES Dungeon_Floor(node_id)
	);")
	
	# Live Upgraded Skill Tracker (Using the Composite Foreign Key Fix!)
	db.query("CREATE TABLE IF NOT EXISTS Player_Skills_Status (
		player_id INTEGER,
		skill_id INTEGER,
		current_tier INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (player_id, skill_id),
		FOREIGN KEY (player_id) REFERENCES Player_Status(player_id),
		FOREIGN KEY (skill_id, current_tier) REFERENCES Skill_Upgrades(skill_id, upgrade_tier)
	);")
	
	# Live Player Inventory (Strict 3-slot cap checked by game script counts)
	db.query("CREATE TABLE IF NOT EXISTS Player_Inventory (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		player_id INTEGER,
		potion_id INTEGER,
		FOREIGN KEY (player_id) REFERENCES Player_Status(player_id),
		FOREIGN KEY (potion_id) REFERENCES Potions(id)
	);")

func seed_static_data() -> void:
	# 1. SEED CLASSES
	db.query("SELECT COUNT(*) as count FROM Classes;")
	if db.query_result[0]["count"] == 0:
		db.query("INSERT INTO Classes VALUES ('MAGE', 70, 15, 'Normal and skill actions build Ult points.');")
		db.query("INSERT INTO Classes VALUES ('BERSERKER', 120, 10, '1.5x damage when HP drops below 30%.');")
		db.query("INSERT INTO Classes VALUES ('ARCHER', 90, 12, 'Permanent 15% passive evasion chance.');")
		print("🌱 Static Classes data seeded!")

	# 2. SEED MASTER SKILLS REGISTRY (2NF)
	db.query("SELECT COUNT(*) as count FROM Skills;")
	if db.query_result[0]["count"] == 0:
		db.query("INSERT INTO Skills VALUES (1, 'Staff Bash', 'NORMAL', 'MAGE', 1);")
		db.query("INSERT INTO Skills VALUES (2, 'Fireball', 'SKILL', 'MAGE', 1);")
		db.query("INSERT INTO Skills VALUES (3, 'Meteor Shower', 'ULTIMATE', 'MAGE', -2);")
		db.query("INSERT INTO Skills VALUES (4, 'Heavy Slash', 'NORMAL', 'BERSERKER', 0);")
		db.query("INSERT INTO Skills VALUES (5, 'Blood Rage', 'SKILL', 'BERSERKER', 1);")
		db.query("INSERT INTO Skills VALUES (6, 'World Breaker', 'ULTIMATE', 'BERSERKER', -2);")
		db.query("INSERT INTO Skills VALUES (7, 'Quick Shot', 'NORMAL', 'ARCHER', 0);")
		db.query("INSERT INTO Skills VALUES (8, 'Piercing Arrow', 'SKILL', 'ARCHER', 1);")
		db.query("INSERT INTO Skills VALUES (9, 'Arrow Rain', 'ULTIMATE', 'ARCHER', -2);")
		print("🔮 Static Skills master registry seeded!")

	# 3. SEED SKILL UPGRADES MATRIX
	db.query("SELECT COUNT(*) as count FROM Skill_Upgrades;")
	if db.query_result[0]["count"] == 0:
		# Mage Upgrades
		db.query("INSERT INTO Skill_Upgrades VALUES (1, 0, 1, 1.0);") # Staff Bash T0
		db.query("INSERT INTO Skill_Upgrades VALUES (1, 1, 1, 1.5);") # Staff Bash T1
		db.query("INSERT INTO Skill_Upgrades VALUES (2, 0, 4, 2.2);") # Fireball T0
		db.query("INSERT INTO Skill_Upgrades VALUES (2, 1, 4, 2.6);") # Fireball T1
		db.query("INSERT INTO Skill_Upgrades VALUES (2, 2, 3, 3.0);") # Fireball T2
		db.query("INSERT INTO Skill_Upgrades VALUES (2, 3, 2, 3.5);") # Fireball T3
		db.query("INSERT INTO Skill_Upgrades VALUES (3, 0, 5, 4.5);") # Meteor Shower T0
		db.query("INSERT INTO Skill_Upgrades VALUES (3, 1, 5, 5.5);") # Meteor Shower T1
		db.query("INSERT INTO Skill_Upgrades VALUES (3, 2, 5, 6.5);") # Meteor Shower T2
		db.query("INSERT INTO Skill_Upgrades VALUES (3, 3, 5, 8.0);") # Meteor Shower T3
		
		# Berserker Upgrades
		db.query("INSERT INTO Skill_Upgrades VALUES (4, 0, 1, 1.0);") # Heavy Slash T0
		db.query("INSERT INTO Skill_Upgrades VALUES (4, 1, 1, 1.5);") # Heavy Slash T1
		db.query("INSERT INTO Skill_Upgrades VALUES (5, 0, 4, 2.0);") # Blood Rage T0
		db.query("INSERT INTO Skill_Upgrades VALUES (5, 1, 4, 2.5);") # Blood Rage T1
		db.query("INSERT INTO Skill_Upgrades VALUES (5, 2, 3, 3.0);") # Blood Rage T2
		db.query("INSERT INTO Skill_Upgrades VALUES (5, 3, 2, 3.5);") # Blood Rage T3
		db.query("INSERT INTO Skill_Upgrades VALUES (6, 0, 5, 4.0);") # World Breaker T0
		db.query("INSERT INTO Skill_Upgrades VALUES (6, 1, 5, 5.0);") # World Breaker T1
		db.query("INSERT INTO Skill_Upgrades VALUES (6, 2, 5, 6.5);") # World Breaker T2
		db.query("INSERT INTO Skill_Upgrades VALUES (6, 3, 5, 8.5);") # World Breaker T3
		
		# Archer Upgrades
		db.query("INSERT INTO Skill_Upgrades VALUES (7, 0, 1, 1.0);") # Quick Shot T0
		db.query("INSERT INTO Skill_Upgrades VALUES (7, 1, 1, 1.5);") # Quick Shot T1
		db.query("INSERT INTO Skill_Upgrades VALUES (8, 0, 4, 2.1);") # Piercing Arrow T0
		db.query("INSERT INTO Skill_Upgrades VALUES (8, 1, 4, 2.4);") # Piercing Arrow T1
		db.query("INSERT INTO Skill_Upgrades VALUES (8, 2, 3, 2.9);") # Piercing Arrow T2
		db.query("INSERT INTO Skill_Upgrades VALUES (8, 3, 2, 3.4);") # Piercing Arrow T3
		db.query("INSERT INTO Skill_Upgrades VALUES (9, 0, 5, 4.2);") # Arrow Rain T0
		db.query("INSERT INTO Skill_Upgrades VALUES (9, 1, 5, 5.2);") # Arrow Rain T1
		db.query("INSERT INTO Skill_Upgrades VALUES (9, 2, 5, 6.2);") # Arrow Rain T2
		db.query("INSERT INTO Skill_Upgrades VALUES (9, 3, 5, 7.8);") # Arrow Rain T3
		print("⚡ Static Skill Upgrades scaling matrix seeded!")

	# 4. SEED MONSTERS CONFIGURATION
	db.query("SELECT COUNT(*) as count FROM Monsters;")
	if db.query_result[0]["count"] == 0:
		db.query("INSERT INTO Monsters VALUES (1, 'Skeletal Sentry', 45, 8, 'NORMAL', 0.40, 0.05);")
		db.query("INSERT INTO Monsters VALUES (2, 'Feral Goblin', 35, 12, 'NORMAL', 0.40, 0.05);")
		db.query("INSERT INTO Monsters VALUES (3, 'Void Imp', 40, 10, 'NORMAL', 0.40, 0.05);")
		db.query("INSERT INTO Monsters VALUES (4, 'Armored Orc Chieftain', 110, 18, 'ELITE', 0.20, 0.60);")
		db.query("INSERT INTO Monsters VALUES (5, 'Shadow Stalker', 85, 24, 'ELITE', 0.20, 0.60);")
		db.query("INSERT INTO Monsters VALUES (6, 'The Corrupted Dragon', 350, 30, 'BOSS', 0.00, 0.00);")
		print("👹 Static Monsters data seeded!")

	# 5. SEED POTIONS BLUEPRINTS
	db.query("SELECT COUNT(*) as count FROM Potions;")
	if db.query_result[0]["count"] == 0:
		db.query("INSERT INTO Potions VALUES (1, 'Minor Health Potion', 'HEAL', 25.0);")
		db.query("INSERT INTO Potions VALUES (2, 'Elixir of Greater Healing', 'HEAL', 60.0);")
		db.query("INSERT INTO Potions VALUES (3, 'Combat Steroid', 'DAMAGE_BUFF', 1.3);")
		db.query("INSERT INTO Potions VALUES (4, 'Adrenaline Shot', 'SP_RECOVER', 3.0);")
		print("🧪 Static Potions catalog blueprints seeded!")
