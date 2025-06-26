# Complete player controller with movement, gravity, sliding, step climbing, instant vault-boosting, and ledge climbing
extends CharacterBody3D

#region Configuration
@export_group("Movement")
const MAX_SLOPE_ANGLE := 40.0
@export var speed := 10.0
@export var jump_force := 10.0
@export var gravity := 30.0
@export var acceleration := 15.0
@export var deceleration := 20.0
@export var air_acceleration := 2.0 # How quickly you can change direction in the air. Lower is less control.
@export var air_deceleration := 0.4 # How quickly you slow down in the air. Lower is less friction.
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
@export var slide_cooldown := 0.1
@export var crouch_camera_offset := Vector3(0, -0.9, 0)
@export var crouch_transition_speed := 5.0

@export_group("Advanced Movement")
@export var slide_hop_boost := 1.2 # Multiplier for speed boost when jumping out of a slide.
@export var slide_hop_jump_multiplier := 0.7 # Multiplier for jump force when slide hopping.
@export var high_speed_decel_multiplier := 0.2 # How much to reduce deceleration when moving faster than base speed. Lower is less friction.

@export_group("Vaulting")
@export var vault_enabled := true
@export var vault_min_height_from_feet := 0.8
@export var vault_max_height_from_feet := 1.8
@export var vault_forward_check_distance := 0.5
@export var vault_boost_vertical_force := 10.0
@export var vault_boost_horizontal_force := 6.0
@export var vault_cooldown := 0.3
@export var vault_min_downward_speed := 2.0

@export_group("Ledge Climb")
@export var ledge_climb_enabled := true
@export var ledge_climb_duration := 0.5
@export var ledge_climb_cooldown := 0.5
@export var ledge_climb_min_upward_speed := -1.0

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

@export_group("Stair Climbing")
@export var max_step_up := 0.5
@export var max_step_down := 0.5
@export var step_up_debug := false
@export var step_down_debug := false
#endregion

#region Nodes
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var direction_ray: RayCast3D = $DirectionRay
@onready var ground_ray: RayCast3D = $GroundRay
@onready var crouch_camera_pivot: Node3D = $CrouchCameraPivot
@onready var standing_camera_pivot: Node3D = $CameraPivot
@onready var player_collider: CollisionShape3D = $StandingCollision
@onready var ledge_detector_ray: RayCast3D = $LedgeDetectorRay

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
var gravity_field_transition_timer := 0.1
const GRAVITY_FIELD_TRANSITION_COOLDOWN := 0.1
var last_gravity_field = null
var previous_velocity := Vector3.ZERO
var current_camera_offset := Vector3.ZERO
var target_camera_offset := Vector3.ZERO
var is_grounded := true
var was_grounded := true
var wish_dir := Vector3.ZERO
const vertical := Vector3(0, 1, 0)
const horizontal := Vector3(1, 0, 1)

var vault_cooldown_timer := 0.0
var is_climbing := false
var ledge_climb_cooldown_timer := 0.0
#endregion

func _ready():
	_cache_gravity_fields()
	_enter_planetary_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	max_look_angle = deg_to_rad(max_look_angle)
	current_camera_pivot = standing_camera_pivot
	camera.reparent(current_camera_pivot)
	camera.position = Vector3.ZERO
	current_camera_offset = Vector3.ZERO
	target_camera_offset = Vector3.ZERO
	var hook_controller = get_node_or_null("HookController")
	if hook_controller:
		hook_controller.gravity_override_changed.connect(_on_hook_gravity_override_changed)

func _input(event):
	if is_climbing: return

	if is_free_space_mode:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			free_space_rotation.x -= event.relative.y * free_space_mouse_sensitivity
			free_space_rotation.y -= event.relative.x * free_space_mouse_sensitivity
			free_space_rotation.x = clamp(free_space_rotation.x, -PI/2, PI/2)

			if Input.is_action_pressed("roll_left"):
				free_space_roll += free_space_roll_speed * get_process_delta_time()
			if Input.is_action_pressed("roll_right"):
				free_space_roll -= free_space_roll_speed * get_process_delta_time()
	else:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			rotate(transform.basis.y, -event.relative.x * (mouse_sensitivity/1000))
			mouse_pitch = clamp(mouse_pitch - event.relative.y * (mouse_sensitivity/1000), -max_look_angle, max_look_angle)
			current_camera_pivot.rotation.x = mouse_pitch

