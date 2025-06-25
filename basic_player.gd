# PlayerController.gd
# Governs player behavior including movement, camera control, and gravity interaction
extends CharacterBody3D

#region Configuration
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
@export var mouse_sensitivity := 1.2
@export var max_look_angle := 89.0
@export var gravity_smoothness: float = 5.0

@export_group("Slide")
@export var slide_enabled := true
@export var slide_enter_speed := 8.0
@export var slide_min_speed := 5.0
@export var slide_friction := 0.1
@export var slide_downhill_accel := 1.2
@export var slide_cooldown := 0.5
@export var crouch_camera_offset := Vector3(0, -0.9, 0)  # How much to lower camera when crouching
@export var crouch_transition_speed := 5.0  # How fast camera moves to crouch position

@export_group("Free Space Movement")
@export var free_space_max_speed := 20.0
@export var free_space_acceleration := 5.0
@export var free_space_deceleration := 2.0
@export var free_space_rotation_speed := 2.0
@export var free_space_momentum_gain := 0.95
@export var free_space_mouse_sensitivity := 0.002
@export var free_space_camera_lerp_speed := 10.0
@export var free_space_roll_speed := 1.0
@export var free_space_roll_decay := 0.95

@export_group("Transition")
@export var transition_duration := 0.5
@export var transition_curve : Curve
var transition_timer := 0.0
var transition_start_velocity := Vector3.ZERO
#endregion

#region Nodes
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var direction_ray: RayCast3D = $DirectionRay
@onready var ground_ray: RayCast3D = $GroundRay
@onready var crouch_camera_pivot: Node3D = $CrouchCameraPivot
@onready var standing_camera_pivot: Node3D = $CameraPivot
var current_camera_pivot: Node3D
#endregion

#region State Variables
var gravity_fields: Array[Node] = []
var nearest_gravity_field: Area3D = null
var is_on_planet := false
var gravity_direction := Vector3.DOWN
var mouse_pitch := 0.0
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2
var hook_gravity_override: bool = false
var is_sliding := false
var slide_cooldown_timer := 0.0
var was_sliding := false
var free_space_velocity := Vector3.ZERO
var free_space_rotation := Vector3.ZERO
var free_space_roll := 10.0
var free_space_camera_offset := Vector3.ZERO
var is_free_space_mode := false
var is_transitioning := false
var gravity_field_transition_timer := 0.0
const GRAVITY_FIELD_TRANSITION_COOLDOWN := 0.1
var last_gravity_field = null
var previous_velocity := Vector3.ZERO
var current_camera_offset := Vector3.ZERO
var target_camera_offset := Vector3.ZERO
#endregion

#region Lifecycle Methods
func _ready():
	"""Initialize player controller and setup input"""
	_cache_gravity_fields()
	_enter_planetary_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	max_look_angle = deg_to_rad(max_look_angle)
	
	# Set initial camera pivot
	current_camera_pivot = standing_camera_pivot
	camera.reparent(current_camera_pivot)
	camera.position = Vector3.ZERO
	current_camera_offset = Vector3.ZERO
	target_camera_offset = Vector3.ZERO
	
	var hook_controller = get_node_or_null("HookController")
	if hook_controller:
		hook_controller.gravity_override_changed.connect(_on_hook_gravity_override_changed)

func _input(event):
	"""Handle mouse input for camera rotation"""
	if is_free_space_mode:
		_handle_free_space_input(event)
	else:
		_handle_planetary_input(event)

func _process(delta):
	"""Handle smooth camera transitions"""
	# Smoothly interpolate camera position
	current_camera_offset = current_camera_offset.lerp(
		target_camera_offset, 
		crouch_transition_speed * delta
	)
	
	# Apply the offset to the camera
	camera.position = current_camera_offset

