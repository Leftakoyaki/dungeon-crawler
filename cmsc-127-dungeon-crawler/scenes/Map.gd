extends Control

# ─────────────────────────────────────────────────────────────────────────────
# Map.gd — Visual node graph (Slay the Spire style)
#
# Node positions are calculated as percentages of viewport so the map scales
# with any resolution. Lines are drawn via _draw(). Buttons are added as
# direct children of this Control at absolute positions.
#
# When node art is ready: replace Button nodes with TextureButton + custom art.
# ─────────────────────────────────────────────────────────────────────────────

# Hard-coded connections matching the Dungeon_Floor seed data.
# Each inner array is [parent_node_id, child_node_id].
const CONNECTIONS: Array = [
	[1, 2], [1, 3],
	[2, 4], [2, 5], [3, 4], [3, 5],
	[4, 6], [4, 7], [5, 6], [5, 7],
	[6, 8], [6, 9], [7, 8], [7, 9],
	[8, 10], [9, 10],
]

const NODE_BTN_SIZE: Vector2 = Vector2(90, 55)
const STATS_BAR_H:   float   = 52.0
const INFO_BAR_H:    float   = 52.0

# Populated in _ready() based on viewport size
var node_positions: Dictionary = {}
var all_nodes:      Dictionary = {}  # node_id (int) → Dictionary from DB

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
# Base column positions:  left=0.28, center=0.50, right=0.72
# X_NUDGE shifts each node slightly off its column (fraction of viewport width).
# Y_NUDGE shifts each node slightly off its row   (fraction of usable height).
# Together they break the rigid grid into an organic web.
#
# Nudges are hand-tuned so the alternating pattern (left→right→left) creates
# the zig-zag look of Slay the Spire without any node leaving the safe margin.

const X_NUDGE: Dictionary = {
	1:  0.02,   # center → slight right
	2: -0.03,   # left col → nudge further left
	3:  0.02,   # right col → nudge further right
	4:  0.05,   # left col → nudge right (toward center) — creates cross-link feel
	5: -0.04,   # right col → nudge left
	6: -0.05,   # left col → nudge left again
	7:  0.05,   # right col → nudge right
	8:  0.04,   # left col → nudge right
	9: -0.03,   # right col → nudge left
	10: -0.02,  # center → slight left
}

const Y_NUDGE: Dictionary = {
	1:  0.000,
	2: -0.018,
	3:  0.012,
	4:  0.022,
	5: -0.015,
	6: -0.010,
	7:  0.018,
	8:  0.010,
	9: -0.022,
	10: 0.000,
}

func _calculate_positions() -> void:
	var vp:     Vector2 = get_viewport_rect().size
	var w:      float   = vp.x
	var h:      float   = vp.y
	var top:    float   = STATS_BAR_H + 10.0
	var usable: float   = h - top - INFO_BAR_H - 10.0

	# Safe margin: node must stay this many pixels from screen edges
	var margin_x: float = NODE_BTN_SIZE.x * 0.5 + 12.0
	var margin_y: float = NODE_BTN_SIZE.y * 0.5 + 6.0

	# Base row fractions (vertical rhythm)
	var rows: Array = [0.04, 0.21, 0.40, 0.59, 0.78, 0.96]

	# Base column fractions
	var base_x: Dictionary = {
		1: 0.50, 2: 0.28, 3: 0.72,
		4: 0.28, 5: 0.72, 6: 0.28,
		7: 0.72, 8: 0.28, 9: 0.72,
		10: 0.50,
	}
	var row_for_node: Dictionary = {
		1: 0, 2: 1, 3: 1,
		4: 2, 5: 2, 6: 3,
		7: 3, 8: 4, 9: 4,
		10: 5,
	}

	node_positions = {}
	for node_id in base_x.keys():
		var raw_x: float = w * (base_x[node_id] + X_NUDGE[node_id])
		var raw_y: float = top + usable * (rows[row_for_node[node_id]] + Y_NUDGE[node_id])

		# Clamp to safe viewport margins so nodes never clip
		var safe_x: float = clampf(raw_x, margin_x, w - margin_x)
		var safe_y: float = clampf(raw_y, top + margin_y, h - INFO_BAR_H - margin_y)

		node_positions[node_id] = Vector2(safe_x, safe_y)


