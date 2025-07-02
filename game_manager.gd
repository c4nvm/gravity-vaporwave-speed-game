# This is a singleton (autoload) script that manages global game state,
# scene transitions, audio, and communication between different game nodes.
# NOTE: Ensure this is named "GameManager" in Project > Project Settings > Autoload

extends Node

# Path to the AudioManager scene.
var AUDIO_MANAGER_SCENE = preload("res://audio_manager.tscn")

# Holds the AudioManager instance.
var audio_manager: Node

# Emitted when a new level is loaded.
signal level_loaded(level_path: String, level_id: String)

# --- GLOBAL STATE ---
var can_pause := true # NEW: Flag to control if the game can be paused.
var is_mouse_captured: bool = false
var current_level_id: String = ""
var current_level_path: String = ""
var is_level_complete: bool = false

# --- NODE REFERENCES ---
var gameplay_ui: CanvasLayer = null
var player_node: CharacterBody3D = null
var pause_menu_instance: CanvasLayer = null
var compasses: Array[Node3D] = []
var fade_rect: ColorRect # Reference to the fade-to-black rectangle.

# --- DEBUGGING ---
var print_tree_timer: Timer


func _ready():
	# Process input when paused and during normal gameplay.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# --- Setup Fade Layer ---
	var fade_canvas = CanvasLayer.new()
	fade_canvas.layer = 128 # High value to ensure it's on top of all other UI.
	add_child(fade_canvas)
	
	fade_rect = ColorRect.new()
	# Start with black, but modulation will control visibility.
	fade_rect.color = Color.BLACK
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block mouse input.
	# Start invisible
	fade_rect.visible = false
	fade_canvas.add_child(fade_rect)

	# --- Existing _ready() code ---
	# Instantiate and add the AudioManager.
	audio_manager = AUDIO_MANAGER_SCENE.instantiate()
	add_child(audio_manager)

	# --- Setup for debounced scene tree printing ---
	print_tree_timer = Timer.new()
	print_tree_timer.wait_time = 0.05 # Small delay to batch rapid changes
	print_tree_timer.one_shot = true
	print_tree_timer.timeout.connect(_print_scene_tree)
	add_child(print_tree_timer)

	# Connect to scene tree changes to trigger the debug print.
	get_tree().node_added.connect(_on_scene_tree_changed)
	get_tree().node_removed.connect(_on_scene_tree_changed)


# -------------------------------------------------------------------
# ---                  PLAYER EVENT HOOKS (AUDIO LOGIC)           ---
# -------------------------------------------------------------------

func _on_player_first_move():
	# Start gameplay music on first move.
	audio_manager.start_gameplay_audio()


# --- GAME LOOP & INPUT ---
func _process(_delta: float) -> void:
	# MODIFIED: Check for pause input, but only if pausing is currently allowed.
	if can_pause and not current_level_path.is_empty() and is_instance_valid(pause_menu_instance) and not is_level_complete:
		if Input.is_action_just_pressed("ui_cancel"):
			toggle_pause_menu()

	# Don't run the rest of the game logic if paused.
	if get_tree().paused:
		return

	# --- Compass Logic ---
	if not is_instance_valid(player_node) or compasses.is_empty():
		return
		
	var current_gravity_dir: Vector3 = player_node.get("gravity_direction")
	var camera_pivot: Node3D = player_node.get("camera_pivot")
	
	if not is_instance_valid(camera_pivot):
		return

	var camera_basis: Basis = camera_pivot.global_transform.basis
	
	for compass in compasses:
		if is_instance_valid(compass):
			compass.update_compass(current_gravity_dir, camera_basis)


# --- SCENE TRANSITION EFFECTS ---
func start_level_fade_in(duration: float):
	"""
	Fades the screen in from black and controls the pause state.
	Called by the Player node when it's ready.
	"""
	if not is_instance_valid(fade_rect):
		push_error("Fade rectangle node is not valid.")
		return

	# Make sure pausing is disabled at the start of the fade.
	can_pause = false
	
	# Make it visible and instantly set to black, then tween to transparent.
	fade_rect.visible = true
	fade_rect.modulate = Color.BLACK
	
	var tween = create_tween()
	# Use a smooth curve for the fade.
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	
	# Animate the 'a' (alpha) channel of the modulate property to fade out the black screen.
	tween.tween_property(fade_rect, "modulate:a", 0.0, duration)
	
	# MODIFIED: When the tween finishes, hide the fade rectangle AND re-enable pausing.
	tween.tween_callback(func():
		fade_rect.visible = false
		can_pause = true
	)


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
	# Allow pausing in the main menu
	can_pause = true
	get_tree().change_scene_to_file("res://Menus/main_menu.tscn")
	update_mouse_mode(false)