func _physics_process(delta):
	"""Main physics processing loop"""
	_update_transition(delta)
	previous_velocity = velocity
	
	_update_nearest_gravity_field()
	
	if should_switch_modes() and not is_transitioning:
		_switch_movement_mode(nearest_gravity_field == null)
	
	if is_free_space_mode:
		_handle_free_space_movement(delta)
	else:
		_handle_planetary_movement(delta)
	
	move_and_slide()
	_update_debug_print(delta)
#endregion

#region Input Handling
func _handle_free_space_input(event):
	"""Handle free space movement input"""
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		free_space_rotation.x -= event.relative.y * free_space_mouse_sensitivity
		free_space_rotation.y -= event.relative.x * free_space_mouse_sensitivity
		free_space_rotation.x = clamp(free_space_rotation.x, -PI/2, PI/2)
		
		if Input.is_action_pressed("roll_left"):
			free_space_roll += free_space_roll_speed * get_process_delta_time()
		if Input.is_action_pressed("roll_right"):
			free_space_roll -= free_space_roll_speed * get_process_delta_time()

func _handle_planetary_input(event):
	"""Handle planetary movement input"""
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate(transform.basis.y, -event.relative.x * (mouse_sensitivity/1000))
		mouse_pitch = clamp(mouse_pitch - event.relative.y * (mouse_sensitivity/1000), -max_look_angle, max_look_angle)
		current_camera_pivot.rotation.x = mouse_pitch
#endregion

#region Movement Modes
func _handle_planetary_movement(delta):
	"""Handle movement when under planetary gravity with transition preparation"""
	if not Input.is_action_pressed("slide"):
		_end_slide()
	
	_update_gravity()
	_apply_gravity(delta)
	
	# Store pre-movement velocity for transition
	var pre_movement_velocity = velocity
	
	_handle_movement(delta)
	_align_with_surface(delta)
	
	# If we detect we're about to leave gravity, blend the velocity
	if is_on_planet and not direction_ray.is_colliding() and not ground_ray.is_colliding():
		var blend_factor = clamp(
			1.0 - global_position.distance_to(nearest_gravity_field.global_position) / nearest_gravity_field.gravity_radius,
			0.0,
			1.0
		)
		velocity = velocity.lerp(pre_movement_velocity, blend_factor)
	
	if slide_enabled:
		_handle_slide(delta)

func _handle_free_space_movement(delta):
	"""Handle movement in free space (zero gravity)"""
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	
	var move_dir = Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()
	var target_velocity = move_dir * free_space_max_speed
	
	# Only apply normal movement if not being pulled by hook
	var hook_controller = get_node_or_null("HookController")
	var is_hook_pulling = hook_controller and hook_controller.is_hook_active() and hook_controller.current_state == HookController.HookState.ATTACHED
	
	if is_hook_pulling:
		# Get hook pull direction and strength from hook controller
		var hook_pull = hook_controller.get_hook_pull_vector(delta)
		
		# Apply hook pull directly to velocity
		velocity += hook_pull
		
		# Still allow some limited movement while being pulled
		free_space_velocity = free_space_velocity.lerp(target_velocity * 0.3, free_space_acceleration * delta)
	else:
		# Normal free space movement
		free_space_velocity = free_space_velocity.lerp(target_velocity, free_space_acceleration * delta)
		
		if move_dir.length_squared() < 0.1:
			free_space_velocity = free_space_velocity.lerp(Vector3.ZERO, free_space_deceleration * delta)
	
	free_space_velocity *= free_space_momentum_gain
	
	var target_basis = Basis()
	target_basis = target_basis.rotated(Vector3.RIGHT, free_space_rotation.x)
	target_basis = target_basis.rotated(Vector3.UP, free_space_rotation.y)
	target_basis = target_basis.rotated(Vector3.BACK, free_space_roll)
	
	transform.basis = transform.basis.slerp(target_basis, free_space_rotation_speed * delta)
	free_space_roll *= free_space_roll_decay
	
	_update_free_space_camera(input_dir, vertical_input, delta)
	
	# Combine hook pull (if any) with player input
	if is_hook_pulling:
		velocity += transform.basis * free_space_velocity
	else:
		velocity = transform.basis * free_space_velocity

