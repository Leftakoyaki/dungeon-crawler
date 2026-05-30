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

signal replace_popup_closed
# Sprite for the ULT
@onready var ult_label = $BattleArea/PlayerSide/UltRow/UltLabel
@onready var ult_sprite: TextureRect = $UltSprite

# Hardcode the textures so you don't have to use the Inspector
# (Double-check that the res:// paths match your project structure)
var ult_emptyULT_tex = preload("res://SPBarBlank.png")
var ult_halfULT_tex  = preload("res://SPBarBlank1.png")
var ult_fullULT_tex  = preload("res://SPBarBlank2.png")

@onready var sp_sprite: TextureRect = $SPSprite
var sp_textures: Dictionary = {}

func _setup_sp_textures() -> void:
	var paths = {
		0: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP0.png",
		1: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP1.png",
		2: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP2.png",
		3: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP3.png",
		4: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP4.png",
		5: "res://assets/Tiny Swords (Free Pack)/UI Elements/UI Elements/Bars/SP5.png",
	}
	for i in range(6):
		var at := AtlasTexture.new()
		at.atlas  = load(paths[i])
		at.region = Rect2(0, 0, 32, 16)
		sp_textures[i] = at

var _texture_cache: Dictionary = {}
# Creates slots in the Inspector for your 3 images
@export var ult_empty_tex: Texture2D
@export var ult_half_tex: Texture2D
@export var ult_full_tex: Texture2D
# ─── Sprite position tweaks (edit in Inspector on the Combat node) ────────────
@export var player_sprite_scale:  float   = 1.3              # big — Pokemon close-camera feel
@export var enemy_sprite_scale:   float   = 0.0              # 0 = use per-monster scale below
@export var player_sprite_offset: Vector2 = Vector2(0, 0)   # push down onto left cliff
@export var enemy_sprite_offset:  Vector2 = Vector2(0, 0)
@export var aura_offset: Vector2 = Vector2(0, -40)

# ─── Combat state ─────────────────────────────────────────────────────────────
var enemy_current_hp: int   = 0
var combat_data: Dictionary = {}
var waves_total: int        = 1
var waves_done: int         = 0
var entry_finished: bool = false
var current_monster_index: int = 0

# ─── Sprite nodes (created at runtime) ───────────────────────────────────────
var player_anim: AnimatedSprite2D = null
var enemy_anim:  AnimatedSprite2D = null

# ─── Node refs — Player side ──────────────────────────────────────────────────
@onready var player_sprite:     Control      = $BattleArea/PlayerSide/PlayerSprite
@onready var player_name_label: Label        = $BattleArea/PlayerSide/PlayerNameLabel
@onready var player_hp_bar:     TextureProgressBar  = $BattleArea/PlayerSide/PlayerHPBar
@onready var player_hp_label:   Label        = $BattleArea/PlayerSide/PlayerHPLabel
@onready var player_sp_label:   Label        = $BattleArea/PlayerSide/PlayerSPLabel
@onready var player_aura: 		AnimatedSprite2D = $PlayerAura

# ─── Node refs — Enemy side ───────────────────────────────────────────────────
@onready var enemy_sprite:      Control      = $BattleArea/EnemySide/EnemySprite
@onready var enemy_name_label:  Label        = $BattleArea/EnemySide/EnemyNameLabel
@onready var enemy_hp_bar:      TextureProgressBar  = $BattleArea/EnemySide/EnemyHPBar
@onready var enemy_hp_label:    Label        = $BattleArea/EnemySide/EnemyHPLabel

# ─── Node refs — Bottom UI ────────────────────────────────────────────────────
@onready var wave_label:      Label         = $WaveLabel
@onready var log_label:       Label         = $LogLabel
@onready var skill_container: HBoxContainer = $SkillContainer
@onready var use_potion_btn:  Button        = $ActionRow/UsePotionButton
@onready var flee_btn:        Button        = $ActionRow/FleeButton

func _preload_effects(player_class: String) -> void:
	var patterns: Array = []
	
	match player_class:
		"WARRIOR":
			patterns = [
				["res://assets/HolySlash_A/Frames/HolySlash_A_%02d.png", 5, 0],
				["res://assets/HolySlash_B/Frames/HolySlash_B_%02d.png", 4, 0],
				["res://assets/HolySlash_C/Frames/HolySlash_C_%02d.png", 7, 0],
				["res://assets/HeavensFury/Frames/HeavensFury_%02d.png", 12, 0],
				["res://assets/HolyNova/Frames/HolyNova_%02d.png", 10, 0],
				["res://assets/SwordOfJustice/Frames/SwordOfJustice_%02d.png", 130, 1],
			]
		"MAGE":
			patterns = [
				["res://assets/Wizard/Effect_FastPixelFire/60fps/Frames/Effect_FastPixelFire_1/Effect_FastPixelFire_1_%03d.png", 59, 0],
				["res://assets/Wizard/Effect_DitheredFire/30fps/Frames/Effect_DitheredFire_1/Effect_DitheredFire_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_Impact/30fps/Frames/Effect_Impact_1/Effect_Impact_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_SmallHit/30fps/Frames/Effect_SmallHit_1/Effect_SmallHit_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_PuffAndStars/30fps/Frames/Effect_PuffAndStars_1/Effect_PuffAndStars_1_%03d.png", 39, 0],
				["res://assets/Wizard/Effect_Constellation/30fps/Frames/Effect_Constellation_1/Effect_Constellation_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_TheVortex/30fps/Frames/Effect_TheVortex_1/Effect_TheVortex_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_ElectricShield/30fps/Frames/Effect_ElectricShield_1/Effect_ElectricShield_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_Explosion2/30fps/Frames/Effect_Explosion2_1/Effect_Explosion2_1_%03d.png", 29, 0],
			]
		"ARCHER":
			patterns = [
				["res://assets/Wizard/Effect_Impact/30fps/Frames/Effect_Impact_1/Effect_Impact_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_BloodImpact/30fps/Frames/Effect_BloodImpact_1/Effect_BloodImpact_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_Wheel/30fps/Frames/Effect_Wheel_1/Effect_Wheel_1_%03d.png", 29, 0],
				["res://assets/Wizard/Effect_PuffAndStars/30fps/Frames/Effect_PuffAndStars_1/Effect_PuffAndStars_1_%03d.png", 39, 0],
				["res://assets/Wizard/Effect_Kabooms/30fps/Frames/Effect_Kabooms_1/Effect_Kabooms_1_%03d.png", 29, 0],
			]

	for entry in patterns:
		var pattern: String = entry[0]
		var count: int = entry[1]
		var start: int = entry[2]
		for i in range(start, count + start):
			var path: String = pattern % i
			if not _texture_cache.has(path):
				_texture_cache[path] = load(path)

