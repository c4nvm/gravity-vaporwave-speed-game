# 6DOF (Six Degrees of Freedom) free-flight movement state.
# Features camera-relative movement, smooth acceleration, and full 360-degree rotation.
extends State

# --- MOVEMENT SETTINGS ---
@export_group("Movement")
@export var speed := 12.0
@export var acceleration := 5.0 # Higher = more responsive, Lower = floatier.

@export_group("Rotation")
@export var roll_speed := 3.0
@export var roll_decay := 8.0 # How fast roll stops after input.

# --- STATE VARIABLES ---
# Player's rotation (x: pitch, y: yaw, z: roll).
var _rotation := Vector3.ZERO

# Player's velocity relative to its own direction. Preserves momentum when turning.
var _local_velocity := Vector3.ZERO


# Called once when entering this state.
func enter():
	# Initialize state from player's current transform for a smooth transition.

	# Convert global velocity to local to preserve momentum.
	_local_velocity = player.transform.basis.inverse() * player.velocity

	# Match player's orientation to prevent camera snapping.
	_rotation = player.transform.basis.get_euler(EULER_ORDER_YXZ)


# Called once when exiting this state.
func exit():
	# Mouse cursor is intentionally not released, in case the next state needs it.
	pass


# Handles mouse input for camera control.
func process_input(event: InputEvent):
	if event is InputEventMouseMotion:
		# Get mouse sensitivity from the GameManager.
		if not GameManager.current_sensitivity:
			push_warning("GameManager missing 'current_sensitivity' variable.")
			return

		var sensitivity_rad = GameManager.current_sensitivity / 1000

		# Check if the player is upside down (local 'up' vector points down globally).
		var is_upside_down := player.transform.basis.y.y < 0.0

		# Update yaw based on horizontal mouse movement.
		# Invert control when upside down for intuitive movement.
		if is_upside_down:
			_rotation.y += event.relative.x * sensitivity_rad
		else:
			_rotation.y -= event.relative.x * sensitivity_rad

		# Update pitch based on vertical mouse movement.
		_rotation.x -= event.relative.y * sensitivity_rad

# Handles physics updates for movement and rotation.
func process_physics(delta: float):
	# 1. Get player input.
	var move_input := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	var roll_input := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")

	# 2. Update rotation.
	_rotation.z += roll_input * roll_speed * delta

	# Smoothly dampen roll when there is no input.
	if is_zero_approx(roll_input):
		_rotation.z = lerp(_rotation.z, 0.0, roll_decay * delta)

	# Apply rotation from Euler angles. YXZ order is ideal for first-person views.
	player.transform.basis = Basis.from_euler(_rotation, EULER_ORDER_YXZ)

	# 3. Update velocity.
	# Godot's forward is -Z, so we negate the y-axis of the input vector.
	var desired_direction = Vector3(move_input.x, vertical_input, -move_input.y)
	var target_velocity = desired_direction.normalized() * speed

	# Lerp to the target velocity for smooth acceleration.
	_local_velocity = _local_velocity.lerp(target_velocity, acceleration * delta)

	# 4. Apply movement.
	# Convert local velocity to world velocity based on current orientation.
	player.velocity = player.transform.basis * _local_velocity
	player.move_and_slide()


# Handles state transition logic.
func get_next_state() -> String:
	# Example: return "WalkState" if player is near a planet.
	# if player.is_near_planet():
	# 	return "PlanetaryMovement"
	return ""