func _switch_movement_mode(free_space: bool):
	"""Transition between planetary and free space movement modes with smoothing"""
	if is_free_space_mode == free_space:
		return
		
	is_transitioning = true
	transition_timer = 0.0
	transition_start_velocity = velocity
	
	# Start transition
	await get_tree().create_timer(transition_duration).timeout
	is_free_space_mode = free_space
	
	if free_space:
		_enter_free_space_mode()
	else:
		_enter_planetary_mode()
	
	is_transitioning = false

func _update_transition(delta):
	"""Handle smooth transition between modes"""
	if not is_transitioning:
		return
		
	transition_timer += delta
	var t = min(transition_timer / transition_duration, 1.0)
	var weight = transition_curve.sample(t) if transition_curve else t
	
	if is_free_space_mode:
		# Transitioning to free space - blend velocity
		var target_velocity = transform.basis * free_space_velocity
		velocity = transition_start_velocity.lerp(target_velocity, weight)
	else:
		# Transitioning to planetary - blend velocity while maintaining up direction
		var up_component = velocity.project(up_direction)
		var horizontal_velocity = velocity - up_component
		velocity = transition_start_velocity.lerp(horizontal_velocity + up_component, weight)
#endregion

#region Gravity Handling
func _cache_gravity_fields():
	"""Find and cache all gravity fields in the scene"""
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.size() > 0:
		nearest_gravity_field = gravity_fields[0]
		is_on_planet = true
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

func _update_nearest_gravity_field():
	"""Determine the nearest/strongest gravity field affecting the player"""
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.is_empty():
		is_on_planet = false
		nearest_gravity_field = null
		last_gravity_field = null  # Clear last field when no fields exist
		return
	
	gravity_field_transition_timer -= get_process_delta_time()
	var candidate_fields = _get_valid_gravity_fields()
	
	if candidate_fields.is_empty():
		is_on_planet = false
		nearest_gravity_field = null
		return
	
	candidate_fields.sort_custom(_sort_gravity_fields)
	var best_candidate = candidate_fields[0].field
	
	if _should_switch_gravity_field(best_candidate):
		last_gravity_field = nearest_gravity_field
		nearest_gravity_field = best_candidate
		gravity_field_transition_timer = GRAVITY_FIELD_TRANSITION_COOLDOWN
		_update_gravity()
	
	# Clear last gravity field if we're not actually transitioning
	if nearest_gravity_field == last_gravity_field:
		last_gravity_field = null
	
	is_on_planet = nearest_gravity_field != null

func _update_gravity():
	"""Update gravity direction based on nearest gravity field"""
	if nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		gravity_direction = (nearest_gravity_field.global_transform.origin - global_transform.origin).normalized() if nearest_gravity_field.gravity_point else nearest_gravity_field.gravity_direction
		self.up_direction = -gravity_direction

func _apply_gravity(delta):
	"""Apply gravity force to player"""
	if is_free_space_mode or nearest_gravity_field == null:
		return
	
	if nearest_gravity_field.is_directional and not nearest_gravity_field.is_body_inside(self):
		_update_nearest_gravity_field()
		return
	
	var gravity_multiplier = 1
	if is_sliding: 
		gravity_multiplier = 1
	elif not _is_going_uphill():
		gravity_multiplier = 1
	elif ground_ray.is_colliding():
		gravity_multiplier = 1
	elif not Input.is_action_just_pressed("jump"):
		gravity_multiplier = 1
	elif not hook_gravity_override:
		gravity_multiplier = 0.0
	else: 
		gravity_multiplier = 3.0
	
	if not is_on_floor():
		velocity += gravity_direction * gravity * gravity_multiplier * delta
#endregion