func _connect_combat_click(btn: BaseButton) -> void:
	btn.button_down.connect(func(): MusicManager.play_combat_click())
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	combat_data = DatabaseManager.get_combat_data(GameState.current_node_id)
	for m in combat_data["monsters"]:
		print(" - ", m["mon_name"])
	_setup_sp_textures()
	# sp_sprite.position = Vector2(100, 213)
	sp_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sp_sprite.set_deferred("size", Vector2(90, 40))
	
	if combat_data.is_empty():
		push_error("Combat: no combat data for node %d." % GameState.current_node_id)
		return

	# Wave count from stage type
	var stage: String = combat_data["node"]["stage_type"]
	# check if boss or normal for music
	if stage == "BOSS":
		MusicManager.play_combat(true)
	else:
		MusicManager.play_combat(false)
		
	match stage:
		"NORMAL": waves_total = 3
		"ELITE":  waves_total = combat_data["monsters"].size()
		"BOSS":   waves_total = 1

	enemy_current_hp = int(combat_data["monsters"][0]["max_hp"])

	_setup_sprites()
	_setup_player_aura()

	use_potion_btn.pressed.connect(_on_use_potion_pressed)
	flee_btn.pressed.connect(_on_flee_pressed)
	
	_connect_combat_click(use_potion_btn)
	_connect_combat_click(flee_btn)
	
	_build_skill_buttons()
	wave_label.text = "Wave 1 / %d" % waves_total
	_refresh_ui()
	_begin_player_turn()

	var player = DatabaseManager.get_player()
	_preload_effects(player["player_class"])
	var current_points = player.get("current_ult_pts", 0)
	var max_points = 2 
	_update_ult_ui(current_points, max_points)
	
func _update_ult_ui(current_ult: int, _max_ult: int) -> void:
	
	ult_label.text = "ULT" # %d / %d" % [current_ult, max_ult]
	
	match current_ult:
		0:
			ult_sprite.texture = ult_empty_tex
		1:
			ult_sprite.texture = ult_half_tex
		2:
			ult_sprite.texture = ult_full_tex
	ult_sprite.show()
func _update_sp_ui(current_sp: int) -> void:

	sp_sprite.texture = sp_textures.get(current_sp, sp_textures[0])
# ─── Sprite setup ─────────────────────────────────────────────────────────────
func _setup_sprites() -> void:
	var player := DatabaseManager.get_player()
	if player.is_empty():
		return

	player_anim = AnimatedSprite2D.new()
	player_anim.sprite_frames = _build_player_frames(player["player_class"])
	player_anim.scale         = Vector2(player_sprite_scale, player_sprite_scale)
	player_anim.z_index       = 5
	player_anim.position      = Vector2(-200, 0)  # ← set off-screen BEFORE add_child
	player_anim.animation_finished.connect(func():
		if is_instance_valid(player_anim):
			player_anim.play("idle")
	)
	add_child(player_anim)  # ← now added off-screen
	player_anim.play("idle")

	_reposition_sprites.call_deferred()
	
func _setup_player_aura() -> void:
	var sheet := load("res://assets/knight_aura_spritesheet.png") as Texture2D
	var h: int = 101
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# ── Intro (plays once when aura activates) ────────────────────────────────
	frames.add_animation("intro")
	frames.set_animation_loop("intro", false)
	frames.set_animation_speed("intro", 8.0)
	for region in [Rect2(3, 0, 53, h), Rect2(60, 0, 63, h)]:
		var at := AtlasTexture.new()
		at.atlas  = sheet
		at.region = region
		frames.add_frame("intro", at)

	# ── Loop (plays continuously while aura is active) ────────────────────────
	frames.add_animation("loop")
	frames.set_animation_loop("loop", true)
	frames.set_animation_speed("loop", 8.0)
	for region in [Rect2(127, 0, 79, h), Rect2(210, 0, 87, h), Rect2(301, 0, 79, h)]:
		var at := AtlasTexture.new()
		at.atlas  = sheet
		at.region = region
		frames.add_frame("loop", at)

	# ── Outro (plays once when aura deactivates) ──────────────────────────────
	frames.add_animation("outro")
	frames.set_animation_loop("outro", false)
	frames.set_animation_speed("outro", 8.0)
	for region in [Rect2(384, 0, 79, h), Rect2(467, 0, 73, h), Rect2(544, 0, 73, h)]:
		var at := AtlasTexture.new()
		at.atlas  = sheet
		at.region = region
		frames.add_frame("outro", at)

	player_aura.sprite_frames = frames
	player_aura.scale = Vector2(2.0, 2.0)
	player_aura.z_index = 4
	player_aura.visible = false

