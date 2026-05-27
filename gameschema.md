# Initial Data Requirements Template

## Project Information

| Attribute | Value |
| :--- | :--- |
| **Project Title:** | RPG Database Game |
| **Group Members:** | Alexis Vince Antolihao, Drebin Aranda, Sean Cassimmere Mayol, John Dexter Rico |
| **Description:** | A database-driven RPG that includes a UI where button actions trigger SQL-like queries. The system will track character progression, class-specific skills, equipment, and a quest system restricted by level or class. |

## Identified Entities

| Entity Name | Description |
| :--- | :--- |
| Classes | Defines base values for the character classes. |
| Skills | Static identity info for each ability — split from Skill_Upgrades for 2NF |
| Skill_Upgrades | Per-tier scaling values only — columns that need both parts of the composite PK |
| Monsters | Stores enemy data configurations and randomized loot drop probabilities. |
| Potions | Blueprints for collectible items. |
| Player_Status | Maintains the immediate vitals of the live player character. |
| Player_Skills_Status | Maps what exact tier version of an attack the player currently owns on this run. |
| Player_Inventory | Tracks currently held potions. The Godot engine handles row count checks to enforce the 3-slot capacity before executing an insert. |
| Dungeon_Floor | The dynamic blueprint representing your hand-drawn map pathways. |

---

## Attributes per Entity

### STATIC ENTITIES

**Entity: Classes**
Defines base values for the character classes.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| class_name | VARCHAR | "MAGE", "BERSERKER", or "ARCHER" | PRIMARY KEY |
| base_hp | INT | Baseline max health pool | NOT NULL |
| base_atk | INT | Flat baseline damage modifier | NOT NULL |
| passive_description | VARCHAR | Description text for the UI | NOT NULL |

**Entity: Skills**
Static identity info for each ability — split from Skill_Upgrades for 2NF

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| skill_id | INT | Unique identity index for the ability | PRIMARY KEY |
| skill_name | VARCHAR | Display name (e.g., "Fireball") | NOT NULL |
| atk_type | VARCHAR | "NORMAL", "SKILL", or "ULTIMATE" | NOT NULL |
| class_restriction | VARCHAR | References Classes(class_name) | FOREIGN KEY |
| ult_pts_mod | INT | Charges (+1) or spends (-2) Ultimate Points | NOT NULL |

**Entity: Skill_Upgrades**
Per-tier scaling values only — columns that need both parts of the composite PK

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| skill_id | INT | Unique identity index for the ability | COMPOSITE PK (Part 1) FOREIGN KEY → Skills |
| upgrade_tier | INT | Tier levels: 0, 1, 2, or 3 | COMPOSITE PK (Part 2) |
| sp_cost | INT | Cost in SP to execute (Ultimates locked at 5) | NOT NULL |
| dmg_multiplier | FLOAT | Base attack multiplier for combat formulas | NOT NULL |

**Entity: Monsters**
Stores enemy data configurations and randomized loot drop probabilities.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| monster_id | INT | Unique enemy identifier | PRIMARY KEY |
| mon_name | VARCHAR | Name displayed in battle | NOT NULL |
| max_hp | INT | Enemy health pool | NOT NULL |
| attack_power | INT | Attack damage dealt to the player | NOT NULL |
| monster_type | VARCHAR | "NORMAL", "ELITE", or "BOSS" | NOT NULL |
| pot_drop_chance | FLOAT | Decimal probability for potion drops (e.g., 0.40) | NOT NULL |
| upg_point_chance | FLOAT | Elite is high (0.60), Normal is low (0.05) | NOT NULL |

**Entity: Potions**
Blueprints for collectible items.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| pot_id | INT | Unique item blueprint index | PRIMARY KEY |
| pot_name | VARCHAR | "Health Potion", "Attack Elixir", etc. | NOT NULL |
| pot_type | VARCHAR | "HEAL", "DAMAGE_BUFF", etc. | NOT NULL |
| potency_value | FLOAT | Flat or percentage formula variable | NOT NULL |

---

### RUNTIME ENTITIES

