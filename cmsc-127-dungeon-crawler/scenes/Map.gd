extends Control
const STAGE_SPRITES: Dictionary = {
	"START":  "res://assets/LEVEL SPRITES/START LEVEL.png",
	"NORMAL": "res://assets/LEVEL SPRITES/NORMAL ENEMY LEVEL.png",
	"ELITE":  "res://assets/LEVEL SPRITES/ELITE ENEMY LEVEL.png",
	"EVENT":  "res://assets/LEVEL SPRITES/EVENT LEVEL.png",
	"REST":   "res://assets/LEVEL SPRITES/REST LEVEL.png",
	"BOSS":   "res://assets/LEVEL SPRITES/BOSS LEVEL.png"
}

func _get_sprite_for_stage(stage: String) -> Texture2D:
	return load(STAGE_SPRITES.get(stage, "res://assets/LEVEL SPRITES/NORMAL ENEMY LEVEL.png"))
# Hard-coded connections matching the new 8-node Dungeon_Floor seed data.
const CONNECTIONS: Array = [
	[1, 2], [1, 3],
	[2, 4], [2, 5],
	[3, 6],
	[4, 7],
	[5, 7],
	[6, 7],
	[7, 8],
]

const NODE_BTN_SIZE: Vector2 = Vector2(90, 55)
const STATS_BAR_H:   float   = 52.0
const INFO_BAR_H:    float   = 52.0

var node_positions: Dictionary = {}
var all_nodes:      Dictionary = {}

@onready var hp_label:      Label  = $StatsBar/HBoxContainer/HPLabel
@onready var sp_label:      Label  = $StatsBar/HBoxContainer/SPLabel
@onready var ult_label:     Label  = $StatsBar/HBoxContainer/UltLabel
@onready var upg_label:     Label  = $StatsBar/HBoxContainer/UpgLabel
@onready var upgrade_btn:   Button = $StatsBar/HBoxContainer/UpgradeButton
@onready var info_label:    Label  = $InfoPanel/InfoLabel


func _ready() -> void:
	_calculate_positions()
	_load_all_nodes()
	_refresh_stats()
	_build_node_buttons()
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	queue_redraw()


func _on_upgrade_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/UpgradeScreen.tscn")


# ─── Position calculation ─────────────────────────────────────────────────────
#
# Layout (8 nodes):
#        1 (START)
#       / \
#      3   2       ← left=EVENT, right=NORMAL
#      |   |\ 
#      6   4  5    ← 6=ELITE, 4=NORMAL, 5=REST
#       \  | /
#        \ |/
#          7       ← REST
#          |
#          8       ← BOSS

const X_NUDGE: Dictionary = {
	1:  0.00,
	2:  0.03,
	3: -0.03,
	4:  0.05,
	5: -0.02,
	6: -0.05,
	7:  0.00,
	8:  0.00,
}

const Y_NUDGE: Dictionary = {
	1:  0.000,
	2: -0.015,
	3:  0.015,
	4:  0.010,
	5: -0.010,
	6:  0.000,
	7:  0.000,
	8:  -0.050,
}
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)
		
func _calculate_positions() -> void:
	var vp:     Vector2 = get_viewport_rect().size
	var w:      float   = vp.x
	var h:      float   = vp.y
	var top:    float   = STATS_BAR_H + 10.0
	var usable: float   = h - top - INFO_BAR_H - 10.0

	var margin_x: float = NODE_BTN_SIZE.x * 0.5 + 12.0
	var margin_y: float = NODE_BTN_SIZE.y * 0.5 + 6.0

	# 6 rows for 8 nodes
	var rows: Array = [0.04, 0.22, 0.44, 0.66, 0.84, 0.96]

	var base_x: Dictionary = {
		1: 0.50,
		2: 0.65, 3: 0.35,
		4: 0.65, 5: 0.50, 6: 0.35,
		7: 0.50,
		8: 0.50,
	}

	var row_for_node: Dictionary = {
		1: 0,
		2: 1, 3: 1,
		4: 2, 5: 2, 6: 2,
		7: 3,
		8: 5,
	}

	node_positions = {}
	for node_id in base_x.keys():
		var raw_x: float = w * (base_x[node_id] + X_NUDGE[node_id])
		var raw_y: float = top + usable * (rows[row_for_node[node_id]] + Y_NUDGE[node_id])

		var safe_x: float = clampf(raw_x, margin_x, w - margin_x)
		var safe_y: float = clampf(raw_y, top + margin_y, h - INFO_BAR_H - margin_y)

		node_positions[node_id] = Vector2(safe_x, safe_y)


# ─── Load node data ───────────────────────────────────────────────────────────

func _load_all_nodes() -> void:
	for i in range(1, 9):  # 1 to 8
		var data: Dictionary = DatabaseManager.get_dungeon_node(i)
		if not data.is_empty():
			all_nodes[i] = data


# ─── Stats bar ────────────────────────────────────────────────────────────────