func _update_warrior_aura() -> void:
	if not entry_finished:
		return
	if not is_instance_valid(player_aura):
		return

	if is_instance_valid(player_anim):
		player_aura.position = player_anim.position + aura_offset
		player_aura.scale    = Vector2(2.0, 2.0)

	var player := DatabaseManager.get_player()
	if player.is_empty():
		return

	var hp_ratio: float = float(player["current_hp"]) / float(player["max_hp"])
	var should_show: bool = player["player_class"] == "WARRIOR" and hp_ratio <= 0.3

	if should_show and not player_aura.visible:
		# Activate — play intro then switch to loop
		player_aura.visible = true
		player_aura.play("intro")
		log_label.text = "Unyielding Spirit awakens!"
		# When intro finishes, switch to loop
		if not player_aura.animation_finished.is_connected(_on_aura_intro_finished):
			player_aura.animation_finished.connect(_on_aura_intro_finished)

	elif not should_show and player_aura.visible and player_aura.animation != "outro":
		# Deactivate — play outro then hide
		player_aura.play("outro")
		if not player_aura.animation_finished.is_connected(_on_aura_outro_finished):
			player_aura.animation_finished.connect(_on_aura_outro_finished)

func _on_aura_intro_finished() -> void:
	player_aura.animation_finished.disconnect(_on_aura_intro_finished)
	if is_instance_valid(player_aura):
		player_aura.play("loop")

func _on_aura_outro_finished() -> void:
	player_aura.animation_finished.disconnect(_on_aura_outro_finished)
	if is_instance_valid(player_aura):
		player_aura.visible = false

func _spawn_enemy() -> void:
	if is_instance_valid(enemy_anim):
		enemy_anim.queue_free()
		enemy_anim = null

	var monster: Dictionary = combat_data["monsters"][current_monster_index]
	var mon_name: String = monster["mon_name"]
	var e_scale: float   = enemy_sprite_scale if enemy_sprite_scale > 0.0 else _get_enemy_scale(mon_name)

	enemy_anim = AnimatedSprite2D.new()
	enemy_anim.sprite_frames = _build_enemy_frames(mon_name)
	enemy_anim.scale         = Vector2(e_scale, e_scale)
	enemy_anim.flip_h        = _get_enemy_flip(mon_name)
	enemy_anim.z_index       = 5
	enemy_anim.position      = Vector2(get_viewport_rect().size.x + 200, 0)  # ← set off-screen BEFORE add_child
	enemy_anim.animation_finished.connect(func():
		if is_instance_valid(enemy_anim):
			enemy_anim.play("idle")
	)
	add_child(enemy_anim)  # ← now added off-screen
	enemy_anim.play("idle")

	await get_tree().process_frame
	await get_tree().process_frame
	var final_pos: Vector2 = enemy_sprite.global_position + enemy_sprite.size / 2.0 + enemy_sprite_offset
	final_pos.y += _get_enemy_y_offset(mon_name)  # per-monster lift so big sprites don't clip the skill panel
	enemy_anim.position = Vector2(get_viewport_rect().size.x + 200, final_pos.y)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(enemy_anim, "position", final_pos, 0.6)

func _reposition_sprites() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if is_instance_valid(player_anim):
		var final_pos: Vector2 = player_sprite.global_position + player_sprite.size / 2.0 + player_sprite_offset
		player_anim.position = Vector2(-200, final_pos.y)
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(player_anim, "position", final_pos, 0.6)
		tween.finished.connect(func():
			entry_finished = true
			_update_warrior_aura()
		)
	
	await _spawn_enemy()
		
func _play_effect(path_pattern: String, frame_count: int, start_index: int = 1, scale_factor: float = 3.0, offset: Vector2 = Vector2.ZERO, speed: float = 12.0, duration: float = -1.0) -> void:
	var effect := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", false)
	
	var actual_speed: float = speed
	if duration > 0.0:
		actual_speed = frame_count / duration
	frames.set_animation_speed("play", actual_speed)
	for i in range(start_index, frame_count + start_index):
		var tex := _load_cached(path_pattern % i) as Texture2D
		if tex:
			frames.add_frame("play", tex)
	if frames.get_frame_count("play") == 0:
		push_error("_play_effect: No frames loaded from %s" % path_pattern)
		return
	effect.sprite_frames = frames
	effect.position = (enemy_anim.global_position if is_instance_valid(enemy_anim) else Vector2(800, 300)) + offset
	effect.scale = Vector2(scale_factor, scale_factor)
	effect.z_index = 10
	add_child(effect)
	effect.play("play")
	await effect.animation_finished
	effect.queue_free()


func _play_effect_no_await(path_pattern: String, frame_count: int, start_index: int = 1, scale_factor: float = 3.0, offset: Vector2 = Vector2.ZERO, speed: float = 12.0, duration: float = -1) -> void:
	var effect := AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	var actual_speed: float = speed
	if duration > 0.0:
		actual_speed = frame_count / duration
	frames.remove_animation("default")
	frames.add_animation("play")
	frames.set_animation_loop("play", false)
	frames.set_animation_speed("play", actual_speed)
	for i in range(start_index, frame_count + start_index):
		var tex := _load_cached(path_pattern % i) as Texture2D
		if tex:
			frames.add_frame("play", tex)
	if frames.get_frame_count("play") == 0:
		push_error("_play_effect_no_await: No frames loaded from %s" % path_pattern)
		return
	effect.sprite_frames = frames
	effect.position = (enemy_anim.global_position if is_instance_valid(enemy_anim) else Vector2(800, 300)) + offset
	effect.scale = Vector2(scale_factor, scale_factor)
	effect.z_index = 10
	add_child(effect)
	effect.play("play")
	effect.animation_finished.connect(effect.queue_free)

