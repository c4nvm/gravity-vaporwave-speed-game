# FreeSpace.gd
extends State

# Movement settings
@export var swim_speed := 12.0
@export var swim_accel := 8.0
@export var roll_speed := 3.0
@export var roll_decay := 0.95

# Rotation tracking
var _pitch := 0.0
var _yaw := 0.0

func enter():
	player._enter_free_space_mode()
	player.free_space_velocity = player.velocity * 0.5
	_pitch = 0.0
	_yaw = 0.0
	player.free_space_roll = 0.0

func exit():
	player._enter_planetary_mode()

func process_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Use player's mouse sensitivity directly
		_pitch -= event.relative.y * player.mouse_sensitivity * 0.001
		_yaw -= event.relative.x * player.mouse_sensitivity * 0.001
		_pitch = clamp(_pitch, -PI/2, PI/2)

func process_physics(_delta):
	# Apply raw rotation immediately
	var rot = Basis()
	rot = rot.rotated(Vector3.RIGHT, _pitch)
	rot = rot.rotated(Vector3.UP, _yaw)
	rot = rot.rotated(Vector3.BACK, player.free_space_roll)
	player.transform.basis = rot.orthonormalized()
	
	# Handle roll input
	if Input.is_action_pressed("roll_left"):
		player.free_space_roll += roll_speed * _delta
	if Input.is_action_pressed("roll_right"):
		player.free_space_roll -= roll_speed * _delta
	player.free_space_roll *= roll_decay
	
	# Movement input (direct with no smoothing)
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	var move_dir = Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()
	
	# Direct velocity application
	player.free_space_velocity = move_dir * swim_speed
	player.velocity = player.transform.basis * player.free_space_velocity
	player.move_and_slide()

func get_next_state() -> String:
	return ""
