extends CanvasLayer

@onready var timer_label: Label = %TimerLabel
@onready var record_time_label: Label = %BestTimeLabel
@onready var debug_label: Label = %DebugLabel
@onready var compass_viewport: SubViewport = $CompassViewport
@onready var compass_sprite: Sprite2D = $CompassSprite

var current_level_id: String = ""
var current_record: float = 0.0
var player: CharacterBody3D
var compass_instance: Node3D # Renamed for clarity

func _ready() -> void:
	GameManager.register_gameplay_ui(self)
	
	# --- MODIFIED: Get the player reference from the GameManager ---
	# This assumes the player is ready before the UI.
	# A signal-based approach could be more robust if load order varies.
	player = GameManager.player_node
	# ----------------------------------------------------------------
	
	# Set default text values
	record_time_label.text = "Record: --:--:---"
	timer_label.text = "00:00:000"

	# Directly get the level ID from the GameManager when the UI is ready.
	current_level_id = GameManager.current_level_id
	
	# Call the function to load and display the record.
	load_record_time()
	
	# Load and setup the 3D compass
	var loaded_scene = preload("res://Compass.tscn").instantiate()
	if loaded_scene is Node3D:
		compass_instance = loaded_scene
		compass_viewport.add_child(compass_instance)
	else:
		push_error("Failed to load Compass.tscn as a Node3D")

	# Configure viewport
	compass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	compass_viewport.transparent_bg = true
	compass_sprite.texture = compass_viewport.get_texture()

func _process(delta: float) -> void:
	# --- MODIFIED: Check if player is valid before updating ---
	if is_instance_valid(player):
		update_compass()
	# --------------------------------------------------------

func update_compass() -> void:
	# Also check if the compass instance is valid
	if not is_instance_valid(compass_instance):
		return
	
	# --- MODIFIED: Get the camera pivot's global basis for full rotation ---
	# This is the key change: camera_pivot has both yaw and pitch.
	var camera_basis = player.camera_pivot.global_transform.basis
	# ---------------------------------------------------------------------
	
	# Update the 3D compass with the player's gravity and camera orientation
	compass_instance.update_compass(player.gravity_direction, camera_basis)

# This function can now be removed or kept as a fallback
# func set_player_reference(player_ref: CharacterBody3D) -> void:
# 	player = player_ref

func load_record_time() -> void:
	if current_level_id.is_empty():
		return
	
	current_record = GameManager.load_best_time(current_level_id)
	
	if current_record > 0.0:
		record_time_label.text = "Record: " + format_time(current_record)
	else:
		record_time_label.text = "Record: No record"

func update_timer(time_in_seconds: float) -> void:
	timer_label.text = format_time(time_in_seconds)

func show_final_time(final_time: float) -> void:
	timer_label.text = "Time: " + format_time(final_time)

	if current_record <= 0.0 or final_time < current_record:
		GameManager.save_best_time(final_time)
		current_record = final_time
		record_time_label.text = "New Record: " + format_time(final_time)
		set_timer_visibility(Color.GOLD)
	else:
		record_time_label.text = "Record: " + format_time(current_record)
		set_timer_visibility(Color.WHITE)

func set_timer_visibility(color: Color) -> void:
	timer_label.add_theme_color_override("font_color", color)

func update_debug_info(debug_string: String, velocity: Vector3) -> void:
	# Renamed from update_debug to avoid conflict and be more descriptive
	var vel_text = "Vel: (%.1f, %.1f, %.1f)" % [velocity.x, velocity.y, velocity.z]
	debug_label.text = debug_string + "\n" + vel_text

func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60)
	var secs := int(seconds) % 60
	var ms := int(fmod(seconds, 1.0) * 1000)
	return "%02d:%02d:%03d" % [minutes, secs, ms]