func _refresh_stats() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		return
	hp_label.text  = "HP %d/%d"  % [player["current_hp"],      player["max_hp"]]
	sp_label.text  = "SP %d/%d"  % [player["current_sp"],      player["max_sp"]]
	ult_label.text = "ULT %d/%d" % [player["current_ult_pts"], GameState.ULT_PTS_MAX]
	upg_label.text = "UPG %d"    % player["upg_pts_bank"]


# ─── Build node buttons ───────────────────────────────────────────────────────
func _build_node_buttons() -> void:
	for child in get_children():
		if child is TextureButton: # Changed from Button
			child.queue_free()

	var reachable: Array = _get_reachable_ids()

	for node_id in node_positions.keys():
		var pos:  Vector2    = node_positions[node_id]
		var data: Dictionary = all_nodes.get(node_id, {})
		
		# Create a TextureButton
		var btn := TextureButton.new()
		var stage: String = data.get("stage_type", "NORMAL")
		
		btn.texture_normal = _get_sprite_for_stage(stage)
		btn.custom_minimum_size = NODE_BTN_SIZE
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.position = pos - NODE_BTN_SIZE * 0.5


# Create a Label to hold the emoji/number
		var lbl := Label.new()
		lbl.text = _node_label(node_id, stage, int(data.get("is_cleared", 0)) == 1)
		
		# Center the label inside the button area
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = NODE_BTN_SIZE
		
		# Add to button
		btn.add_child(lbl)

		# Logic for active/disabled
		btn.disabled = not (node_id in reachable)
		if node_id == GameState.current_node_id:
			btn.modulate = Color(1.0, 1.0, 0.3) # Highlight current
		elif not btn.disabled:
			btn.modulate = Color(1.0, 1.0, 1.0) # Normal
		else:
			btn.modulate = Color(0.3, 0.3, 0.3) # Disabled/Greyed out

		btn.pressed.connect(func(): _travel_to(node_id))
		add_child(btn)


func _get_reachable_ids() -> Array:
	var paths: Array = DatabaseManager.get_available_paths(GameState.current_node_id)
	var ids:   Array = []
	for path in paths:
		ids.append(int(path["node_id"]))
	return ids


func _node_label(node_id: int, stage: String, cleared: bool) -> String:
	var icon: String  = _stage_icon(stage)
	var check: String = " ✓" if cleared else ""
	return "%s %d%s" % [icon, node_id, check]


func _stage_icon(stage: String) -> String:
	match stage:
		"START":  return "●"
		"NORMAL": return "⚔"
		"ELITE":  return "☠"
		"EVENT":  return "?"
		"REST":   return "♥"
		"BOSS":   return "★"
		_:        return "·"


# ─── Draw connection lines ────────────────────────────────────────────────────

func _draw() -> void:
	var reachable: Array = _get_reachable_ids()

	for conn in CONNECTIONS:
		var a: int = conn[0]
		var b: int = conn[1]
		if not (node_positions.has(a) and node_positions.has(b)):
			continue

		var p0: Vector2 = node_positions[a]
		var p3: Vector2 = node_positions[b]

		if a == GameState.current_node_id and b in reachable:
			_draw_bezier_cubic(p0, p3, Color(0.95, 0.85, 0.10, 1.0), 3.0)
		else:
			_draw_bezier_cubic(p0, p3, Color(0.32, 0.32, 0.32, 1.0), 2.0)


func _draw_bezier_cubic(p0: Vector2, p3: Vector2, color: Color, width: float) -> void:
	var dist: float = abs(p3.y - p0.y)
	var pull: float = dist * 0.45

	var p1: Vector2 = p0 + Vector2(0.0,  pull)
	var p2: Vector2 = p3 + Vector2(0.0, -pull)

	var steps: int    = 20
	var prev:  Vector2 = p0

	for i in range(1, steps + 1):
		var t:  float   = float(i) / float(steps)
		var nt: float   = 1.0 - t
		var pt: Vector2 = (
			nt * nt * nt        * p0 +
			3.0 * nt * nt * t   * p1 +
			3.0 * nt * t  * t   * p2 +
			t  * t  * t         * p3
		)
		draw_line(prev, pt, color, width)
		prev = pt


# ─── Navigation ──────────────────────────────────────────────────────────────

func _travel_to(target_node_id: int) -> void:
	DatabaseManager.update_player_location(target_node_id)

	var dest: Dictionary = DatabaseManager.get_dungeon_node(target_node_id)
	if dest.is_empty():
		push_error("Map: destination node %d not found." % target_node_id)
		return

	var stage: String = dest["stage_type"]
	info_label.text = "Entering: %s" % stage

	match stage:
		"NORMAL", "ELITE", "BOSS":
			GameState.enemy_id = int(dest.get("monster_id", -1))
			get_tree().change_scene_to_file("res://scenes/Combat.tscn")
		"REST":
			get_tree().change_scene_to_file("res://scenes/Rest.tscn")
		"EVENT":
			get_tree().change_scene_to_file("res://scenes/Event.tscn")
		_:
			push_error("Map: unknown stage_type '%s'." % stage)
