extends Control

@onready var new_game_btn: TextureButton = $NewGameButton
@onready var continue_btn: TextureButton	 = $ContinueButton
@onready var quit_btn: TextureButton = $QuitButton

var original_pos: Vector2
var is_hovering: bool = false
# Adjust this number to control how fast it travels (higher = faster)
var travel_speed: float = 200.0 
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		print("Click detected! State: ", event.pressed) # This will show up in the Output console
		GameState.update_cursor(event.pressed)
func _ready() -> void:
	original_pos = new_game_btn.position
	
	# Connect signals to toggle our hovering state
	new_game_btn.mouse_entered.connect(func(): is_hovering = true)
	new_game_btn.mouse_exited.connect(_reset_button_position)
	
	# Standard button signals
	new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	continue_btn.disabled = DatabaseManager.get_player().is_empty()

func _process(delta: float) -> void:
	if is_hovering:
		# Get the width of the screen
		var screen_width = get_viewport_rect().size.x
		
		# Calculate how far we can travel before hitting the edge
		# We subtract the button's own width so it doesn't disappear completely
		var limit = screen_width - new_game_btn.size.x
		
		# Only move if we haven't hit the limit yet
		if new_game_btn.position.x < limit:
			new_game_btn.position.x += travel_speed * delta
		else:
			# Snap it exactly to the edge so it doesn't jitter
			new_game_btn.position.x = limit
func _reset_button_position() -> void:
	is_hovering = false
	# Snap back to the start when the mouse leaves
	new_game_btn.position = original_pos

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ClassSelect.tscn")

func _on_continue_pressed() -> void:
	GameState.sync_from_db()
	get_tree().change_scene_to_file("res://scenes/Map.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