func _process(delta):
	current_camera_offset = current_camera_offset.lerp(
		target_camera_offset,
		crouch_transition_speed * delta
	)
	camera.position = current_camera_offset

func _physics_process(delta):
	if is_climbing:
		return

	_pre_physics_process()
	_update_transition(delta)
	previous_velocity = velocity
	_update_nearest_gravity_field()
	
	if vault_cooldown_timer > 0:
		vault_cooldown_timer -= delta
	if ledge_climb_cooldown_timer > 0:
		ledge_climb_cooldown_timer -= delta

	if should_switch_modes() and not is_transitioning:
		_switch_movement_mode(nearest_gravity_field == null)

	if is_free_space_mode:
		_handle_free_space_movement(delta)
	else:
		_handle_planetary_movement(delta)

	wish_dir = Vector3(velocity.x, 0, velocity.z).normalized()

	if not is_free_space_mode:
		_stair_step_up()

	move_and_slide()

	_handle_vaulting()
	_handle_ledge_climb()

	if not is_free_space_mode:
		_stair_step_down()

	_update_debug_print(delta)

func _pre_physics_process():
	if player_collider:
		player_collider.global_rotation = Vector3.ZERO

	was_grounded = is_grounded
	is_grounded = is_on_floor()

func _handle_free_space_movement(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	
	var move_dir = Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()
	var target_velocity = move_dir * free_space_max_speed
	
	var hook_controller = get_node_or_null("HookController")
	var is_hook_pulling = hook_controller and hook_controller.is_hook_active() and hook_controller.current_state == HookController.HookState.ATTACHED
	
	if is_hook_pulling:
		var hook_pull = hook_controller.get_hook_pull_vector(delta)
		velocity += hook_pull
		free_space_velocity = free_space_velocity.lerp(target_velocity * 0.3, free_space_acceleration * delta)
	else:
		free_space_velocity = free_space_velocity.lerp(target_velocity, free_space_acceleration * delta)
		if move_dir.length_squared() < 0.1:
			free_space_velocity = free_space_velocity.lerp(Vector3.ZERO, free_space_deceleration * delta)
	
	free_space_velocity *= free_space_momentum_gain
	
	var target_basis = Basis()
	target_basis = target_basis.rotated(Vector3.RIGHT, free_space_rotation.x)
	target_basis = target_basis.rotated(Vector3.UP, free_space_rotation.y)
	target_basis = target_basis.rotated(Vector3.BACK, free_space_roll)
	
	transform.basis = transform.basis.slerp(target_basis, free_space_rotation_speed * delta).orthonormalized()
	free_space_roll *= free_space_roll_decay
	
	_update_free_space_camera(input_dir, vertical_input, delta)
	
	if is_hook_pulling:
		velocity += transform.basis * free_space_velocity
	else:
		velocity = transform.basis * free_space_velocity

func _handle_planetary_movement(delta):
	if not Input.is_action_pressed("slide"):
		_end_slide()

	_update_gravity()
	_apply_gravity(delta)

	var pre_movement_velocity = velocity

	_handle_movement(delta)
	_align_with_surface(delta)

	if is_on_planet and not direction_ray.is_colliding() and not ground_ray.is_colliding():
		var blend_factor = clamp(
			1.0 - global_position.distance_to(nearest_gravity_field.global_position) / nearest_gravity_field.gravity_radius,
			0.0,
			1.0
		)
		velocity = velocity.lerp(pre_movement_velocity, blend_factor)

	if slide_enabled:
		_handle_slide(delta)

# MODIFIED: This function now handles air control separately from ground control.
func _handle_movement(delta):
	if is_sliding:
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var raycast_forward = -direction_ray.global_transform.basis.z.normalized()
	var raycast_right = direction_ray.global_transform.basis.x.normalized()

	if is_on_planet:
		var vertical_velocity = velocity.project(self.up_direction)
		var horizontal_velocity = velocity - vertical_velocity

		# Project wish direction onto plane defined by gravity
		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		var wish_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		
		var target_h_velocity = wish_dir * speed

		var current_accel: float
		var current_decel: float

		# Select acceleration/deceleration values based on whether we are on the ground or in the air
		if is_on_floor():
			current_accel = acceleration
			current_decel = deceleration
			
			# Apply high-speed friction reduction only when on the ground and not providing input
			var current_h_speed = horizontal_velocity.length()
			if current_h_speed > speed and input_dir == Vector2.ZERO:
				current_decel *= high_speed_decel_multiplier
		else: # In the air
			current_accel = air_acceleration
			current_decel = air_deceleration

		# Apply acceleration or deceleration
		if input_dir.length() > 0.01:
			# Player is providing input, accelerate towards target velocity
			horizontal_velocity = horizontal_velocity.lerp(target_h_velocity, current_accel * delta)
		else:
			# Player is not providing input, decelerate to a stop
			horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, current_decel * delta)

		if Input.is_action_just_pressed("jump") and (is_on_floor() or ground_ray.is_colliding()):
			vertical_velocity = self.up_direction * jump_force

		velocity = horizontal_velocity + vertical_velocity
	else:
		# This logic is for the old free-space mode, kept as is
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		if input_dir == Vector2.ZERO:
			velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity += -transform.basis.y * jump_force * 0.5

