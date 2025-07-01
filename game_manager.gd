# GameManager.gd
extends Node

## Game Manager (Autoload Singleton)
## Handles scene transitions, pause state, and global game data management.
## NOTE: This node's 'Process Mode' must be set to 'Always' in Project Settings -> Autoload.

signal level_loaded(level_path: String)

@export var main_menu_scene: PackedScene = preload("res://Menus/main_menu.tscn")
@export var level_select_scene: PackedScene = preload("res://Menus/level_select.tscn")

var current_level_path: String = ""
var current_level_name: String = ""

# Node references
var gameplay_ui: CanvasLayer
var pause_menu: Control
var player_node: Node

# State variables
var is_mouse_captured: bool = true
var game_is_paused: bool = false


func _unhandled_input(event: InputEvent) -> void:
	# Only allow pausing if we are in a level
	if not current_level_path.is_empty() and event.is_action_pressed("ui_cancel"):
		toggle_pause_menu()

#region Registration
func register_gameplay_ui(ui_node: CanvasLayer) -> void:
	gameplay_ui = ui_node

func register_pause_menu(menu: Control) -> void:
	pause_menu = menu

func register_player(p_node: Node) -> void:
	player_node = p_node
#endregion

#region Scene Management
func goto_main_menu() -> void:
	if not main_menu_scene:
		push_error("Main Menu scene not set in GameManager!")
		return
	
	unpause_game(false) # Ensure game is unpaused when changing scenes
	current_level_path = ""
	current_level_name = ""
	get_tree().change_scene_to_packed(main_menu_scene)

func goto_level_select() -> void:
	if not level_select_scene:
		push_error("Level Select scene not set in GameManager!")
		return

	unpause_game(false)
	get_tree().change_scene_to_packed(level_select_scene)

func load_level(level_path: String) -> void:
	if level_path.is_empty() or not ResourceLoader.exists(level_path):
		push_error("Failed to load level: %s" % level_path)
		return
		
	unpause_game(true)
	current_level_path = level_path
	current_level_name = level_path.get_file().get_basename()
	
	# Clear old references
	pause_menu = null
	player_node = null
	
	get_tree().change_scene_to_file(level_path)
	level_loaded.emit(level_path)

func reload_current_level() -> void:
	if not current_level_path.is_empty():
		load_level(current_level_path)
	else:
		push_warning("No current level to reload.")
		goto_main_menu()

func quit_game() -> void:
	get_tree().quit()
#endregion

#region Pause System
func toggle_pause_menu() -> void:
	game_is_paused = not game_is_paused
	get_tree().paused = game_is_paused
	
	if game_is_paused:
		is_mouse_captured = false
		if is_instance_valid(gameplay_ui):
			gameplay_ui.hide()
		if is_instance_valid(pause_menu):
			pause_menu.show()
			pause_menu.resume_button.grab_focus()
	else:
		is_mouse_captured = true
		if is_instance_valid(gameplay_ui):
			gameplay_ui.show()
		if is_instance_valid(pause_menu):
			pause_menu.hide()
			
	update_mouse_mode()

func unpause_game(capture_mouse: bool) -> void:
	# Helper function to ensure game is unpaused before scene changes
	if get_tree().paused:
		get_tree().paused = false
	game_is_paused = false
	is_mouse_captured = capture_mouse
	update_mouse_mode()

func update_mouse_mode() -> void:
	if is_mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
#endregion

#region Data Persistence
func save_best_time(level_name: String, time: float) -> void:
	if level_name.is_empty(): return

	var save_path = "user://%s_save.json" % level_name
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var save_data = {"best_time": time}
		file.store_string(JSON.stringify(save_data))
		file.close() # CRITICAL FIX: This line ensures the data is written to disk.

func load_best_time(level_name: String) -> float:
	if level_name.is_empty(): return 0.0

	var save_path = "user://%s_save.json" % level_name
	if not FileAccess.file_exists(save_path):
		return 0.0
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file: return 0.0
	
	var content = file.get_as_text()
	file.close() # CRITICAL FIX: This ensures the file handle is released properly.
	var data = JSON.parse_string(content)
	
	# Check for corrupted or empty JSON data to prevent crash
	if not data or not data.has("best_time"):
		return 0.0
		
	return data["best_time"]

func delete_all_saved_times() -> void:
	var dir = DirAccess.open("user://")
	if not dir:
		push_error("Could not open user directory.")
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with("_save.json"):
			var error = dir.remove(file_name)
			if error != OK:
				push_error("Failed to delete file: %s" % file_name)
		file_name = dir.get_next()
	
	# After deleting, refresh the current level's UI if it's visible
	if is_instance_valid(gameplay_ui) and not current_level_name.is_empty():
		gameplay_ui.display_best_time()
#endregion
