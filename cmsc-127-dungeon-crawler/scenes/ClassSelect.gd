extends Control

var selected_class: String = ""

@onready var mage_btn:      Button = $MarginContainer/VBoxContainer/ClassCards/MageCard/SelectMage
@onready var berserker_btn: Button = $MarginContainer/VBoxContainer/ClassCards/BerserkerCard/SelectBerserker
@onready var archer_btn:    Button = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/SelectArcher

@onready var mage_stats:      Label = $MarginContainer/VBoxContainer/ClassCards/MageCard/StatsLabel
@onready var berserker_stats: Label = $MarginContainer/VBoxContainer/ClassCards/BerserkerCard/StatsLabel
@onready var archer_stats:    Label = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/StatsLabel

@onready var selected_label: Label  = $MarginContainer/VBoxContainer/SelectedLabel
@onready var passive_label:  Label  = $MarginContainer/VBoxContainer/PassiveLabel
@onready var confirm_btn:    Button = $MarginContainer/VBoxContainer/ConfirmButton
@onready var back_btn:       Button = $MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	mage_btn.pressed.connect(func(): _select_class("MAGE"))
	berserker_btn.pressed.connect(func(): _select_class("BERSERKER"))
	archer_btn.pressed.connect(func(): _select_class("ARCHER"))
	confirm_btn.pressed.connect(_on_confirm_pressed)
	back_btn.pressed.connect(_on_back_pressed)

	confirm_btn.disabled = true
	selected_label.text  = "No class selected."
	passive_label.text   = ""

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