func _build_player_frames(player_class: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	var idle_path:  String
	var idle_count: int
	var atk_path:   String
	var atk_count:  int

	match player_class:
		"MAGE":
			idle_path  = "res://assets/Tiny Swords (Free Pack)/Units/Blue Units/Monk/Idle.png"
			idle_count = 6
			atk_path   = "res://assets/Tiny Swords (Free Pack)/Units/Blue Units/Monk/Cast.png"
			atk_count  = 5
		"WARRIOR":
			idle_path  = "res://assets/Tiny Swords (Free Pack)/Units/Red Units/Warrior/Warrior_Idle.png"
			idle_count = 8
			atk_path   = "res://assets/Tiny Swords (Free Pack)/Units/Red Units/Warrior/Warrior_Attack1.png"
			atk_count  = 4
		"ARCHER":
			idle_path  = "res://assets/Tiny Swords (Free Pack)/Units/Yellow Units/Archer/Archer_Idle.png"
			idle_count = 6
			atk_path   = "res://assets/Tiny Swords (Free Pack)/Units/Yellow Units/Archer/Archer_Shoot.png"
			atk_count  = 8
		_:
			idle_path  = "res://assets/Tiny Swords (Free Pack)/Units/Blue Units/Monk/Idle.png"
			idle_count = 6
			atk_path   = "res://assets/Tiny Swords (Free Pack)/Units/Blue Units/Monk/Run.png"
			atk_count  = 4

	# Idle (looping)
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 8.0)
	var idle_sheet := load(idle_path) as Texture2D
	if idle_sheet:
		for i in range(idle_count):
			var at := AtlasTexture.new()
			at.atlas  = idle_sheet
			at.region = Rect2(i * 192, 0, 192, 192)
			frames.add_frame("idle", at)

	# Attack (one-shot — fires animation_finished when done)
	frames.add_animation("attack")
	frames.set_animation_loop("attack", false)
	frames.set_animation_speed("attack", 16.0)
	var atk_sheet := load(atk_path) as Texture2D
	if atk_sheet:
		for i in range(atk_count):
			var at := AtlasTexture.new()
			at.atlas  = atk_sheet
			at.region = Rect2(i * 192, 0, 192, 192)
			frames.add_frame("attack", at)

	# Fallback: keep at least one frame so play() doesn't error
	if frames.get_frame_count("idle") == 0:
		frames.add_frame("idle", PlaceholderTexture2D.new())
	if frames.get_frame_count("attack") == 0:
		frames.add_frame("attack", PlaceholderTexture2D.new())

	return frames