func goto_level_select() -> void:
	_cleanup_before_scene_change()
	# Allow pausing in the level select menu (if applicable)
	can_pause = true
	get_tree().change_scene_to_file("res://Menus/level_select.tscn")
	update_mouse_mode(false)


func load_level(level_path: String) -> void:
	# MODIFIED: Disable pausing when starting to load a level.
	can_pause = false
	is_level_complete = false # Reset on new level load
	current_level_path = level_path
	current_level_id = level_path.get_file().get_basename()
	
	update_mouse_mode(true)
	get_tree().change_scene_to_file(level_path)
	
	level_loaded.emit(level_path, current_level_id)
	
	# Play waiting music on level load.
	audio_manager.play_waiting_music()


func reload_current_level() -> void:
	# MODIFIED: Disable pausing when reloading a level.
	can_pause = false
	is_level_complete = false # Reset on level reload
	
	# This function is called from the pause menu to restart the level.
	# Ensure the game is unpaused before reloading.
	get_tree().paused = false
	# Make sure the mouse is captured again for gameplay.
	update_mouse_mode(true)
	
	# Play waiting music on level restart.
	audio_manager.play_waiting_music()
	
	# Reload the currently active scene.
	get_tree().reload_current_scene()


func _cleanup_before_scene_change() -> void:
	is_level_complete = false # Reset when leaving a level
	get_tree().paused = false
	audio_manager.stop_all_music()
	
	current_level_id = ""
	current_level_path = ""
	
	gameplay_ui = null
	player_node = null
	if is_instance_valid(pause_menu_instance):
		pause_menu_instance.queue_free()
	pause_menu_instance = null
	
	compasses.clear()


# --- TIME SAVING & LOADING ---
const SAVE_DIR = "user://best_times/"

func save_best_time(time: float) -> void:
	# Don't run the level complete logic more than once.
	if is_level_complete:
		return
	is_level_complete = true
	
	if current_level_id.is_empty():
		push_error("Cannot save time - empty level ID!")
		return
	
	audio_manager.play_end_level_audio()

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


func delete_all_saved_times() -> void:
	# This function is called from the pause menu.
	var dir = DirAccess.open(SAVE_DIR)
	if dir == null:
		# This can happen if the directory was never created, which is not an error.
		print("Best times directory doesn't exist. Nothing to delete.")
		return

	# Iterate over all files in the directory and remove them.
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".dat"):
			var err = dir.remove(file_name)
			if err != OK:
				push_error("Failed to delete file: %s" % file_name)
		file_name = dir.get_next()
	
	# After deleting the files, if the gameplay UI is active, tell it to
	# reload the record time, which will now be non-existent.
	if is_instance_valid(gameplay_ui):
		gameplay_ui.load_record_time()


# --- APPLICATION CONTROL ---
func quit_game() -> void:
	if OS.get_name() == "HTML5":
		JavaScriptBridge.eval("window.close()", true)
	else:
		get_tree().quit()


# --- NODE REGISTRATION ---
func register_gameplay_ui(ui_instance: CanvasLayer) -> void:
	gameplay_ui = ui_instance


func register_player(p_node: CharacterBody3D) -> void:
	player_node = p_node


func register_pause_menu(menu_instance: CanvasLayer) -> void:
	pause_menu_instance = menu_instance
	pause_menu_instance.hide()


func register_compass(compass: Node3D) -> void:
	if not compass in compasses:
		compasses.append(compass)


func unregister_compass(compass: Node3D) -> void:
	if compass in compasses:
		compasses.erase(compass)


# --- DEBUGGING ---
func _on_scene_tree_changed(_node: Node):
	# Start or restart the timer to print the tree after a short delay.
	# This prevents printing for every single node change during a batch operation.
	print_tree_timer.start()


func _print_scene_tree() -> void:
	print("--- SCENE TREE (Updated) ---")
	_print_node_and_children(get_tree().get_root(), "")
	print("----------------------------")


func _print_node_and_children(node: Node, prefix: String) -> void:
	# Print the current node's name and type.
	print(prefix + "- " + node.name + " (" + str(node.get_class()) + ")")
	
	# Recursively call this function for all children.
	for child in node.get_children():
		_print_node_and_children(child, prefix + "  ")
