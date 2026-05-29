extends Control

@onready var new_game_btn: TextureButton = $NewGameButton
@onready var continue_btn: TextureButton = $ContinueButton
@onready var quit_btn: TextureButton = $QuitButton
@onready var original_game_btn: TextureButton = $OriginalGameButton 
@onready var lancer: AnimatedSprite2D = $MainMenuLancer

var original_pos_new: Vector2
var original_pos_quit: Vector2
var original_pos_orig: Vector2
var original_pos_cont: Vector2

var is_hovering: bool = false
var is_pressing_new_game: bool = false 
var is_dying: bool = false
var hover_time: float = 0.0

func _ready() -> void:
	MusicManager.play_menu()
	original_pos_new = new_game_btn.position
	original_pos_quit = quit_btn.position
	original_pos_orig = original_game_btn.position
	original_pos_cont = continue_btn.position
	
	original_game_btn.visible = false
	
	lancer.play("idle")
	
	# Connect signals
	new_game_btn.mouse_entered.connect(func(): is_hovering = true)
	new_game_btn.mouse_exited.connect(_reset_button_position)
	new_game_btn.button_down.connect(func(): is_pressing_new_game = true)
	new_game_btn.button_up.connect(func(): is_pressing_new_game = false)
	
	_connect_press_scale(new_game_btn)
	_connect_press_scale(continue_btn)
	_connect_press_scale(quit_btn)
	_connect_press_scale(original_game_btn)
	
	new_game_btn.pressed.connect(_on_new_game_pressed)
	original_game_btn.pressed.connect(_on_original_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	quit_btn.mouse_entered.connect(_on_quit_btn_mouse_entered)

	continue_btn.disabled = DatabaseManager.get_player().is_empty()

func _connect_press_scale(btn: TextureButton) -> void:
	btn.button_down.connect(func(): btn.scale = Vector2(1.2, 1.2))
	btn.button_up.connect(func(): btn.scale = Vector2(1.0, 1.0))
func _process(delta: float) -> void:
	hover_time += delta
	
	# 1. Floating Logic (Always runs, even when dying!)
	# We move this OUTSIDE the "is_dying" check
	
	# New Game button float logic (only if NOT pressing)
	if not is_pressing_new_game:
		if is_hovering:
			new_game_btn.position.y = original_pos_new.y + (sin(hover_time * 5.0) * 10.0)
		else:
			new_game_btn.position.y = original_pos_new.y
			
	# Always float others
	quit_btn.position.y = original_pos_quit.y + (sin(hover_time * 4.0) * 8.0)
	continue_btn.position.y = original_pos_cont.y + (sin(hover_time * 3.5) * 8.0)
	original_game_btn.position.y = original_pos_orig.y + (sin(hover_time * 4.5) * 8.0)
	
	# 2. Input/Interaction Logic (Stops when dying)
	if is_dying: return
	
	if is_pressing_new_game:
		if new_game_btn.scale.x < 3.0:
			new_game_btn.scale.x += 3.0 * delta
		else:
			_play_death_sequence()
	else:
		new_game_btn.scale.x = 1.0
func _play_death_sequence() -> void:
	if is_dying: return
	is_dying = true
	lancer.play("death")
	
	# Show the button and force its initial Y position to prevent a "jump"
	original_game_btn.visible = true
	original_game_btn.position.y = original_pos_orig.y
	
	await lancer.animation_finished

func _on_original_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ClassSelect.tscn")

func _reset_button_position() -> void:
	is_hovering = false
	# Reset Y position explicitly when mouse leaves
	new_game_btn.position.y = original_pos_new.y

func _on_quit_btn_mouse_entered() -> void:
	var screen_size = get_viewport_rect().size
	var random_x = randf_range(0, screen_size.x - quit_btn.size.x)
	var random_y = randf_range(0, screen_size.y - quit_btn.size.y)
	quit_btn.position = Vector2(random_x, random_y)

func _on_new_game_pressed() -> void: pass 
func _on_continue_pressed() -> void:
	GameState.sync_from_db()
	get_tree().change_scene_to_file("res://scenes/Map.tscn")
func _on_quit_pressed() -> void:
	get_tree().quit()