#region Planetary Movement
func _handle_movement(delta):
	"""Handle standard planetary movement"""
	if is_sliding:
		return
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var raycast_forward = -direction_ray.global_transform.basis.z.normalized()
	var raycast_right = direction_ray.global_transform.basis.x.normalized()
	
	if is_on_planet:
		var vertical_velocity = velocity.project(self.up_direction)
		var horizontal_velocity = velocity - vertical_velocity

		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		
		horizontal_velocity = horizontal_velocity.lerp(move_dir * speed, acceleration * delta)

		if Input.is_action_just_pressed("jump") and (is_on_floor() or ground_ray.is_colliding()):
			vertical_velocity = self.up_direction * jump_force

		velocity = horizontal_velocity + vertical_velocity
	else:
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		if input_dir == Vector2.ZERO:
			velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity += -transform.basis.y * jump_force * 0.5

func _align_with_surface(delta: float):
	"""Align player with planetary surface"""
	if not is_on_planet or not is_instance_valid(nearest_gravity_field):
		return

	var target_up = -gravity_direction.normalized()
	var current_up = transform.basis.y
	var rot = Quaternion(current_up, target_up)

	transform.basis = transform.basis.slerp(Basis(rot) * transform.basis, gravity_smoothness * delta).orthonormalized()

func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	"""Safely project vector onto plane defined by normal"""
	var projected = vector - vector.project(normal)
	return projected.normalized() if projected.length() > 0.001 else Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()
#endregion

#region Slide Mechanics
func _start_slide():
	"""Begin sliding movement"""
	if not slide_enabled or is_sliding or velocity.length() < slide_enter_speed:
		return
	
	is_sliding = true
	slide_cooldown_timer = 0.0
	$StandingCollision.disabled = true
	$SlidingCollision.disabled = false
	
	# Set target camera offset for crouch position
	target_camera_offset = crouch_camera_offset

func _end_slide(force_reset: bool = false):
	"""End sliding movement"""
	if not is_sliding and not force_reset:
		return
	
	is_sliding = false
	$StandingCollision.disabled = false
	$SlidingCollision.disabled = true
	
	# Reset camera offset to standing position
	target_camera_offset = Vector3.ZERO

func _handle_slide(delta):
	"""Handle sliding physics and state"""
	if slide_cooldown_timer < slide_cooldown:
		slide_cooldown_timer += delta
	
	if is_sliding and not Input.is_action_pressed("slide") and is_on_floor() and velocity.length() < slide_min_speed:
		_end_slide()
	
	if (Input.is_action_just_pressed("slide") and is_on_floor() 
		and velocity.length() >= slide_enter_speed and slide_cooldown_timer >= slide_cooldown):
		_start_slide()
	
	if is_sliding:
		_apply_slide_physics(delta)

func _is_going_uphill() -> bool:
	"""Check if player is sliding uphill"""
	return is_on_floor() and is_sliding and -get_floor_normal().slide(gravity_direction).normalized().dot(velocity.normalized()) > 0.1

func _apply_slide_physics(delta):
	"""Apply physics during sliding"""
	var slope_normal = get_floor_normal()
	if slope_normal != Vector3.ZERO and gravity_direction != Vector3.ZERO:
		var slope_dir = -slope_normal.slide(gravity_direction)
		
		if slope_dir.length() > 0.01:
			slope_dir = slope_dir.normalized()
			var horizontal_vel = velocity.slide(gravity_direction)
			var vertical_vel = velocity.project(gravity_direction)
			
			if slope_dir.dot(horizontal_vel.normalized()) > 0.1: # Moving uphill
				horizontal_vel = horizontal_vel.lerp(Vector3.ZERO, slide_friction * delta)
			else:
				horizontal_vel += slope_dir * slide_downhill_accel * delta
			
			velocity = horizontal_vel + vertical_vel
#endregion

#region Helper Functions
func should_switch_modes() -> bool:
	"""Determine if we should switch between movement modes"""
	return (nearest_gravity_field == null) != is_free_space_mode