# ─── Load node data ───────────────────────────────────────────────────────────

func _load_all_nodes() -> void:
	for i in range(1, 11):
		var data: Dictionary = DatabaseManager.get_dungeon_node(i)
		if not data.is_empty():
			all_nodes[i] = data


# ─── Stats bar ────────────────────────────────────────────────────────────────

func _refresh_stats() -> void:
	var player: Dictionary = DatabaseManager.get_player()
	if player.is_empty():
		return
	hp_label.text  = "HP %d/%d"  % [player["current_hp"],      player["max_hp"]]
	sp_label.text  = "SP %d/%d"  % [player["current_sp"],      GameState.current_max_sp()]
	ult_label.text = "ULT %d/%d" % [player["current_ult_pts"], GameState.ULT_PTS_MAX]
	upg_label.text = "UPG %d"    % player["upg_pts_bank"]


# ─── Build node buttons ───────────────────────────────────────────────────────

func _build_node_buttons() -> void:
	# Remove any old buttons from a previous build
	for child in get_children():
		if child is Button:
			child.queue_free()

	var reachable: Array = _get_reachable_ids()

	for node_id in node_positions.keys():
		var pos:  Vector2    = node_positions[node_id]
		var data: Dictionary = all_nodes.get(node_id, {})

		var btn := Button.new()
		btn.custom_minimum_size = NODE_BTN_SIZE
		btn.size = NODE_BTN_SIZE
		# Centre the button on the node position
		btn.position = pos - NODE_BTN_SIZE * 0.5

		if data.is_empty():
			btn.text = "?"
		else:
			var stage:   String = data.get("stage_type", "?")
			var cleared: bool   = int(data.get("is_cleared", 0)) == 1
			btn.text = _node_label(node_id, stage, cleared)

		# Highlight current node
		if node_id == GameState.current_node_id:
			btn.modulate = Color(1.0, 1.0, 0.3)   # yellow tint

		# Reachable nodes are enabled; all others are disabled
		btn.disabled = not (node_id in reachable)
		if not btn.disabled:
			btn.modulate = Color(0.4, 1.0, 0.5)   # green tint = clickable

		# Keep current node yellow even if it's also "reachable" (shouldn't happen, but safe)
		if node_id == GameState.current_node_id:
			btn.modulate = Color(1.0, 1.0, 0.3)

		btn.pressed.connect(func(): _travel_to(node_id))
		add_child(btn)


func _get_reachable_ids() -> Array:
	var paths: Array = DatabaseManager.get_available_paths(GameState.current_node_id)
	var ids:   Array = []
	for path in paths:
		ids.append(int(path["node_id"]))
	return ids


func _node_label(node_id: int, stage: String, cleared: bool) -> String:
	var icon: String   = _stage_icon(stage)
	var check: String  = " ✓" if cleared else ""
	return "%s %d%s" % [icon, node_id, check]


func _stage_icon(stage: String) -> String:
	match stage:
		"START":   return "●"
		"NORMAL":  return "⚔"
		"ELITE":   return "☠"
		"EVENT":   return "?"
		"REST":    return "♥"
		"BOSS":    return "★"
		_:         return "·"


# ─── Draw connection lines ────────────────────────────────────────────────────
#
# Uses cubic Bezier curves (20 segments each) instead of straight lines.
# Control points are set vertically (tangent along Y-axis) so curves bow
# naturally between nodes at different X positions — matching the Slay the
# Spire hand-drawn feel.

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


# Draws a cubic Bezier curve from p0 to p3 using 20 line segments.
# Control points p1/p2 are offset vertically from p0/p3 — this keeps
# tangents pointing "downward" at each node so curves never curl sideways.
func _draw_bezier_cubic(p0: Vector2, p3: Vector2, color: Color, width: float) -> void:
	var dist: float   = abs(p3.y - p0.y)
	var pull: float   = dist * 0.45   # how strongly the curve bows

	var p1: Vector2 = p0 + Vector2(0.0,  pull)   # leave p0 going straight down
	var p2: Vector2 = p3 + Vector2(0.0, -pull)   # arrive at p3 coming from above

	var steps: int     = 20
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
