extends Node

# Signal emitted when a new level is loaded, with both path and ID
signal level_loaded(level_path: String, level_id: String)

# --- GLOBAL STATE ---
var is_mouse_captured: bool = false
var current_level_id: String = ""
var current_level_path: String = ""

# --- NODE REFERENCES ---
var gameplay_ui: CanvasLayer = null
var player_node: CharacterBody3D = null
var pause_menu_instance: Control = null

# --- MOUSE MANAGEMENT ---
func update_mouse_mode(capture: bool = false) -> void:
	is_mouse_captured = capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE)

# --- PAUSE MANAGEMENT ---
func toggle_pause_menu() -> void:
	if not is_instance_valid(pause_menu_instance):
		push_error("No pause menu registered!")
		return

	var new_paused_state = not get_tree().paused
	get_tree().paused = new_paused_state
	pause_menu_instance.visible = new_paused_state
	update_mouse_mode(not new_paused_state)

# --- SCENE MANAGEMENT ---
func goto_main_menu() -> void:
	_cleanup_before_scene_change()
	get_tree().change_scene_to_file("res://Menus/main_menu.tscn")
	update_mouse_mode(false)

func goto_level_select() -> void:
	_cleanup_before_scene_change()
	get_tree().change_scene_to_file("res://Menus/level_select.tscn")
	update_mouse_mode(false)

func load_level(level_path: String) -> void:
	# This is the single source of truth for the level ID.
	current_level_path = level_path
	current_level_id = level_path.get_file().get_basename()
	
	update_mouse_mode(true)
	get_tree().change_scene_to_file(level_path)
	level_loaded.emit(level_path, current_level_id)

func _cleanup_before_scene_change() -> void:
	get_tree().paused = false
	
	# Clear level-specific data
	current_level_id = ""
	current_level_path = ""
	
	# Clear node references
	gameplay_ui = null
	player_node = null
	if is_instance_valid(pause_menu_instance):
		pause_menu_instance.queue_free()
	pause_menu_instance = null

# --- APPLICATION CONTROL ---
func quit_game() -> void:
	# Handle web platform differently if needed
	if OS.get_name() == "HTML5":
		# This is a placeholder and might not work in all browsers due to security restrictions.
		JavaScriptBridge.eval("window.close()", true)
	else:
		get_tree().quit()

# --- NODE REGISTRATION ---
func register_gameplay_ui(ui_instance: CanvasLayer) -> void:
	gameplay_ui = ui_instance

func register_player(p_node: CharacterBody3D) -> void:
	player_node = p_node

func register_pause_menu(menu_instance: Control) -> void:
	pause_menu_instance = menu_instance
	pause_menu_instance.hide() # Start hidden

# --- TIME SAVING & LOADING ---
const SAVE_DIR = "user://best_times/"

func save_best_time(time: float) -> void:
	if current_level_id.is_empty():
		push_error("Cannot save time - empty level ID!")
		return

	var dir = DirAccess.open("user://")
	if dir == null:
		push_error("Failed to access user data directory!")
		return

	if not dir.dir_exists("best_times"):
		var err = dir.make_dir("best_times")
		if err != OK:
			push_error("Failed to create best_times directory!")
			return

	var file_path = SAVE_DIR.path_join(current_level_id + ".dat")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save time for %s. Error: %s" % [current_level_id, FileAccess.get_open_error()])
		return

	file.store_float(time)
	file.close()

func load_best_time(level_id_to_load: String) -> float:
	if level_id_to_load.is_empty():
		return 0.0

	var file_path = SAVE_DIR.path_join(level_id_to_load + ".dat")
	if not FileAccess.file_exists(file_path):
		return 0.0

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Failed to load time for %s. Error: %s" % [level_id_to_load, FileAccess.get_open_error()])
		return 0.0

	var time = file.get_float()
	file.close()
	return time
