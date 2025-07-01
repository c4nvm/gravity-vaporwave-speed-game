extends Control

# We'll link the nodes from the scene tree in the editor.
@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
# This assumes you have a child node named 'SettingsMenu' which is the settings panel.
@onready var settings_menu: Control = $MarginContainer/SettingsMenu

func _ready() -> void:
	# Explicitly set the mouse mode to visible for the main menu.
	GameManager.is_mouse_captured = false
	GameManager.update_mouse_mode()
	
	# Connect the 'pressed' signal of each button to a function.
	play_button.pressed.connect(_on_play_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

func _on_play_button_pressed() -> void:
	# Tell the global game manager to switch to the level select screen.
	GameManager.goto_level_select()

func _on_settings_button_pressed() -> void:
	# Show the settings menu panel.
	settings_menu.show()

func _on_quit_button_pressed() -> void:
	# Tell the global game manager to quit the application.
	GameManager.quit_game()
