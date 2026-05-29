extends Control

var selected_class: String = ""

# ── Texture buttons at root ───────────────────────────────────────────────────
@onready var mage_btn:    TextureButton = $SelectMage
@onready var warrior_btn: TextureButton = $SelectWarrior
@onready var archer_btn:  TextureButton = $SelectArcher

# ── Single stats label (shown on class select) ────────────────────────────────
@onready var stats_label: Label = $StatsLabel

@onready var selected_label: Label  = $SelectedLabel
@onready var passive_label:  Label  = $PassiveLabel
@onready var confirm_btn:    Button = $ConfirmButton
@onready var back_btn:       Button = $BackButton

# ── Animated sprites ──────────────────────────────────────────────────────────
@onready var mage_sprite:    AnimatedSprite2D = $Animations/MageSprite
@onready var warrior_sprite: AnimatedSprite2D = $Animations/WarriorSprite
@onready var archer_sprite:  AnimatedSprite2D = $Animations/ArcherSprite


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.update_cursor(event.pressed)


func _ready() -> void:
	# --- ADDED: Play Menu Music ---
	MusicManager.play_menu()
	
	mage_btn.pressed.connect(func(): _select_class("MAGE"))
	warrior_btn.pressed.connect(func(): _select_class("WARRIOR"))
	archer_btn.pressed.connect(func(): _select_class("ARCHER"))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	
	# --- ADDED: Hook up click sounds to all buttons ---
	_connect_click_sound(mage_btn)
	_connect_click_sound(warrior_btn)
	_connect_click_sound(archer_btn)
	_connect_click_sound(confirm_btn)
	_connect_click_sound(back_btn)

	# Hover effects
	mage_btn.mouse_entered.connect(func(): mage_btn.modulate = Color(0.5, 0.5, 0.5))
	mage_btn.mouse_exited.connect(func(): mage_btn.modulate = Color(1.0, 1.0, 1.0))
	warrior_btn.mouse_entered.connect(func(): warrior_btn.modulate = Color(0.5, 0.5, 0.5))
	warrior_btn.mouse_exited.connect(func(): warrior_btn.modulate = Color(1.0, 1.0, 1.0))
	archer_btn.mouse_entered.connect(func(): archer_btn.modulate = Color(0.5, 0.5, 0.5))
	archer_btn.mouse_exited.connect(func(): archer_btn.modulate = Color(1.0, 1.0, 1.0))

	confirm_btn.disabled = true
	selected_label.text  = "No class selected."
	passive_label.text   = ""
	stats_label.visible  = false

	mage_sprite.play("idle")
	warrior_sprite.play("idle")
	archer_sprite.play("idle")


# --- ADDED: Helper function to trigger click SFX ---
func _connect_click_sound(btn: BaseButton) -> void:
	btn.button_down.connect(func(): MusicManager.play_click())


func _select_class(cls: String) -> void:
	selected_class = cls
	var data := DatabaseManager.get_class_data(cls)

	selected_label.text  = "Selected: %s" % cls
	passive_label.text   = data.get("passive_description", "")
	stats_label.text     = "HP: %d    ATK: %d" % [data["base_hp"], data["base_atk"]]
	confirm_btn.disabled = false
	stats_label.visible  = true

	mage_sprite.play("idle")
	warrior_sprite.play("idle")
	archer_sprite.play("idle")

	match cls:
		"MAGE":    mage_sprite.play("run")
		"WARRIOR": warrior_sprite.play("run")
		"ARCHER":  archer_sprite.play("run")


func _on_confirm_pressed() -> void:
	if selected_class.is_empty():
		return
	var success := DatabaseManager.start_new_game(selected_class)
	if success:
		get_tree().change_scene_to_file("res://scenes/Map.tscn")
	else:
		push_error("ClassSelect: start_new_game failed for '%s'." % selected_class)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
