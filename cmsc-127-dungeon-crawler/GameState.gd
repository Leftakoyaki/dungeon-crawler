extends Node

# ─────────────────────────────────────────────────────────────────────────────
# GameState.gd  —  Autoload singleton
#
# Owns all runtime-only state that GDScript tracks instead of the DB.
# Sync this from the DB on game load; reset it on new game.
#
# Load order: GameState must be registered BEFORE DatabaseManager in
# Project > Project Settings > Autoload so DatabaseManager._ready() can
# safely call GameState functions.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Runtime Identity ────────────────────────────────────────────────────────
var player_id: int      = 1   # Always 1 — single active run
var player_class: String = ""
var current_node_id: int = -1
var enemy_id: int        = -1  # monster_id of current encounter; -1 = not in combat

# ─── Combat buffs — consumed on next hit, tracked here not in DB ─────────────
var atk_buff_multiplier: float = 1.0  # set by DAMAGE_BUFF potion, reset after one hit

# ─── SP Cap — tracked here, NOT in DB ────────────────────────────────────────
# current_sp in Player_Status tracks SP *remaining this turn*.
# These constants define the per-turn maximum per class.
# TODO: Adjust values to match your final game balance.
const SP_MAX_BY_CLASS: Dictionary = {
	"MAGE":      4,
	"BERSERKER": 3,
	"ARCHER":    3,
}

# ─── Ult Points Cap — tracked here for reference ─────────────────────────────
# Actual current value lives in Player_Status.current_ult_pts.
# GDScript clamps to this before calling DatabaseManager.update_player_ult_pts().
const ULT_PTS_MAX: int = 2

# ─── SP Helpers ──────────────────────────────────────────────────────────────

## Returns max SP per turn for the given class name.
## Returns 3 as a safe default for unknown classes.
func max_sp_for_class(cls_name: String) -> int:
	return SP_MAX_BY_CLASS.get(cls_name, 3)

## Returns max SP per turn for the currently loaded player class.
func current_max_sp() -> int:
	return max_sp_for_class(player_class)

# ─── State Management ────────────────────────────────────────────────────────

## Syncs GameState vars from DB. Call this on game load (continue save).
func sync_from_db() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_warning("GameState.sync_from_db: No active player found in DB.")
		return
	player_class    = player["player_class"]
	current_node_id = player["current_node_id"]
	enemy_id        = -1

## Resets all runtime state. Call before starting a new game.
func reset() -> void:
	player_class         = ""
	current_node_id      = -1
	enemy_id             = -1
	atk_buff_multiplier  = 1.0
