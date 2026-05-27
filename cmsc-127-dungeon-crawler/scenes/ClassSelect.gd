extends Control

var selected_class: String = ""

#grab the buttonsfrom root node now
@onready var mage_btn: TextureButton = $SelectMage
@onready var berserker_btn: TextureButton = $SelectBerserker
@onready var archer_btn: TextureButton = $SelectArcher

@onready var mage_stats:      Label = $MarginContainer/VBoxContainer/ClassCards/MageCard/StatsLabel
@onready var berserker_stats: Label = $MarginContainer/VBoxContainer/ClassCards/BerserkerCard/StatsLabel
@onready var archer_stats:    Label = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/StatsLabel
#if u moved the labels out of the folders too they should look like this
@onready var selected_label: Label = $SelectedLabel
#grab the passive label from inside the folders
@onready var passive_label: Label = $PassiveLabel#if u moved confirm and back out of the folders make sure they look like this
@onready var confirm_btn:    Button = $ConfirmButton
@onready var back_btn:       Button = $BackButton

#grab the spritesfrom the animations node
@onready var mage_sprite: AnimatedSprite2D = $Animations/MageSprite
@onready var berserker_sprite: AnimatedSprite2D = $Animations/BerserkerSprite
@onready var archer_sprite: AnimatedSprite2D = $Animations/ArcherSprite


func _ready() -> void:
	mage_btn.pressed.connect(func(): _select_class("MAGE"))
	berserker_btn.pressed.connect(func(): _select_class("BERSERKER"))
	archer_btn.pressed.connect(func(): _select_class("ARCHER"))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	back_btn.pressed.connect(_on_back_pressed)

	#grey out when mouse touchesthem
	mage_btn.mouse_entered.connect(func(): mage_btn.modulate = Color(0.5, 0.5, 0.5))
	mage_btn.mouse_exited.connect(func(): mage_btn.modulate = Color(1.0, 1.0, 1.0))
	
	berserker_btn.mouse_entered.connect(func(): berserker_btn.modulate = Color(0.5, 0.5, 0.5))
	berserker_btn.mouse_exited.connect(func(): berserker_btn.modulate = Color(1.0, 1.0, 1.0))
	
	archer_btn.mouse_entered.connect(func(): archer_btn.modulate = Color(0.5, 0.5, 0.5))
	archer_btn.mouse_exited.connect(func(): archer_btn.modulate = Color(1.0, 1.0, 1.0))

	confirm_btn.disabled = true
	selected_label.text  = "No class selected."
	passive_label.text   = ""

	#make everyone idleat the start
	mage_sprite.play("idle")
	berserker_sprite.play("idle")
	archer_sprite.play("idle")

	_populate_class_stats()


func _populate_class_stats() -> void:
	var classes := DatabaseManager.get_all_classes()
	for cls in classes:
		var stats_text := "HP: %d   ATK: %d" % [cls["base_hp"], cls["base_atk"]]
		match cls["class_name"]:
			"MAGE":      mage_stats.text      = stats_text
			"BERSERKER": berserker_stats.text = stats_text
			"ARCHER":    archer_stats.text    = stats_text


func _select_class(cls: String) -> void:
	selected_class = cls
	var data := DatabaseManager.get_class_data(cls)
	selected_label.text  = "Selected: %s" % cls
	passive_label.text   = data.get("passive_description", "")
	confirm_btn.disabled = false

	#make everyone idlefirst
	mage_sprite.play("idle")
	berserker_sprite.play("idle")
	archer_sprite.play("idle")
	
	#make the chosenone run
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