func _align_with_surface(delta: float):
	if not is_on_planet or not is_instance_valid(nearest_gravity_field):
		return

	var target_up = -gravity_direction.normalized()
	var current_up = transform.basis.y
	var rot = Quaternion(current_up, target_up)

	transform.basis = transform.basis.slerp(Basis(rot) * transform.basis, gravity_smoothness * delta).orthonormalized()

func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	var projected = vector - vector.project(normal)
	return projected.normalized() if projected.length() > 0.001 else Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()

func _start_slide():
	if not $SlideRay.is_colliding():
		return
	
	is_sliding = true
	slide_cooldown_timer = 0.0
	$StandingCollision.disabled = true
	$SlidingCollision.disabled = false
	target_camera_offset = crouch_camera_offset

func _end_slide(force_reset: bool = false):
	if not is_sliding and not force_reset:
		return
	
	was_sliding = is_sliding # Keep track that we were just sliding
	is_sliding = false
	$StandingCollision.disabled = false
	$SlidingCollision.disabled = true
	target_camera_offset = Vector3.ZERO

func _handle_slide(delta):
	if slide_cooldown_timer < slide_cooldown:
		slide_cooldown_timer += delta
	
	# Check for jump to initiate a slide hop
	if is_sliding and Input.is_action_just_pressed("jump") and (is_on_floor() or ground_ray.is_colliding()):
		_perform_slide_hop()
		return # We've jumped, no more slide logic this frame.

	if is_sliding and not Input.is_action_pressed("slide"):
		_end_slide()
	
	if (Input.is_action_just_pressed("slide") and $SlideRay.is_colliding()
		and velocity.length() >= slide_enter_speed and slide_cooldown_timer >= slide_cooldown):
		_start_slide()
	
	if is_sliding:
		_apply_slide_physics(delta)

# MODIFIED: Logic for performing a slide hop
func _perform_slide_hop():
	var horizontal_velocity = velocity - velocity.project(self.up_direction)
	
	# Apply speed boost
	horizontal_velocity *= slide_hop_boost
	
	# Apply vertical jump force (modified by multiplier)
	var vertical_velocity = self.up_direction * (jump_force * slide_hop_jump_multiplier)
	
	# Combine and set the new velocity
	velocity = horizontal_velocity + vertical_velocity
	
	# Exit the sliding state
	_end_slide()


func _apply_slide_physics(delta):
	var slope_normal = get_floor_normal()
	if slope_normal != Vector3.ZERO and gravity_direction != Vector3.ZERO:
		var slope_dir = -slope_normal.slide(gravity_direction)
		
		if slope_dir.length() > 0.01:
			slope_dir = slope_dir.normalized()
			var horizontal_vel = velocity.slide(gravity_direction)
			var vertical_vel = velocity.project(gravity_direction)
			
			if slope_dir.dot(horizontal_vel.normalized()) > 0.1:
				horizontal_vel = horizontal_vel.lerp(Vector3.ZERO, slide_friction * delta)
			else:
				horizontal_vel += slope_dir * slide_downhill_accel * delta
			
			velocity = horizontal_vel + vertical_vel

