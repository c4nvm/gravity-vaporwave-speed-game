# PauseMenu.gd
extends CanvasLayer

## Pause Menu
## Handles all pause menu interactions and confirmations.

@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var delete_times_button: Button = %DeleteTimesButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var confirmation_dialog: ConfirmationDialog = $PauseMenu/ConfirmationDialog

enum Action { RESTART, DELETE_TIMES, MAIN_MENU }
var current_confirmation_action: Action

func _ready() -> void:
	# Register this instance with the GameManager so it can be controlled.
	GameManager.register_pause_menu(self)
	
	# This menu should be hidden when the level starts.
	hide()
	
	# --- Connect button signals ---
	resume_button.pressed.connect(GameManager.toggle_pause_menu)
	restart_button.pressed.connect(_on_restart_pressed)
	delete_times_button.pressed.connect(_on_delete_times_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	# --- Connect confirmation dialog signals ---
	confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	confirmation_dialog.visibility_changed.connect(_on_confirmation_visibility_changed)

func _on_restart_pressed() -> void:
	current_confirmation_action = Action.RESTART
	show_confirmation("Restart Level", "Are you sure you want to restart? Your current run will be lost.")

func _on_delete_times_pressed() -> void:
	current_confirmation_action = Action.DELETE_TIMES
	show_confirmation("Delete All Times", "This will permanently delete ALL saved times for EVERY level. This cannot be undone.")

func _on_main_menu_pressed() -> void:
	current_confirmation_action = Action.MAIN_MENU
	show_confirmation("Return to Menu", "Are you sure you want to return to the main menu? Your current run will be lost.")

func show_confirmation(title: String, message: String) -> void:
	confirmation_dialog.title = title
	confirmation_dialog.dialog_text = message
	confirmation_dialog.popup_centered()
	set_buttons_disabled(true)

func _on_confirmation_confirmed() -> void:
	match current_confirmation_action:
		Action.RESTART:
			# GameManager handles unpausing and scene change
			GameManager.reload_current_level()
		Action.DELETE_TIMES:
			GameManager.delete_all_saved_times()
		Action.MAIN_MENU:
			# GameManager handles unpausing and scene change
			GameManager.goto_main_menu()

func _on_confirmation_visibility_changed() -> void:
	# Re-enable buttons if the confirmation dialog is hidden (e.g., by pressing Esc)
	if not confirmation_dialog.visible:
		set_buttons_disabled(false)

func set_buttons_disabled(disabled: bool) -> void:
	resume_button.disabled = disabled
	restart_button.disabled = disabled
	delete_times_button.disabled = disabled
	main_menu_button.disabled = disabled
