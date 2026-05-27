extends Control

var selected_class: String = ""

# Buttons
@onready var mage_btn: TextureButton = $SelectMage
@onready var berserker_btn: TextureButton = $SelectBerserker
@onready var archer_btn: TextureButton = $SelectArcher

# We now only have one label for stats
@onready var stats_label: Label = $StatsLabel

@onready var selected_label: Label = $SelectedLabel
@onready var passive_label: Label = $PassiveLabel
@onready var confirm_btn: Button = $ConfirmButton
@onready var back_btn: Button = $BackButton

# Sprites
@onready var mage_sprite: AnimatedSprite2D = $Animations/MageSprite
@onready var berserker_sprite: AnimatedSprite2D = $Animations/BerserkerSprite
@onready var archer_sprite: AnimatedSprite2D = $Animations/ArcherSprite

func _ready() -> void:
	mage_btn.pressed.connect(func(): _select_class("MAGE"))
	berserker_btn.pressed.connect(func(): _select_class("BERSERKER"))
	archer_btn.pressed.connect(func(): _select_class("ARCHER"))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	back_btn.pressed.connect(_on_back_pressed)

	# Mouse hover effects
	mage_btn.mouse_entered.connect(func(): mage_btn.modulate = Color(0.5, 0.5, 0.5))
	mage_btn.mouse_exited.connect(func(): mage_btn.modulate = Color(1.0, 1.0, 1.0))
	berserker_btn.mouse_entered.connect(func(): berserker_btn.modulate = Color(0.5, 0.5, 0.5))
	berserker_btn.mouse_exited.connect(func(): berserker_btn.modulate = Color(1.0, 1.0, 1.0))
	archer_btn.mouse_entered.connect(func(): archer_btn.modulate = Color(0.5, 0.5, 0.5))
	archer_btn.mouse_exited.connect(func(): archer_btn.modulate = Color(1.0, 1.0, 1.0))

	confirm_btn.disabled = true
	selected_label.text = "No class selected."
	passive_label.text = ""
	
	# Stats hidden at start
	stats_label.visible = false

	mage_sprite.play("idle")
	berserker_sprite.play("idle")
	archer_sprite.play("idle")

func _select_class(cls: String) -> void:
	selected_class = cls
	var data := DatabaseManager.get_class_data(cls)
	
	# Update text
	selected_label.text = "Selected: %s" % cls
	passive_label.text = data.get("passive_description", "")
	# Update the single stats label with HP and ATK
	stats_label.text = "HP: %d    ATK: %d" % [data["base_hp"], data["base_atk"]]
	
	confirm_btn.disabled = false
	stats_label.visible = true

	# Reset animations
	mage_sprite.play("idle")
	berserker_sprite.play("idle")
	archer_sprite.play("idle")
	
	# Play run animation
	match cls:
		"MAGE": mage_sprite.play("run")
		"BERSERKER": berserker_sprite.play("run")
		"ARCHER": archer_sprite.play("run")

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
