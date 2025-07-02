# main.gd
extends Node

# Set the path to your main menu scene.
@export var main_menu_scene: PackedScene = preload("res://Menus/main_menu.tscn")

func _ready() -> void:
	# When the game starts, this main node will immediately
	# add the main menu as a child, effectively loading it.
	var menu_instance = main_menu_scene.instantiate()
	add_child(menu_instance)
