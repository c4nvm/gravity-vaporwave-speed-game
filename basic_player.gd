#
# PlayerController.gd
#
# This script governs all player-character behaviors, including movement,
# camera orientation, and interactions with planetary gravitational fields.
# It is intended for use with a CharacterBody3D node.
#

extends CharacterBody3D

#region #################### Configuration Properties ####################
# @tool
@export_group("Movement")
const MAX_SLOPE_ANGLE := 40.0
@export var speed := 10.0  # Defines the maximum movement speed of the character.
@export var jump_force := 10.0  # Specifies the initial velocity applied during a jump action.
@export var gravity := 30.0  # Determines the magnitude of the gravitational force.
@export var acceleration := 15.0  # Controls the rate at which the character reaches maximum speed.
@export var deceleration := 20.0  # Controls the rate at which the character comes to a stop.
@export var terminal_velocity := 50.0  # The maximum speed the character can fall.
@export var fall_lerp_weight := 5.0    # How quickly the character reaches terminal velocity.

@export_group("Camera")
@export var mouse_sensitivity := 0.002  # Scales the sensitivity of mouse input for camera control.
@export var max_look_angle := 89.0  # Constrains the vertical look angle of the camera, in degrees.
@export var rotation_smoothness := 30.0  # Modulates the interpolation speed for surface alignment.

#endregion

#region #################### Private Member Variables ####################
# Node references, initialized during the _ready() lifecycle event.
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var push_raycast: RayCast3D = $DirectionRay

# Planetary interaction variables.
var planet: Node3D
var is_on_planet := false  # Flag indicating if the character is within a planet's gravitational influence.
var gravity_direction := Vector3.DOWN  # The current direction of gravity, dynamically updated.

# Character orientation and view variables.
var mouse_rotation := Vector2.ZERO  # Stores the yaw (x) and pitch (y) rotation from mouse input.

# Debugging variables.
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2  # Sets the frequency for logging debug information.
#endregion

#
# Godot Engine Lifecycle Methods
#

func _ready():
	# Establishes a reference to the planetary body in the scene.
	_setup_planet()

	# Configure the mouse input mode for first-person camera control.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Convert the maximum look angle from degrees to radians for internal calculations.
	max_look_angle = deg_to_rad(max_look_angle)

func _input(event):
	# Process mouse movement events for camera rotation.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Update the yaw component based on horizontal mouse movement.
		mouse_rotation.x -= event.relative.x * mouse_sensitivity
		# Normalize yaw to the range [-PI, PI] for rotational consistency.
		mouse_rotation.x = wrapf(mouse_rotation.x, -PI, PI)

		# Update the pitch component based on vertical mouse movement, clamped by max_look_angle.
		mouse_rotation.y = clamp(mouse_rotation.y - event.relative.y * mouse_sensitivity, -max_look_angle, max_look_angle)
		
		# Apply the calculated pitch to the camera pivot's rotation.
		camera_pivot.rotation.x = mouse_rotation.y

func _physics_process(delta):
	# When under planetary influence, apply gravity and surface alignment logic.
	if is_on_planet and planet:
		_update_gravity()
		_apply_gravity(delta)
		_handle_movement(delta)
		_align_with_surface(delta)
		move_and_slide()
	else:
		# In the absence of planetary influence, apply standard free-space physics.
		_handle_movement(delta)
		move_and_slide()
	
	# Periodically output debugging information.
	_update_debug_print(delta)

#
# Internal Logic and Helper Functions
#

# Initializes the planet reference and associated state variables.
func _setup_planet():
	planet = get_parent().find_child("Planet3D", false) if get_parent() else null
	is_on_planet = planet != null
	if is_on_planet:
		# Configure the maximum slope angle for movement on planetary surfaces.
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

# Calculates the direction of gravity based on the character's position relative to the planet.
func _update_gravity():
	gravity_direction = (planet.global_transform.origin - global_transform.origin).normalized()
	up_direction = -gravity_direction

# Applies gravitational force to the character's velocity vector.
func _apply_gravity(delta):
	# This part is fine. It correctly adds gravity when airborne.
	if not is_on_floor():
		velocity += gravity_direction * gravity * delta

# Corrected _handle_movement
func _handle_movement(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	var raycast_forward = -push_raycast.global_transform.basis.z.normalized()
	var raycast_right = push_raycast.global_transform.basis.x.normalized()
	
	if is_on_planet:

		# 1. Store the vertical velocity and remove it from the main velocity.
		var vertical_velocity = velocity.project(up_direction) # up_direction is -gravity_direction
		var horizontal_velocity = velocity - vertical_velocity

		# 2. Calculate the desired horizontal movement.
		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		
		# 3. Lerp ONLY the horizontal velocity towards the target.
		horizontal_velocity = horizontal_velocity.lerp(move_dir * speed, acceleration * delta)

		# 4. Handle the jump. It modifies the vertical velocity.
		if Input.is_action_just_pressed("jump") and is_on_floor():
			vertical_velocity = up_direction * jump_force

		# 5. Recombine the horizontal and vertical components.
		velocity = horizontal_velocity + vertical_velocity
	else:
		# Your free-space logic should also be checked for similar issues.
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity += -transform.basis.y * jump_force * 0.5

# Dynamically aligns the character's orientation with the underlying surface normal.
func _align_with_surface(delta: float):
	if not is_on_planet or not planet:
		return
	
	var new_up = -gravity_direction
	
	# Construct the horizontal rotation from mouse input.
	var horizontal_rot = Basis(new_up, mouse_rotation.x)
	# Construct the tilt rotation from the camera's pitch.
	var tilt_rot = Basis(Vector3.RIGHT, camera_pivot.rotation.x)
	
	# Combine rotations and orthonormalize to mitigate potential scaling artifacts.
	var new_basis = (horizontal_rot * tilt_rot).orthonormalized()
	
	# Re-align the basis to ensure mathematical correctness.
	new_basis.y = new_up.normalized()
	new_basis.x = new_basis.y.cross(new_basis.z).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	
	# Smoothly interpolate the character's transform to the new target basis.
	transform.basis = transform.basis.slerp(new_basis, rotation_smoothness * delta)

# Projects a vector onto a plane defined by a normal, handling potential edge cases.
func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	var projected = vector - vector.project(normal)
	# If the projected vector is near-zero (i.e., view is parallel to the normal),
	# compute a perpendicular vector to prevent returning a zero vector.
	return projected.normalized() if projected.length() > 0.001 else Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()

#
# Debugging Utilities
#

# Manages the periodic printing of debug information.
func _update_debug_print(delta):
	debug_timer += delta
	if debug_timer >= DEBUG_PRINT_INTERVAL:
		debug_timer = 0.0
		_print_input_debug()

# Outputs a formatted string containing the character's state for debugging.
func _print_input_debug():
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	# Construct a formatted string with relevant debugging data.
	var debug_str := "--- Player Debug Information ---\n"
	debug_str += "[Input]\n"
	debug_str += "  Forward: %+.2f\n" % input_dir.y
	debug_str += "  Strafe: %+.2f\n" % input_dir.x
	debug_str += "\n[State]\n"
	debug_str += "  Is Grounded: %s\n" % str(is_on_floor())
	debug_str += "  Velocity: %s (Magnitude: %.2f)\n" % [str(velocity.normalized()), velocity.length()]
	
	if is_on_planet:
		debug_str += "  Gravity Direction: %s\n" % str(gravity_direction.normalized())
	
	debug_str += "  Forward Direction: %s\n" % str(-global_transform.basis.z.normalized())
	debug_str += "--------------------------------\n"
	
	print(debug_str)
