extends State

# Movement settings
@export var swim_speed := 12.0
# Acceleration now controls how quickly you reach swim_speed. Lower is floatier.
@export var swim_accel := 8.0
@export var mouse_sensitivity := 0.0012
@export var roll_speed := 3.0
@export var roll_decay := 0.95

# Raw rotation tracking
var _pitch := 0.0
var _yaw := 0.0

func enter():
	player._enter_free_space_mode()
	
	# Correctly convert incoming world velocity to local velocity to preserve momentum.
	player.free_space_velocity = player.transform.basis.inverse() * player.velocity

	# Initialize rotation from the player's current transform to prevent snapping.
	var current_euler = player.transform.basis.get_euler(EulerOrder.EULER_ORDER_ZYX)
	_pitch = current_euler.x
	_yaw = current_euler.y
	player.free_space_roll = -current_euler.z


func exit():
	player._enter_planetary_mode()


func process_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Direct unfiltered mouse input
		_pitch -= event.relative.y * mouse_sensitivity
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch, -PI/2, PI/2)


func process_physics(delta):
	# Immediate rotation application
	var rot = Basis()
	rot = rot.rotated(Vector3.RIGHT, _pitch)
	rot = rot.rotated(Vector3.UP, _yaw)
	rot = rot.rotated(Vector3.BACK, player.free_space_roll)
	player.transform.basis = rot.orthonormalized()
	
	# Roll input (minimal decay)
	if Input.is_action_pressed("roll_left"):
		player.free_space_roll += roll_speed * delta
	if Input.is_action_pressed("roll_right"):
		player.free_space_roll -= roll_speed * delta
	player.free_space_roll *= roll_decay
	
	# --- Start of floaty movement logic ---
	# Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	var move_dir = Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()
	
	# Define the velocity we want to reach based on input
	var target_velocity = move_dir * swim_speed
	
	# Smoothly move the current velocity towards the target velocity
	player.free_space_velocity = player.free_space_velocity.move_toward(target_velocity, swim_accel * delta)
	
	# Apply the final velocity
	player.velocity = player.transform.basis * player.free_space_velocity
	player.move_and_slide()
	# --- End of floaty movement logic ---


func get_next_state() -> String:
	return ""
