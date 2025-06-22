#region
# PlayerController.gd
#
# By c4nvm / Nathaniel Denzler
#
# Governs player behavior, including movement, camera control, and interaction
# with planetary gravity. Designed for a CharacterBody3D node.
#endregion

extends CharacterBody3D

#region #################### Configuration Properties ####################
@export_group("Movement")
const MAX_SLOPE_ANGLE := 40.0
@export var speed := 10.0
@export var jump_force := 10.0
@export var gravity := 30.0
@export var acceleration := 15.0
@export var deceleration := 20.0
@export var terminal_velocity := 50.0
@export var fall_lerp_weight := 5.0

@export_group("Camera")
@export var mouse_sensitivity := 0.002
@export var max_look_angle := 89.0 # Vertical look limit, in degrees.
@export var gravity_smoothness: float = 5.0 # How quickly the player aligns to a new gravity vector.

#endregion

#region #################### Private Member Variables ####################
# Node references, assigned in _ready().
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var direction_ray: RayCast3D = $DirectionRay
@onready var ground_ray: RayCast3D = $GroundRay

# Planetary interaction variables.
var gravity_fields: Array[Node] = []
var nearest_gravity_field: Area3D = null
var is_on_planet := false
var gravity_direction := Vector3.DOWN # Current direction of gravity.

# Stores vertical camera rotation from mouse input.
var mouse_pitch := 0.0

# Debugging variables.
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2

var just_jumped := false
var jump_cooldown := 0.2
var jump_timer := 0.0

#endregion

#
# Godot Engine Lifecycle Methods
#

func _ready():
	_cache_gravity_fields()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Convert angle to radians for internal calculations.
	max_look_angle = deg_to_rad(max_look_angle)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Horizontal rotation (yaw) is applied to the entire CharacterBody.
		rotate(transform.basis.y, -event.relative.x * mouse_sensitivity)

		# Vertical rotation (pitch) is applied only to the camera pivot,
		# and is clamped to prevent looking straight up or down.
		mouse_pitch = clamp(mouse_pitch - event.relative.y * mouse_sensitivity, -max_look_angle, max_look_angle)
		camera_pivot.rotation.x = mouse_pitch

func _physics_process(delta):
	_update_nearest_gravity_field()
	
	if is_on_planet and nearest_gravity_field:
		# Planetary physics: custom gravity and surface alignment.
		_update_gravity()
		_apply_gravity(delta)
		_handle_movement(delta)
		_align_with_surface(delta)
		move_and_slide()
	else:
		# Standard free-space physics.
		_handle_movement(delta)
		move_and_slide()
	
	_update_debug_print(delta)

#
# Internal Logic and Helper Functions
#

# Finds and stores all nodes in the "gravity_fields" group.
func _cache_gravity_fields():
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.size() > 0:
		nearest_gravity_field = gravity_fields[0]
		is_on_planet = true
		# Set the CharacterBody3D's slope handling for planetary surfaces.
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

# Iterates through cached fields to find the one with the strongest influence.
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

# Sets gravity based on the nearest field's properties. Supports both
# point gravity (for planets) and directional gravity.
func _update_gravity():
	if nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		if nearest_gravity_field.gravity_point == true:
			# Point Gravity: Pulls towards the center of the field.
			gravity_direction = (nearest_gravity_field.global_transform.origin - global_transform.origin).normalized()
		else:
			# Directional Gravity: Pulls in a fixed direction.
			gravity_direction = nearest_gravity_field.gravity_direction

		self.up_direction = -gravity_direction


func _apply_gravity(delta):
	var gravity_multiplier = 1.0
	
	# Apply stronger gravity to help stick to surfaces when grounded.
	if ground_ray.is_colliding() and not Input.is_action_just_pressed("jump"):
		gravity_multiplier = 2.0
	
	if not is_on_floor():
		velocity += gravity_direction * gravity * gravity_multiplier * delta

func _handle_movement(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	# Use the camera's basis for movement direction.
	var raycast_forward = -direction_ray.global_transform.basis.z.normalized()
	var raycast_right = direction_ray.global_transform.basis.x.normalized()
	
	if is_on_planet:
		# 1. Isolate vertical velocity (along the gravity vector).
		var vertical_velocity = velocity.project(self.up_direction)
		var horizontal_velocity = velocity - vertical_velocity

		# 2. Project movement input onto the plane perpendicular to gravity.
		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		
		# 3. Accelerate horizontal velocity based on input.
		horizontal_velocity = horizontal_velocity.lerp(move_dir * speed, acceleration * delta)

		# 4. Apply jump impulse to vertical velocity.
		if Input.is_action_just_pressed("jump"):
			if is_on_floor() or ground_ray.is_colliding():
				vertical_velocity = self.up_direction * jump_force

		# 5. Recombine velocities.
		velocity = horizontal_velocity + vertical_velocity
	else:
		# Handle free-space movement.
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		if input_dir != Vector2.ZERO:
			velocity += move_dir * acceleration * delta
		else:
			velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity += -transform.basis.y * jump_force * 0.5

# Smoothly aligns the player's orientation with the current gravity direction.
# This uses a quaternion to find the shortest rotation from the current 'up'
# to the target 'up', preserving the player's forward direction (yaw).
func _align_with_surface(delta: float):
	if not is_on_planet or not is_instance_valid(nearest_gravity_field):
		return

	var target_up = -gravity_direction.normalized()
	var current_up = transform.basis.y
	var rot = Quaternion(current_up, target_up)

	transform.basis = transform.basis.slerp(Basis(rot) * transform.basis, gravity_smoothness * delta)

# Projects a vector onto a plane defined by a normal.
func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	var projected = vector - vector.project(normal)
	# If the input vector is parallel to the normal, the projection is a zero vector.
	# To prevent this, we calculate an arbitrary perpendicular vector as a fallback.
	return projected.normalized() if projected.length() > 0.001 else Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()

#
# Debugging Utilities
#

func _update_debug_print(delta):
	debug_timer += delta
	if debug_timer >= DEBUG_PRINT_INTERVAL:
		debug_timer = 0.0
		_print_input_debug()

func _print_input_debug():
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
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
