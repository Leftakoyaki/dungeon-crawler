extends Node

# ─────────────────────────────────────────────────────────────────────────────
# GameState.gd  —  Autoload singleton
# ─────────────────────────────────────────────────────────────────────────────

# ─── Cursor Sprites ──────────────────────────────────────────────────────────
var cursor_normal = preload("res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Cursors/Cursor_01.png")
var cursor_clicked = preload("res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Cursors/Cursor_02.png")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			update_cursor(event.pressed)
# ─── Runtime Identity ────────────────────────────────────────────────────────
var player_id: int       = 1  
var player_class: String = ""
var current_node_id: int = -1
var enemy_id: int        = -1 

# ─── Combat buffs ────────────────────────────────────────────────────────────
var atk_buff_multiplier: float = 1.0  

# ─── SP & Ult Caps ───────────────────────────────────────────────────────────
const SP_MAX_BY_CLASS: Dictionary = {
	"MAGE":      4,
	"BERSERKER": 3,
	"ARCHER":    3,
}

const ULT_PTS_MAX: int = 2

# ─── Cursor Logic ────────────────────────────────────────────────────────────
func _ready() -> void:
	Input.set_custom_mouse_cursor(cursor_normal)

func update_cursor(is_pressed: bool) -> void:
	if is_pressed:
		Input.set_custom_mouse_cursor(cursor_clicked)
	else:
		Input.set_custom_mouse_cursor(cursor_normal)

# ─── SP Helpers ──────────────────────────────────────────────────────────────
func max_sp_for_class(cls_name: String) -> int:
	return SP_MAX_BY_CLASS.get(cls_name, 3)

func current_max_sp() -> int:
	return max_sp_for_class(player_class)

# ─── State Management ────────────────────────────────────────────────────────
func sync_from_db() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		push_warning("GameState.sync_from_db: No active player found in DB.")
		return
	player_class    = player["player_class"]
	current_node_id = player["current_node_id"]
	enemy_id        = -1

func reset() -> void:
	player_class         = ""
	current_node_id      = -1
	enemy_id             = -1
	atk_buff_multiplier  = 1.0
