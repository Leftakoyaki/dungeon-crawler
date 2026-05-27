extends Control

var selected_class: String = ""

@onready var mage_btn:      Button = $MarginContainer/VBoxContainer/ClassCards/MageCard/SelectMage
@onready var warrior_btn:   Button = $MarginContainer/VBoxContainer/ClassCards/WarriorCard/SelectWarrior
@onready var archer_btn:    Button = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/SelectArcher
@onready var mage_stats:    Label  = $MarginContainer/VBoxContainer/ClassCards/MageCard/StatsLabel
@onready var warrior_stats: Label  = $MarginContainer/VBoxContainer/ClassCards/WarriorCard/StatsLabel
@onready var archer_stats:  Label  = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/StatsLabel
@onready var mage_name:     Label  = $MarginContainer/VBoxContainer/ClassCards/MageCard/NameLabel
@onready var warrior_name:  Label  = $MarginContainer/VBoxContainer/ClassCards/WarriorCard/NameLabel
@onready var archer_name:   Label  = $MarginContainer/VBoxContainer/ClassCards/ArcherCard/NameLabel
@onready var selected_label: Label  = $MarginContainer/VBoxContainer/SelectedLabel
@onready var passive_label:  Label  = $MarginContainer/VBoxContainer/PassiveLabel
@onready var confirm_btn:    Button = $MarginContainer/VBoxContainer/ConfirmButton
@onready var back_btn:       Button = $MarginContainer/VBoxContainer/BackButton

func _ready() -> void:
	mage_btn.pressed.connect(func(): _select_class("MAGE"))
	warrior_btn.pressed.connect(func(): _select_class("WARRIOR"))
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
			"MAGE":
				mage_stats.text = stats_text
				mage_name.text  = cls["class_name"]
			"WARRIOR":
				warrior_stats.text = stats_text
				warrior_name.text  = cls["class_name"]
			"ARCHER":
				archer_stats.text = stats_text
				archer_name.text  = cls["class_name"]

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