func _update_free_space_camera(input_dir: Vector2, vertical_input: float, delta: float):
	var camera_target_position = Vector3.ZERO
	if abs(vertical_input) > 0.1:
		camera_target_position.y = vertical_input * 0.5
	if abs(input_dir.x) > 0.1:
		camera_target_position.x = input_dir.x * 0.5
	if abs(input_dir.y) > 0.1:
		camera_target_position.z = input_dir.y * 0.3
	
	free_space_camera_offset = free_space_camera_offset.lerp(camera_target_position, free_space_camera_lerp_speed * delta)
	camera.position = free_space_camera_offset

func _switch_movement_mode(free_space: bool):
	if is_free_space_mode == free_space:
		return
		
	is_transitioning = true
	transition_timer = 0.0
	transition_start_velocity = velocity
	
	await get_tree().create_timer(transition_duration).timeout
	is_free_space_mode = free_space
	
	if free_space:
		_enter_free_space_mode()
	else:
		_enter_planetary_mode()
	
	is_transitioning = false

func _enter_free_space_mode():
	free_space_velocity = previous_velocity
	var speed = previous_velocity.length()
	if speed > 0:
		var local_dir = transform.basis.inverse() * previous_velocity.normalized()
		free_space_velocity = local_dir * speed
	
	free_space_rotation = Vector3(camera_pivot.rotation.x, rotation.y, 0)
	free_space_roll = 0
	free_space_camera_offset = Vector3.ZERO
	is_sliding = false
	camera_pivot.rotation.z = 0.0

func _enter_planetary_mode():
	camera.position = Vector3.ZERO
	free_space_camera_offset = Vector3.ZERO
	mouse_pitch = camera_pivot.rotation.x
	free_space_rotation = Vector3.ZERO
	free_space_roll = 0.0
	free_space_velocity = Vector3.ZERO

func _update_transition(delta):
	if not is_transitioning:
		return
		
	transition_timer += delta
	var t = min(transition_timer / transition_duration, 1.0)
	var weight = transition_curve.sample(t) if transition_curve else t
	
	if is_free_space_mode:
		var target_velocity = transform.basis * free_space_velocity
		velocity = transition_start_velocity.lerp(target_velocity, weight)
	else:
		var up_component = velocity.project(up_direction)
		var horizontal_velocity = velocity - up_component
		velocity = transition_start_velocity.lerp(horizontal_velocity + up_component, weight)

func _cache_gravity_fields():
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.size() > 0:
		nearest_gravity_field = gravity_fields[0]
		is_on_planet = true
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

func _update_nearest_gravity_field():
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.is_empty():
		is_on_planet = false
		nearest_gravity_field = null
		last_gravity_field = null
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
	
	if nearest_gravity_field == last_gravity_field:
		last_gravity_field = null
	
	is_on_planet = nearest_gravity_field != null

func _get_valid_gravity_fields() -> Array:
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
	if nearest_gravity_field == null:
		return true
		
	if new_field.priority > nearest_gravity_field.priority:
		return true
		
	return (gravity_field_transition_timer <= 0 and
			(new_field != nearest_gravity_field or
				not nearest_gravity_field.is_body_inside(self)))

func _update_gravity():
	if nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		gravity_direction = (nearest_gravity_field.global_transform.origin - global_transform.origin).normalized() if nearest_gravity_field.gravity_point else nearest_gravity_field.gravity_direction
		self.up_direction = -gravity_direction

func _apply_gravity(delta):
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

func _is_going_uphill() -> bool:
	return is_on_floor() and is_sliding and -get_floor_normal().slide(gravity_direction).normalized().dot(velocity.normalized()) > 0.1

func should_switch_modes() -> bool:
	return (nearest_gravity_field == null) != is_free_space_mode

func _on_hook_gravity_override_changed(should_override: bool):
	hook_gravity_override = should_override

func _update_debug_print(delta):
	debug_timer += delta
	if debug_timer >= DEBUG_PRINT_INTERVAL:
		debug_timer = 0.0