func _build_enemy_frames(mon_name: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("idle")
	frames.set_animation_loop("idle", true)
	frames.set_animation_speed("idle", 8.0)
	frames.add_animation("attack")
	frames.set_animation_loop("attack", false)
	frames.set_animation_speed("attack", 12.0)

	var idle_paths: Array = []
	var atk_paths:  Array = []

	match mon_name:
		"Troll":
			idle_paths = [
				"res://assets/Monsters/Troll_Idle/ogre-idle1.png",
				"res://assets/Monsters/Troll_Idle/ogre-idle2.png",
				"res://assets/Monsters/Troll_Idle/ogre-idle3.png",
				"res://assets/Monsters/Troll_Idle/ogre-idle4.png",
			]
			atk_paths = [
				"res://assets/Monsters/Troll_Attack/ogre-attack1.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack2.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack3.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack4.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack5.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack6.png",
				"res://assets/Monsters/Troll_Attack/ogre-attack7.png",
			]
		"Jumping Demon":
			idle_paths = [
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon1.png",
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon2.png",
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon3.png",
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon4.png",
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon5.png",
				"res://assets/Monsters/Jumping-Demon/Jumping-Demon6.png",
			]
			atk_paths = idle_paths   # no separate attack folder
		"Dark Knight":
			idle_paths = [
				"res://assets/Monsters/DarkKnight_Idle/frame1.png",
				"res://assets/Monsters/DarkKnight_Idle/frame2.png",
				"res://assets/Monsters/DarkKnight_Idle/frame3.png",
				"res://assets/Monsters/DarkKnight_Idle/frame4.png",
			]
			atk_paths = [
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export1.png",
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export2.png",
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export3.png",
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export4.png",
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export5.png",
				"res://assets/Monsters/DarkKnight_Attack/AirSwordSlash-export6.png",
			]
		"Nightmare":
			idle_paths = [
				"res://assets/Monsters/Nightmare_Idle/frame1.png",
				"res://assets/Monsters/Nightmare_Idle/frame2.png",
				"res://assets/Monsters/Nightmare_Idle/frame3.png",
				"res://assets/Monsters/Nightmare_Idle/frame4.png",
			]
			atk_paths = [
				"res://assets/Monsters/Nightmare_Attack/frame1.png",
				"res://assets/Monsters/Nightmare_Attack/frame2.png",
				"res://assets/Monsters/Nightmare_Attack/frame3.png",
			]
		"Centaur":
			idle_paths = [
				"res://assets/Monsters/Centaur_Idle/centaur1.png",
				"res://assets/Monsters/Centaur_Idle/centaur2.png",
				"res://assets/Monsters/Centaur_Idle/centaur3.png",
				"res://assets/Monsters/Centaur_Idle/centaur4.png",
			]
			atk_paths = [
				"res://assets/Monsters/Centaur_Attack_/00_Untitled design (13).png",
				"res://assets/Monsters/Centaur_Attack_/01_Untitled design (13).png",
				"res://assets/Monsters/Centaur_Attack_/02_Untitled design (13).png",
				"res://assets/Monsters/Centaur_Attack_/04_Untitled design (13).png",
				"res://assets/Monsters/Centaur_Attack_/05_Untitled design (13).png",
			]
		"Demon":
			idle_paths = [
				"res://assets/Monsters/Demon_Idle/frame_0_delay-0.2s.png",
				"res://assets/Monsters/Demon_Idle/frame_1_delay-0.2s.png",
				"res://assets/Monsters/Demon_Idle/frame_2_delay-0.2s.png",
				"res://assets/Monsters/Demon_Idle/frame_3_delay-0.2s.png",
				"res://assets/Monsters/Demon_Idle/frame_4_delay-0.2s.png",
				"res://assets/Monsters/Demon_Idle/frame_5_delay-0.2s.png",
			]
			atk_paths = [
				"res://assets/Monsters/Demon_Attack/frame_00_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_01_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_02_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_03_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_04_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_05_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_06_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_07_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_08_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_09_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_10_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_11_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_12_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_13_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_14_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_15_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_16_delay-0.1s.png",
				"res://assets/Monsters/Demon_Attack/frame_17_delay-0.2s.png",
			]

	for path in idle_paths:
		var tex := _load_cached(path) as Texture2D
		if tex:
			frames.add_frame("idle", tex)

	for path in atk_paths:
		var tex := _load_cached(path) as Texture2D
		if tex:
			frames.add_frame("attack", tex)

	if frames.get_frame_count("idle") == 0:
		frames.add_frame("idle", PlaceholderTexture2D.new())
	if frames.get_frame_count("attack") == 0:
		frames.add_frame("attack", PlaceholderTexture2D.new())

	return frames


func _get_enemy_scale(mon_name: String) -> float:
	# Enemies should feel threatening — bigger scales, Demon fills the screen.
	match mon_name:
		"Troll":         return 2.5   # source ~144×80  → 360×200 at 2.5
		"Jumping Demon": return 2.5   # source ~101×98  → 252×245 at 2.5
		"Dark Knight":   return 3.5   # source ~128×96  → 448×336 at 3.5
		"Nightmare":     return 2.5   # source ~160×96  → 400×240 at 2.5
		"Centaur":       return 2.2   # source ~112×144 → 246×317 at 2.2
		"Demon":         return 3.0   # source 256×176 with transparent padding
		_:               return 2.5


func _get_enemy_y_offset(mon_name: String) -> float:
	# Upward nudge (negative = up) so taller-scaled sprites rest on the platform
	# instead of clipping down into the skill panel. Center-anchored sprites grow
	# both ways, so bigger scale needs more lift.
	match mon_name:
		"Dark Knight": return -70.0
		_:             return 0.0


func _get_enemy_flip(mon_name: String) -> bool:
	# true  = flip_h → sprite faces LEFT (toward player)
	# false = no flip (sprite already faces left in source)
	match mon_name:
		"Nightmare": return false  # source already faces left
		"Centaur":   return false  # source already faces left
		"Demon":     return false  # source already faces left
		"Troll":     return false
		_:           return true


# ─── Turn management ─────────────────────────────────────────────────────────

func _begin_player_turn() -> void:
	log_label.text = ""
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
	var monster: Dictionary = combat_data["monsters"][current_monster_index]

	var damage: int = int(monster["attack_power"])
	var new_hp: int = max(int(player["current_hp"]) - damage, 0)

	log_label.text = "%s attacks for %d damage!" % [monster["mon_name"], damage]

	# Enemy attack animation
	if enemy_anim != null and enemy_anim.sprite_frames != null \
			and enemy_anim.sprite_frames.has_animation("attack") \
			and enemy_anim.sprite_frames.get_frame_count("attack") > 0:
		enemy_anim.play("attack")
		await enemy_anim.animation_finished
		if is_instance_valid(enemy_anim):
			enemy_anim.play("idle")

	DatabaseManager.update_player_hp(new_hp)
	_refresh_ui()
	
	_hit_flash(player_anim)
	await _knockback(player_anim, -1.0)

	if new_hp <= 0:
		await get_tree().create_timer(0.5).timeout
		_on_defeat()
		return

	use_potion_btn.disabled = false
	flee_btn.disabled       = false
	_begin_player_turn()

func _hit_flash(sprite: AnimatedSprite2D) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.modulate = Color(4.0, 0.5, 0.5, 1.0)  # red flash
	await get_tree().create_timer(0.08).timeout
	sprite.modulate = Color.WHITE

func _knockback(sprite: AnimatedSprite2D, direction: float) -> void:
	if not is_instance_valid(sprite):
		return
	var original_pos: Vector2 = sprite.position
	var knockback_pos: Vector2 = original_pos + Vector2(direction * 40, 0)

	var out_tween = create_tween()
	out_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	out_tween.tween_property(sprite, "position", knockback_pos, 0.08)
	await out_tween.finished

	var in_tween = create_tween()
	in_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	in_tween.tween_property(sprite, "position", original_pos, 0.3)
	await in_tween.finished

func _play_enemy_death() -> void:
	if not is_instance_valid(enemy_anim):
		return

	var viewport_width: float = get_viewport_rect().size.x

	# Stop movement, switch to idle pose (freeze it)
	enemy_anim.stop()

	# Fade to gray over 0.5s
	var gray_tween = create_tween()
	gray_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)
	gray_tween.tween_property(enemy_anim, "modulate", Color(0.35, 0.35, 0.35, 1.0), 0.5)
	await gray_tween.finished

	await get_tree().create_timer(0.3).timeout

	# Slide off to the right
	var exit_pos := Vector2(viewport_width + 300, enemy_anim.position.y)
	var slide_tween = create_tween()
	slide_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	slide_tween.tween_property(enemy_anim, "position", exit_pos, 0.7)
	await slide_tween.finished