**Entity: Player_Status**
Maintains the immediate vitals of the live player character.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| player_id | INT | Set to 1 for standard single-player active run | PRIMARY KEY |
| player_class | VARCHAR | References Classes(class_name) | FOREIGN KEY → Classes |
| current_hp | INT | Drops when hit, capped by max_hp | NOT NULL |
| max_hp | INT | Max health ceiling | NOT NULL |
| current_sp | INT | Active SP remaining inside the combat turn | NOT NULL |
| current_ult_pts | INT | Tracks active charge points (0, 1, or 2 max) | NOT NULL |
| upg_pts_bank | INT | Banked upgrade points won/earned (Starts at 0) | NOT NULL |
| current_node_id | INT | References Dungeon_Floor(node_id) | FOREIGN KEY → Dungeon_Floor |

**Entity: Player_Skills_Status**
Maps what exact tier version of an attack the player currently owns on this run.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| player_id | INT | References Player_Status(player_id) | COMPOSITE PK (Part 1) FOREIGN KEY → Player_Status |
| skill_id | INT | References Skill_Upgrades(skill_id) | COMPOSITE PK (Part 2) COMPOSITE FOREIGN KEY (Part 1) → Skill_Upgrades(skill_id) |
| current_tier | INT | Defaults to 0; increments up to 3 | COMPOSITE FOREIGN KEY (Part 2) → Skill_Upgrades(upgrade_tier) |

**Entity: Player_Inventory**
Tracks currently held potions. The Godot engine handles row count checks to enforce the 3-slot capacity before executing an insert.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| inv_id | INT | Unique runtime storage slot ID | PRIMARY KEY AUTOINCREMENT |
| player_id | INT | References active player | FOREIGN KEY → Player_Status |
| pot_id | INT | References Potions(pot_id) | FOREIGN KEY → Potions |

**Entity: Dungeon_Floor**
The dynamic blueprint representing your hand-drawn map pathways.

| Attribute Name | Data Type | Description | Constraint |
| :--- | :--- | :--- | :--- |
| node_id | INT | Tracks the specific node (1 through 10) | PRIMARY KEY |
| stage_type | VARCHAR | "START", "NORMAL", "ELITE", "EVENT", "REST", "BOSS" | NOT NULL |
| monster_id | INT | References Monsters(monster_id); null for non-combat nodes | FOREIGN KEY, NULLABLE |
| is_cleared | BOOLEAN | Flips to 1 upon stage completion | NOT NULL DEFAULT 0 |
| child_left_id | INT | The node index reached by taking the left path | FOREIGN KEY → Dungeon_Floor NULLABLE |
| child_right_id | INT | The node index reached by taking the right path | FOREIGN KEY → Dungeon_Floor NULLABLE |

---

## Relationships Between Entities

*(Note: The extra comma typo in the original document's first row has been preserved in the table structure below).*

| Entities Involved | Relation | Reason |
| :--- | :--- | :--- |
| Classes → Skills | ,One-to-Many | Each class restricts multiple skills via class_restriction FK; each skill belongs to at most one class |
| Skills → Skill_Upgrades | One-to-Many | Each skill has up to 4 upgrade tiers (0–3); each Skill_Upgrades row belongs to exactly one skill via skill_id |
| Classes → Player_Status | One-to-Many | Many runs can share a class; each player belongs to exactly one class via character_class FK |
| Player_Status ↔ Player_Skills_Status | One-to-Many | One player tracks multiple skills; each row is tied to one player via the composite PK (player_id, skill_id) |
| Player_Skills_Status → Skill_Upgrades | Many-to-One | A player's active skill tracking row references a single, concrete (skill_id, upgrade_tier) row inside the master balance upgrade matrix via a composite foreign key. |
| Player_Status ↔ Player_Inventory | One-to-Many | One player holds up to 3 inventory slots; each slot is tied to that player (capacity enforced by the engine) |
| Player_Inventory → Potions | Many-to-One | Multiple slots can reference the same potion blueprint; each slot points to one Potions row via potion_id FK |
| Player_Status → Dungeon_Floor | Many-to-One | The player occupies one node at a time via current_node_id FK; the same node can be the current node across different runs |
| Dungeon_Floor → Monsters | Many-to-One | Each floor node hosts one enemy via a monster_id FK on Dungeon_Floor (added column); the same monster blueprint can appear on multiple nodes |
| Dungeon_Floor ↔ Dungeon_Floor | Self-referential Many-to-Many | Each node can link forward to up to two child nodes via child_left_id and child_right_id, and multiple paths can converge/merge into the same forward node down the line. |