func _stair_step_down():
	if is_free_space_mode or not is_grounded:
		return

	if velocity.y <= 0 and was_grounded:
		var body_test_result = PhysicsTestMotionResult3D.new()
		var body_test_params = PhysicsTestMotionParameters3D.new()
		body_test_params.from = self.global_transform
		body_test_params.motion = Vector3(0, -max_step_down, 0)
		if PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
			position.y += body_test_result.get_travel().y
			apply_floor_snap()
			is_grounded = true

func _stair_step_up():
	if is_free_space_mode or wish_dir == Vector3.ZERO or velocity.y > 0:
		return

	var body_test_params = PhysicsTestMotionParameters3D.new()
	var body_test_result = PhysicsTestMotionResult3D.new()
	var test_transform = global_transform
	var distance = wish_dir * 0.1
	body_test_params.from = self.global_transform
	body_test_params.motion = distance
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		return
	var remainder = body_test_result.get_remainder()
	test_transform = test_transform.translated(body_test_result.get_travel())
	var step_up = max_step_up * vertical
	body_test_params.from = test_transform
	body_test_params.motion = step_up
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())
	body_test_params.from = test_transform
	body_test_params.motion = remainder
	PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
	test_transform = test_transform.translated(body_test_result.get_travel())
	if body_test_result.get_collision_count() != 0:
		remainder = body_test_result.get_remainder().length()
		var wall_normal = body_test_result.get_collision_normal()
		var dot_div_mag = wish_dir.dot(wall_normal) / (wall_normal * wall_normal).length()
		var projected_vector = (wish_dir - dot_div_mag * wall_normal).normalized()
		body_test_params.from = test_transform
		body_test_params.motion = remainder * projected_vector
		PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result)
		test_transform = test_transform.translated(body_test_result.get_travel())
	body_test_params.from = test_transform
	body_test_params.motion = max_step_up * -vertical
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result):
		return
	test_transform = test_transform.translated(body_test_result.get_travel())
	var surface_normal = body_test_result.get_collision_normal()
	if (snappedf(surface_normal.angle_to(vertical), 0.001) > deg_to_rad(MAX_SLOPE_ANGLE)):
		return
	var global_pos = global_position
	var step_up_dist = test_transform.origin.y - global_pos.y
	velocity.y = 0
	global_pos.y = test_transform.origin.y
	global_position = global_pos

func _handle_vaulting():
	if not vault_enabled or is_on_floor() or vault_cooldown_timer > 0:
		return

	# Allow vaulting when either moving forward OR falling fast enough
	var forward_velocity_component = velocity.dot(-transform.basis.z)
	var downward_velocity = velocity.dot(gravity_direction)
	if forward_velocity_component < 1.0 and downward_velocity < vault_min_downward_speed:
		return

	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		if collision:
			var angle_with_gravity = collision.get_normal().angle_to(-gravity_direction)
			if rad_to_deg(angle_with_gravity) > 80:
				if _check_and_perform_vault(collision):
					break

func _check_and_perform_vault(collision: KinematicCollision3D) -> bool:
	var world_space = get_world_3d().direct_space_state
	var wall_normal = collision.get_normal()
	var player_center = global_position
	var player_height = player_collider.shape.height
	
	# First check if we're falling onto a ledge from above
	var downward_velocity = velocity.dot(gravity_direction)
	if downward_velocity > vault_min_downward_speed:
		var down_ray_start = global_position
		var down_ray_end = down_ray_start + gravity_direction * (vault_max_height_from_feet + 0.5)
		var down_query = PhysicsRayQueryParameters3D.create(down_ray_start, down_ray_end)
		down_query.exclude = [self.get_rid()]
		var floor_hit = world_space.intersect_ray(down_query)
		if floor_hit and (floor_hit.position.y > global_position.y - vault_max_height_from_feet):
			_perform_vault(wall_normal)
			return true

	# Original ledge check for forward vaulting
	var ray_start_vertical_offset = -gravity_direction * (vault_max_height_from_feet - (player_height / 2.0))
	var ray_start_horizontal_offset = -wall_normal * vault_forward_check_distance
	var ray_start = player_center + ray_start_vertical_offset + ray_start_horizontal_offset
	var ray_length = (vault_max_height_from_feet - vault_min_height_from_feet) + 0.2
	var ray_end = ray_start + gravity_direction * ray_length
	var query_params = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query_params.exclude = [self.get_rid()]
	query_params.hit_from_inside = true
	var ledge_result = world_space.intersect_ray(query_params)
	if not ledge_result: return false
	
	var landing_spot = ledge_result.position
	var clearance_check_start = landing_spot - gravity_direction * 0.05
	var clearance_check_end = clearance_check_start + -gravity_direction * (player_height + 0.1)
	var clearance_query = PhysicsRayQueryParameters3D.create(clearance_check_start, clearance_check_end)
	clearance_query.exclude = [self.get_rid()]
	if world_space.intersect_ray(clearance_query): return false

	_perform_vault(wall_normal)
	return true

