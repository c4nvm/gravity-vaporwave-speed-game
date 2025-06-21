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
@export var gravity_smoothness: float = 5.0
@export var look_smoothness: float = 30.0

#endregion

#region #################### Private Member Variables ####################
# Node references, initialized during the _ready() lifecycle event.
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var direction_ray: RayCast3D = $DirectionRay
@onready var ground_ray: RayCast3D = $GroundRay

# Planetary interaction variables.
var gravity_fields: Array[Node] = []  # Array to cache all gravity field areas
var nearest_gravity_field: Area3D = null  # The currently active gravity field
var is_on_planet := false  # Flag indicating if the character is within a planet's gravitational influence.
var gravity_direction := Vector3.DOWN  # The current direction of gravity, dynamically updated.

# Character orientation and view variables.
var mouse_rotation := Vector2.ZERO  # Stores the yaw (x) and pitch (y) rotation from mouse input.

# Debugging variables.
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2  # Sets the frequency for logging debug information.

var just_jumped := false
var jump_cooldown := 0.2  # Time in seconds after jumping where gravity isn't multiplied
var jump_timer := 0.0

#endregion

#
# Godot Engine Lifecycle Methods
#

func _ready():
	# Cache all gravity field areas in the scene
	_cache_gravity_fields()
	
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
	# Find the nearest gravity field
	_update_nearest_gravity_field()
	
	# When under planetary influence, apply gravity and surface alignment logic.
	if is_on_planet and nearest_gravity_field:
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

# Caches all gravity field areas in the scene that belong to the "gravity_fields" group
func _cache_gravity_fields():
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.size() > 0:
		nearest_gravity_field = gravity_fields[0]
		is_on_planet = true
		# Configure the maximum slope angle for movement on planetary surfaces.
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

# Finds the nearest gravity field from the cached array
func _update_nearest_gravity_field():
	if gravity_fields.is_empty():
		is_on_planet = false
		return
	
	var nearest_distance := INF
	var new_nearest: Area3D = null
	
	for field in gravity_fields:
		if not is_instance_valid(field):
			continue
			
		var distance = global_position.distance_squared_to(field.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			new_nearest = field
	
	if new_nearest != nearest_gravity_field:
		nearest_gravity_field = new_nearest
		is_on_planet = nearest_gravity_field != null

# Calculates the direction of gravity based on the character's position relative to the nearest gravity field
func _update_gravity():
	if nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		gravity_direction = (nearest_gravity_field.global_transform.origin - global_transform.origin).normalized()
		self.up_direction = -gravity_direction

func _apply_gravity(delta):
	var gravity_multiplier = 1.0  # Default gravity strength
	
	# Check if we should apply stronger gravity
	if ground_ray.is_colliding() and not Input.is_action_just_pressed("jump"):
		gravity_multiplier = 2.0  # Example: 2x gravity when grounded (not jumping)
	
	# Always apply gravity (with possible multiplier)
	if not is_on_floor():
		velocity += gravity_direction * gravity * gravity_multiplier * delta

# Corrected _handle_movement
func _handle_movement(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	var raycast_forward = -direction_ray.global_transform.basis.z.normalized()
	var raycast_right = direction_ray.global_transform.basis.x.normalized()
	
	if is_on_planet:
		# 1. Store the vertical velocity and remove it from the main velocity.
		var vertical_velocity = velocity.project(self.up_direction) # up_direction is -gravity_direction
		var horizontal_velocity = velocity - vertical_velocity

		# 2. Calculate the desired horizontal movement.
		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		
		# 3. Lerp ONLY the horizontal velocity towards the target.
		horizontal_velocity = horizontal_velocity.lerp(move_dir * speed, acceleration * delta)

		# 4. Handle the jump. It modifies the vertical velocity.
		if Input.is_action_just_pressed("jump"):
			if is_on_floor() or ground_ray.is_colliding():
				vertical_velocity = self.up_direction * jump_force

		# 5. Recombine the horizontal and vertical components.
		velocity = horizontal_velocity + vertical_velocity
	else:
		# Your free-space logic should also be checked for similar issues.
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		if input_dir != Vector2.ZERO:
			velocity += move_dir * acceleration * delta
		else:
			velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity += -transform.basis.y * jump_force * 0.5

# Dynamically aligns the character's orientation with the underlying surface normal.
# Add these as exported variables to your script to adjust them in the editor

func _align_with_surface(delta: float):
	if not is_on_planet or not nearest_gravity_field or not is_instance_valid(nearest_gravity_field):
		return

	var target_up = -gravity_direction.normalized()

	var smoothed_up = transform.basis.y.slerp(target_up, gravity_smoothness * delta)

	var horizontal_rot = Basis(target_up, mouse_rotation.x)
	var tilt_rot = Basis(Vector3.RIGHT, camera_pivot.rotation.x)
	var desired_look_basis = (horizontal_rot * tilt_rot).orthonormalized()

	var final_target_basis = Basis()

	final_target_basis.y = smoothed_up

	final_target_basis.z = desired_look_basis.z
	
	# Re-align the basis to ensure it's a valid and orthogonal rotation,
	# preserving the new 'up' and 'forward' vectors.
	final_target_basis.x = final_target_basis.y.cross(final_target_basis.z).normalized()
	final_target_basis.z = final_target_basis.x.cross(final_target_basis.y).normalized()

	transform.basis = transform.basis.slerp(final_target_basis, 50 * delta)

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
	
	if is_on_planet and nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		debug_str += "  Current Gravity Field: %s\n" % nearest_gravity_field.name
		debug_str += "  Gravity Direction: %s\n" % str(gravity_direction.normalized())
	
	debug_str += "  Forward Direction: %s\n" % str(-global_transform.basis.z.normalized())
	debug_str += "  Total Gravity Fields: %d\n" % gravity_fields.size()
	debug_str += "--------------------------------\n"
	
	print(debug_str)
