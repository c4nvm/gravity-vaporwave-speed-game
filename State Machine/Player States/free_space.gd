#
# Streamlined 6DOF (Six Degrees of Freedom) Movement State for Godot 4
#
# This state provides free-flight movement, similar to a spaceship or a character swimming.
#
# Key Features:
# - Player's movement is always relative to the camera's direction ("forward" is where you look).
# - Smooth, acceleration-based "floaty" movement using LERP.
# - Full 360-degree rotation: pitch (looking up/down), yaw (turning left/right), and roll.
# - The state is self-contained and uses standard Godot Input mapping.
#
extends State

# --- EXPORTS (Movement Configuration) ---
@export_group("Movement")
@export var speed := 12.0
@export var acceleration := 5.0 # Higher is more responsive, lower is "floatier".

@export_group("Rotation")
# REMOVED: mouse_sensitivity is now fetched from the main player script.
@export var roll_speed := 3.0
@export var roll_decay := 8.0 # How quickly roll stops when input is released.

# --- STATE VARIABLES ---
# We track rotation as Euler angles to easily clamp pitch and avoid gimbal lock.
var _rotation := Vector3.ZERO # x: pitch, y: yaw, z: roll

# Stores the player's velocity relative to its own orientation.
# This is the key to preserving momentum correctly during rotation.
var _local_velocity := Vector3.ZERO


# Called once when the state machine enters this state.
func enter():

	# --- PRESERVE MOMENTUM & ORIENTATION ---
	# To ensure a smooth transition into this state, we initialize our state
	# variables from the player's current transform.

	# 1. Preserve momentum: Convert the player's global velocity into local velocity.
	_local_velocity = player.transform.basis.inverse() * player.velocity

	# 2. Preserve orientation: Set our internal rotation to match the player's.
	#    This prevents the camera from snapping to a new direction on entry.
	_rotation = player.transform.basis.get_euler(EULER_ORDER_YXZ)


# Called once when the state machine exits this state.
func exit():
	# Per user request, the mouse cursor is NOT released upon exiting this state.
	# This is useful if the next state also requires a captured mouse.
	pass


# Handles mouse input for looking around.
func process_input(event: InputEvent):
	if event is InputEventMouseMotion:
		# Ensure the player script has a 'mouse_sensitivity' variable.
		if not GameManager.current_sensitivity:
			push_warning("Player script is missing a 'mouse_sensitivity' variable.")
			return

		# Convert sensitivity (read from player script) to radians for rotation.
		var sensitivity_rad = GameManager.current_sensitivity/1000

		# --- Check if the player is upside down ---
		# We determine this by checking if the player's local 'up' vector (basis.y)
		# is pointing downwards in world space (its world y-component is negative).
		var is_upside_down := player.transform.basis.y.y < 0.0

		# Modify yaw and pitch based on mouse movement.
		# We subtract yaw because moving the mouse right (positive x) should turn right (negative yaw).
		if is_upside_down:
			# When upside down, reverse the horizontal mouse input for yaw.
			_rotation.y += event.relative.x * sensitivity_rad
		else:
			# Normal yaw controls.
			_rotation.y -= event.relative.x * sensitivity_rad
		
		# Pitch is controlled by vertical mouse movement and is unaffected.
		_rotation.x -= event.relative.y * sensitivity_rad

		# Clamp the pitch to prevent the camera from flipping upside down.
		# _rotation.x = clamp(_rotation.x, -PI / 2.0, PI / 2.0)


# Handles all physics-based updates for movement and rotation.
func process_physics(delta: float):
	# --- 1. HANDLE INPUTS ---
	# Using your project's specific input actions.
	var move_input := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	var roll_input := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")

	# --- 2. UPDATE ROTATION ---
	# Apply roll input directly.
	_rotation.z += roll_input * roll_speed * delta

	# If there's no roll input, smoothly decay the roll back to zero.
	if is_zero_approx(roll_input):
		_rotation.z = lerp(_rotation.z, 0.0, roll_decay * delta)

	# Construct the final rotation basis from our Euler angles.
	# Using YXZ order is common for "first-person" style controls where you
	# yaw the body, then pitch the head up/down, then optionally roll.
	player.transform.basis = Basis.from_euler(_rotation, EULER_ORDER_YXZ)

	# --- 3. UPDATE VELOCITY ---
	# Determine the desired movement direction in the player's local space.
	# The z-component is negative because the second pair in get_vector maps to the Y axis
	# of the vector, and Godot's forward direction is -Z.
	var desired_direction = Vector3(move_input.x, vertical_input, -move_input.y)

	# Calculate the target velocity based on the input direction and speed.
	var target_velocity = desired_direction.normalized() * speed

	# Smoothly interpolate the current velocity towards the target.
	# This creates the signature smooth, "floaty" acceleration.
	_local_velocity = _local_velocity.lerp(target_velocity, acceleration * delta)

	# --- 4. APPLY MOVEMENT ---
	# Convert the local-space velocity into world-space velocity based on the
	# player's current orientation.
	player.velocity = player.transform.basis * _local_velocity

	# Execute the movement using the character body's built-in function.
	player.move_and_slide()


# This function can be used to transition to another state.
func get_next_state() -> String:
	# Example: Transition to a "walking" state if the player gets near a planet.
	# if player.is_near_planet():
	#     return "PlanetaryMovement"
	return ""
