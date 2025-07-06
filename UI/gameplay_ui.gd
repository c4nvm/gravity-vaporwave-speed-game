extends CanvasLayer

@onready var timer_label: Label = %TimerLabel
@onready var record_time_label: Label = %BestTimeLabel
@onready var debug_label: Label = %DebugLabel
@onready var compass_viewport: SubViewport = $CompassViewport

var current_level_id: String = ""
var current_record: float = 0.0
var player: CharacterBody3D
var compass_instance: Node3D

func _ready() -> void:
	GameManager.register_gameplay_ui(self)
	
	# Attempt to get the player node immediately. It might be null if the UI is ready first.
	player = GameManager.player_node
	
	record_time_label.text = "Record: --:--:---"
	timer_label.text = "00:00:000"

	current_level_id = GameManager.current_level_id
	
	load_record_time()
	
	var loaded_scene = preload("res://compass.tscn").instantiate()
	if loaded_scene is Node3D:
		compass_instance = loaded_scene
		compass_viewport.add_child(compass_instance)
	else:
		push_error("Failed to load Compass.tscn as a Node3D")

	compass_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	compass_viewport.transparent_bg = true
	
	await get_tree().process_frame
	
	self.visible = true

func _process(delta: float) -> void:
	# If the player reference is not yet valid, try to get it from the GameManager.
	# This handles cases where the UI is ready before the player has registered itself.
	if not is_instance_valid(player):
		player = GameManager.player_node
		# If it's still not valid, we can't do anything yet, so we wait for the next frame.
		if not is_instance_valid(player):
			# Hide the debug label if there is no player
			debug_label.text = "State: N/A\nVel: (0.0, 0.0, 0.0)"
			return

	# Once we have a valid player reference, update the UI elements.
	update_compass()
	_update_debug_label()

func _update_debug_label():
	"""Pulls data from the player and updates the debug label."""
	var state_name = "N/A"
	# Check if the state machine and its current state are valid before accessing them.
	if player.has_node("StateMachine") and player.state_machine.current_state:
		state_name = player.state_machine.current_state.name

	# Format the velocity and state information.
	var vel_text = "Vel: (%.1f, %.1f, %.1f)" % [player.velocity.x, player.velocity.y, player.velocity.z]
	debug_label.text = "State: %s\n%s" % [state_name, vel_text]

func update_compass() -> void:
	if not is_instance_valid(compass_instance):
		return
	
	# This requires a 'camera_pivot' node on your player.
	if not player.has_node("CameraPivot"): return
	var camera_pivot = player.get_node("CameraPivot")
	
	var camera_basis = camera_pivot.global_transform.basis
	
	compass_instance.update_compass(player.gravity_direction, camera_basis)

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

func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60)
	var secs := int(seconds) % 60
	var ms := int(fmod(seconds, 1.0) * 1000)
	return "%02d:%02d:%03d" % [minutes, secs, ms]