func _enter_free_space_mode():
	"""Initialize free space mode with momentum preservation"""
	# Preserve the exact velocity from planetary mode, just convert to world space
	free_space_velocity = previous_velocity
	
	# Convert the velocity direction to be relative to the player's new orientation
	var speed = previous_velocity.length()
	if speed > 0:
		var local_dir = transform.basis.inverse() * previous_velocity.normalized()
		free_space_velocity = local_dir * speed
	
	# Smooth rotation transition
	free_space_rotation = Vector3(camera_pivot.rotation.x, rotation.y, 0)
	free_space_roll = 0
	free_space_camera_offset = Vector3.ZERO
	is_sliding = false
	camera_pivot.rotation.z = 0.0

func _enter_planetary_mode():
	"""Initialize planetary mode"""
	camera.position = Vector3.ZERO
	free_space_camera_offset = Vector3.ZERO
	mouse_pitch = camera_pivot.rotation.x
	free_space_rotation = Vector3.ZERO
	free_space_roll = 0.0
	free_space_velocity = Vector3.ZERO

func _update_free_space_camera(input_dir: Vector2, vertical_input: float, delta: float):
	"""Update camera position in free space mode"""
	var camera_target_position = Vector3.ZERO
	if abs(vertical_input) > 0.1:
		camera_target_position.y = vertical_input * 0.5
	if abs(input_dir.x) > 0.1:
		camera_target_position.x = input_dir.x * 0.5
	if abs(input_dir.y) > 0.1:
		camera_target_position.z = input_dir.y * 0.3
	
	free_space_camera_offset = free_space_camera_offset.lerp(camera_target_position, free_space_camera_lerp_speed * delta)
	camera.position = free_space_camera_offset

func _get_valid_gravity_fields() -> Array:
	"""Get array of valid gravity fields affecting player"""
	var candidate_fields := []
	var current_priority = nearest_gravity_field.priority if nearest_gravity_field else -1
	
	for field in gravity_fields:
		if not is_instance_valid(field):
			continue
			
		var should_consider = field.is_body_inside(self) if field.is_directional else true
		
		if should_consider:
			candidate_fields.append({
				"field": field,
				"priority": field.priority,
				"strength": field.gravity_strength,
				"distance": global_position.distance_to(field.global_position),
				"is_new": field != nearest_gravity_field
			})
	
	return candidate_fields

func _sort_gravity_fields(a, b) -> bool:
	"""Custom sort function for gravity fields"""
	if a.priority != b.priority:
		return a.priority > b.priority
		
	var a_dot = a.field.global_position.direction_to(global_position).dot(velocity.normalized())
	var b_dot = b.field.global_position.direction_to(global_position).dot(velocity.normalized())
	if abs(a_dot - b_dot) > 0.1:
		return a_dot < b_dot
	elif a.is_new != b.is_new:
		return a.is_new
	elif a.field.is_directional != b.field.is_directional:
		return a.field.is_directional
	else:
		return a.strength > b.strength if a.field.is_directional else a.distance < b.distance

func _should_switch_gravity_field(new_field) -> bool:
	"""Determine if we should switch to a new gravity field"""
	# If we're not currently in any field, accept any valid new field
	if nearest_gravity_field == null:
		return true
		
	# If the new field has higher priority, always switch
	if new_field.priority > nearest_gravity_field.priority:
		return true
		
	return (gravity_field_transition_timer <= 0 and 
			(new_field != nearest_gravity_field or 
			 not nearest_gravity_field.is_body_inside(self)))

func _on_hook_gravity_override_changed(should_override: bool):
	"""Handle hook gravity override changes"""
	hook_gravity_override = should_override

func _update_debug_print(delta):
	"""Update debug information display"""
	debug_timer += delta
	if debug_timer >= DEBUG_PRINT_INTERVAL:
		debug_timer = 0.0
		_print_input_debug()

func _print_input_debug():
	"""Print debug information to console"""
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
#endregion