# ─── Skill buttons ────────────────────────────────────────────────────────────

func _build_skill_buttons() -> void:
	for child in skill_container.get_children():
		child.queue_free()

	var skills := DatabaseManager.get_player_skills()
	var player := DatabaseManager.get_player()
	var class_data := DatabaseManager.get_class_data(player["player_class"])
	var base_atk: int = int(class_data.get("base_atk", 10))

	var alagard := load("res://assets/alagardFont.ttf") as FontFile
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
		if alagard:
			btn.add_theme_font_override("font", alagard)
			btn.add_theme_font_size_override("font_size", 22)
		# .bind() evaluates skill NOW (current loop value), avoiding closure-capture bug
		btn.pressed.connect(_on_skill_used.bind(skill))
		_connect_combat_click(btn)
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

	# ── Passive: WARRIOR — Unyielding Spirit (1.5x ATK boost at 30% HP) ──────
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

	# ── Override log if Warrior Unyielding Spirit is active ───────────────────
	if player["player_class"] == "WARRIOR":
		var hp_ratio: float = float(player["current_hp"]) / float(player["max_hp"])
		if hp_ratio <= 0.3:
			log_msg = "Your Unyielding Spirit is showing! %s deals %d damage!" % [skill["skill_name"], damage]

	# ── Passive: ARCHER — Eagle Eye (25% double strike on NORMAL) ────────────
	if player["player_class"] == "ARCHER" and (skill["atk_type"] == "NORMAL" or skill["atk_type"] == "SKILL") and randf() < 0.30:
		damage *= 2
		log_msg = "Eagle Eye! %s hits TWICE for %d damage!" % [skill["skill_name"], damage]

	# Consume SP and ULT before animation plays
	DatabaseManager.update_player_sp(int(player["current_sp"]) - effective_sp_cost)
	var new_ult: int = clampi(int(player["current_ult_pts"]) + int(skill["ult_pts_mod"]), 0, GameState.ULT_PTS_MAX)
	DatabaseManager.update_player_ult_pts(new_ult)
	_refresh_ui()

	# Player attack animation
	if player_anim != null and player_anim.sprite_frames != null \
			and player_anim.sprite_frames.has_animation("attack") \
			and player_anim.sprite_frames.get_frame_count("attack") > 0:
		player_anim.play("attack")

	# ── Skill effects ─────────────────────────────────────────────────────────
	if player["player_class"] == "WARRIOR" and skill["atk_type"] == "SKILL":
		_play_effect("res://assets/SwordOfJustice/Frames/SwordOfJustice_%02d.png", 130)

	if player["player_class"] == "WARRIOR" and skill["atk_type"] == "ULTIMATE":
		_play_effect_no_await("res://assets/HeavensFury/Frames/HeavensFury_%02d.png", 12, 0, 3.0)
		_play_effect("res://assets/HolyNova/Frames/HolyNova_%02d.png", 10, 0, 3.0)
	
	if player["player_class"] == "WARRIOR" and skill["atk_type"] == "NORMAL":
		_play_effect_no_await("res://assets/HolySlash_A/Frames/HolySlash_A_%02d.png", 5)
		_play_effect_no_await("res://assets/HolySlash_B/Frames/HolySlash_B_%02d.png", 4)
		_play_effect("res://assets/HolySlash_C/Frames/HolySlash_C_%02d.png", 7)
		
		
	if player["player_class"] == "MAGE" and skill["atk_type"] == "NORMAL":
		_play_effect_no_await("res://assets/Wizard/Effect_Impact/30fps/Frames/Effect_Impact_1/Effect_Impact_1_%03d.png", 29, 0, 1.0)
		_play_effect_no_await("res://assets/Wizard/Effect_SmallHit/30fps/Frames/Effect_SmallHit_1/Effect_SmallHit_1_%03d.png", 29, 0, 1.0)
		_play_effect("res://assets/Wizard/Effect_PuffAndStars/30fps/Frames/Effect_PuffAndStars_1/Effect_PuffAndStars_1_%03d.png", 39, 0, 1.0)
	
	if player["player_class"] == "MAGE" and skill["atk_type"] == "SKILL":
		_play_effect_no_await("res://assets/Wizard/Effect_FastPixelFire/60fps/Frames/Effect_FastPixelFire_1/Effect_FastPixelFire_1_%03d.png", 59, 0, 1.0, Vector2.ZERO, 12.0, 1)
		_play_effect("res://assets/Wizard/Effect_DitheredFire/30fps/Frames/Effect_DitheredFire_1/Effect_DitheredFire_1_%03d.png", 29, 0, 0.5, Vector2(0, 50), 12.0, 1)
	
	if player["player_class"] == "MAGE" and skill["atk_type"] == "ULTIMATE":
		_play_effect_no_await("res://assets/Wizard/Effect_Constellation/30fps/Frames/Effect_Constellation_1/Effect_Constellation_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 1.5)
		await _play_effect("res://assets/Wizard/Effect_TheVortex/30fps/Frames/Effect_TheVortex_1/Effect_TheVortex_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 1.5)
		_play_effect_no_await("res://assets/Wizard/Effect_ElectricShield/30fps/Frames/Effect_ElectricShield_1/Effect_ElectricShield_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 1)
		_play_effect("res://assets/Wizard/Effect_Explosion2/30fps/Frames/Effect_Explosion2_1/Effect_Explosion2_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 1)
		
	if player["player_class"] == "ARCHER" and skill["atk_type"] == "NORMAL":
		_play_effect_no_await("res://assets/Wizard/Effect_Impact/30fps/Frames/Effect_Impact_1/Effect_Impact_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 24.0)
		_play_effect("res://assets/Wizard/Effect_BloodImpact/30fps/Frames/Effect_BloodImpact_1/Effect_BloodImpact_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 0.5)
		
	if player["player_class"] == "ARCHER" and skill["atk_type"] == "SKILL":
		_play_effect("res://assets/Wizard/Effect_Wheel/30fps/Frames/Effect_Wheel_1/Effect_Wheel_1_%03d.png", 29, 0, 1.0, Vector2.ZERO, 12.0, 1.0)
	
	if player["player_class"] == "ARCHER" and skill["atk_type"] == "ULTIMATE":
		_play_effect_no_await("res://assets/Wizard/Effect_PuffAndStars/30fps/Frames/Effect_PuffAndStars_1/Effect_PuffAndStars_1_%03d.png", 29, 0, 3.0)
		_play_effect("res://assets/Wizard/Effect_Kabooms/30fps/Frames/Effect_Kabooms_1/Effect_Kabooms_1_%03d.png", 29, 0, 1.0)
	# Apply damage to enemy
	enemy_current_hp -= damage
	log_label.text = log_msg
	_refresh_ui()

	_hit_flash(enemy_anim)
	await _knockback(enemy_anim, 1.0)
	
	if enemy_current_hp <= 0:
		await get_tree().create_timer(0.5).timeout
		_on_wave_cleared()
		return

	# ── Check remaining SP ────────────────────────────────────────────────────
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
		_set_skill_buttons_enabled(true)

	
# ─── Wave management ──────────────────────────────────────────────────────────

func _on_wave_cleared() -> void:
	waves_done += 1
	await _play_enemy_death()
	await _roll_drops()
	await get_tree().create_timer(0.6).timeout
	if waves_done < waves_total:
		var next_wave: int = waves_done + 1
		log_label.text   = "Wave %d cleared! Next wave incoming..." % waves_done
		wave_label.text  = "Wave %d / %d" % [next_wave, waves_total]

		# Switch to next monster if we've finished all waves for current one
		var waves_per_monster: int = waves_total / combat_data["monsters"].size()
		if waves_done % waves_per_monster == 0:
			current_monster_index += 1
			log_label.text = "A new enemy appears!"

		enemy_current_hp = int(combat_data["monsters"][current_monster_index]["max_hp"])
		await _spawn_enemy()

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
	DatabaseManager.combat_ended.emit("victory")

	var node: Dictionary = combat_data["node"]
	await get_tree().create_timer(1.2).timeout
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
	
	inventory.sort_custom(func(a, b): return int(a["inv_id"]) < int(b["inv_id"])) # sort based on inv_id
	# Always show picker (even if 1 item)
	_set_skill_buttons_enabled(false)
	use_potion_btn.disabled = true
	flee_btn.disabled       = true

	var popup := Panel.new()
	popup.name     = "PotionPicker"
	popup.theme = load("res://assets/upgrade_theme.tres")
	popup.size     = Vector2(250, 50 + inventory.size() * 50 + 50)
	popup.position = (get_viewport_rect().size - popup.size) * 0.5
	popup.z_index  = 10

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "Choose a potion:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for item in inventory:
		var btn := Button.new()
		btn.text = item["pot_name"]
		btn.custom_minimum_size = Vector2(0, 40)

		var captured_item: Dictionary = item
		btn.pressed.connect(func():
			popup.queue_free()
			_set_skill_buttons_enabled(true)
			use_potion_btn.disabled = false
			flee_btn.disabled = false
			_use_potion(captured_item)
		)
		_connect_combat_click(btn)
		vbox.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	_connect_combat_click(cancel_btn)
	cancel_btn.pressed.connect(func():
		popup.queue_free()
		_set_skill_buttons_enabled(true)
		use_potion_btn.disabled = false
		flee_btn.disabled = false
	)

	vbox.add_child(cancel_btn)

	add_child(popup)


func _use_potion(item: Dictionary) -> void:
	var player: Dictionary = DatabaseManager.get_player()

	match item["pot_type"]:
		"HEAL":
			var new_hp := mini(int(player["current_hp"]) + int(item["potency_value"]), int(player["max_hp"]))
			DatabaseManager.update_player_hp(new_hp)
			log_label.text = "Used %s — restored %d HP." % [item["pot_name"], int(item["potency_value"])]
		"DAMAGE_BUFF":
			GameState.atk_buff_multiplier = float(item["potency_value"])
			log_label.text = "Used %s — ATK x%.2f on next hit!" % [item["pot_name"], GameState.atk_buff_multiplier]
		"SP_RECOVER":
			var player_fresh := DatabaseManager.get_player()
			var new_sp := mini(int(player_fresh["current_sp"]) + int(item["potency_value"]), int(player_fresh["max_sp"]))
			DatabaseManager.update_player_sp(new_sp)
			log_label.text = "Used %s — recovered %d SP." % [item["pot_name"], int(item["potency_value"])]

	DatabaseManager.remove_from_inventory(item["inv_id"])
	_refresh_ui()


# ─── Flee ─────────────────────────────────────────────────────────────────────

func _on_flee_pressed() -> void:
	var monster: Dictionary = combat_data["monsters"][current_monster_index]
	var type = monster["monster_type"]
	if randf() < 0.5 and type not in ["ELITE", "BOSS"]:
		log_label.text = "You fled!"
		DatabaseManager.combat_ended.emit("fled")
		await get_tree().create_timer(0.8).timeout
		get_tree().change_scene_to_file("res://scenes/Map.tscn")
	else:
		log_label.text = "Couldn't escape!"
		_end_player_turn()

# ─── Drop system ─────────────────────────────────────────────────────────────

var pending_pot_id: int = -1
var pending_pot_name: String = ""


func _roll_drops() -> void:
	var monster: Dictionary = combat_data["monsters"][current_monster_index]
	if randf() < float(monster["pot_drop_chance"]):
		var pot_id := randi_range(1, 4)
		var result := DatabaseManager.add_to_inventory(pot_id)
		if result["success"]:
			var potion := DatabaseManager.get_potion(pot_id)
			log_label.text += "\nDrop: %s!" % potion.get("pot_name", "Potion")
		elif result["reason"] == "FULL":
			var potion := DatabaseManager.get_potion(pot_id)
			pending_pot_id   = pot_id
			pending_pot_name = potion.get("pot_name", "Potion")
			log_label.text  += "\nDrop: %s (Inventory Full)!" % pending_pot_name
			_open_replace_inventory_ui(pot_id)
			await replace_popup_closed
	if randf() < float(monster["upg_point_chance"]):
		DatabaseManager.add_upg_pts(1)
		log_label.text += "\nDrop: +1 Upgrade Point!"


# ─── Replace UI (dynamic popup) ──────────────────────────────────────────────
func _open_replace_inventory_ui(_pot_id: int) -> void:
	var inventory := DatabaseManager.get_inventory()
	inventory.sort_custom(func(a, b): return int(a["inv_id"]) < int(b["inv_id"]))
	_set_skill_buttons_enabled(false)
	use_potion_btn.disabled = true
	flee_btn.disabled = true

	var popup := Panel.new()
	popup.name = "ReplacePotionPopup"

	popup.size = Vector2(320, 60 + inventory.size() * 50 + 60)
	popup.position = (get_viewport_rect().size - popup.size) * 0.5
	popup.z_index = 20

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	# ── Title shows incoming potion ───────────────────────────────────────────
	var title := Label.new()
	title.text = "Your inventory is full!\nItem Drop: %s" % pending_pot_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# ── Inventory buttons ─────────────────────────────────────────────────────
	for i in range(inventory.size()):
		var item: Dictionary = inventory[i]

		var btn := Button.new()
		btn.text = "Replace: " + item["pot_name"]
		btn.custom_minimum_size = Vector2(0, 40)

		var captured_inv_id: int = int(item["inv_id"])  # ← capture inv_id, not index
		btn.pressed.connect(func():
			popup.queue_free()
			_set_skill_buttons_enabled(true)
			use_potion_btn.disabled = false
			flee_btn.disabled = false
			_replace_item(captured_inv_id)  # ← call new function
			replace_popup_closed.emit()
		)
		
		# --- ADDED: Click sound for the replace buttons! ---
		_connect_combat_click(btn)

		vbox.add_child(btn)

	# ── Discard option ────────────────────────────────────────────────────────
	var discard_btn := Button.new()
	discard_btn.text = "Discard new potion"
	discard_btn.custom_minimum_size = Vector2(0, 40)

	discard_btn.pressed.connect(func():
		popup.queue_free()
		_set_skill_buttons_enabled(true)
		use_potion_btn.disabled = false
		flee_btn.disabled = false
		log_label.text += "\nDiscarded %s." % pending_pot_name
		replace_popup_closed.emit()
	)
	
	# --- ADDED: Click sound for the discard button! ---
	_connect_combat_click(discard_btn)

	vbox.add_child(discard_btn)

	add_child(popup)


# ─── Replace logic ───────────────────────────────────────────────────────────

func _replace_item(inv_id: int) -> void:
	var inv := DatabaseManager.get_inventory()

	var target: Dictionary = {}
	for item in inv:
		if int(item["inv_id"]) == inv_id:
			target = item
			break

	if target.is_empty():
		return

	var old_potion := DatabaseManager.get_potion(target["pot_id"])
	var new_potion := DatabaseManager.get_potion(pending_pot_id)

	DatabaseManager.remove_from_inventory(inv_id)
	DatabaseManager.add_to_inventory(pending_pot_id)

	log_label.text = "Replaced %s with %s!" % [
		old_potion.get("pot_name", "Potion"),
		new_potion.get("pot_name", "Potion")
	]

	pending_pot_id = -1
	pending_pot_name = ""

	await get_tree().create_timer(1.0).timeout
	log_label.text = ""

# ─── UI refresh ───────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	var player:  Dictionary = DatabaseManager.get_player()
	var monster: Dictionary = combat_data["monsters"][current_monster_index] if not combat_data.get("monsters", []).is_empty() else {}

	if not player.is_empty():
		player_name_label.text = GameState.player_class
		player_hp_bar.max_value = int(player["max_hp"])
		player_hp_bar.value     = int(player["current_hp"])
		player_hp_label.text    = "HP  %d / %d" % [player["current_hp"], player["max_hp"]]
		player_sp_label.text    = "SP" #  %d / %d" % [player["current_sp"], player["max_sp"]]
		_update_sp_ui(int(player["current_sp"]))
		_update_ult_ui(int(player["current_ult_pts"]), GameState.ULT_PTS_MAX)
		
		#player_ult_label.text   = "ULT  %d / %d" % [player["current_ult_pts"], GameState.ULT_PTS_MAX]
	if not monster.is_empty():
		enemy_name_label.text  = "%s  [%s]" % [monster["mon_name"], monster["monster_type"]]
		enemy_hp_bar.max_value = int(monster["max_hp"])
		enemy_hp_bar.value     = max(enemy_current_hp, 0)
		enemy_hp_label.text    = "HP  %d / %d" % [max(enemy_current_hp, 0), monster["max_hp"]]
	
	_update_warrior_aura()

func _load_cached(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path)
	return _texture_cache[path]