func _perform_vault(wall_normal: Vector3):
	# Preserve more natural momentum
	var vertical_vel = velocity.project(gravity_direction)
	var horizontal_vel = velocity - vertical_vel
	
	# Only remove velocity going INTO the wall, keep parallel motion
	var into_wall_vel = horizontal_vel.project(wall_normal)
	var preserved_vel = horizontal_vel - into_wall_vel * 0.8 # Only partially cancel wall-ward velocity
	
	# Apply boosts while maintaining more natural movement
	var upward_boost = -gravity_direction * vault_boost_vertical_force
	var outward_boost = wall_normal * vault_boost_horizontal_force * 0.5 # Reduced outward force
	
	velocity = preserved_vel * 1.2 + upward_boost + outward_boost # Slight speed boost
	
	vault_cooldown_timer = vault_cooldown

func _handle_ledge_climb():
	if not ledge_climb_enabled or is_on_floor() or is_climbing or ledge_climb_cooldown_timer > 0:	
		return
	if velocity.dot(-gravity_direction) < ledge_climb_min_upward_speed:	
		return
		
	if ledge_detector_ray.is_colliding():
		var point = ledge_detector_ray.get_collision_point()
		var normal = ledge_detector_ray.get_collision_normal()
		_check_and_perform_climb(point, normal)

func _check_and_perform_climb(wall_point: Vector3, wall_normal: Vector3):
	var world_space = get_world_3d().direct_space_state
	var player_height = player_collider.shape.height
	
	var ray_start = wall_point - wall_normal * 0.1 + (-gravity_direction * 0.3)
	var ray_end = ray_start + gravity_direction * 0.5
	var query_params = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query_params.exclude = [self.get_rid()]
	query_params.hit_from_inside = true
	var ledge_result = world_space.intersect_ray(query_params)
	if not ledge_result:	
		return

	var landing_spot = ledge_result.position
	var landing_normal = ledge_result.normal

	if landing_normal.dot(-gravity_direction) < cos(deg_to_rad(MAX_SLOPE_ANGLE)):	
		return
		
	var ceiling_check_start = landing_spot - gravity_direction * 0.05
	var ceiling_check_end = ceiling_check_start + -gravity_direction * (player_height + 0.1)
	var ceiling_query = PhysicsRayQueryParameters3D.create(ceiling_check_start, ceiling_check_end)
	ceiling_query.exclude = [self.get_rid()]
	if world_space.intersect_ray(ceiling_query):	
		return

	_perform_climb(landing_spot, wall_normal)

func _perform_climb(landing_position: Vector3, wall_normal: Vector3):
	if is_climbing:	
		return

	is_climbing = true
	velocity = Vector3.ZERO
	var player_height = player_collider.shape.height
	var player_radius = player_collider.shape.radius if player_collider.shape is CapsuleShape3D else 0.5
	
	var hang_pos = landing_position + wall_normal * player_radius + gravity_direction * (player_height / 2.0 - 0.2)
	var final_pos = landing_position + (-gravity_direction * (player_height / 2.0 + 0.05))

	var tween = create_tween()
	tween.set_parallel(false)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position", hang_pos, ledge_climb_duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", final_pos, ledge_climb_duration * 0.6).set_ease(Tween.EASE_IN_OUT)
	
	await tween.finished

	is_climbing = false
	ledge_climb_cooldown_timer = ledge_climb_cooldown
	is_grounded = true
	was_grounded = true
