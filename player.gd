extends CharacterBody3D

#region State Machine
@onready var state_machine = $StateMachine
#endregion

#region UI
# Note: This path might need to be adjusted based on your final scene structure
@onready var state_label: Label = get_node_or_null("CanvasLayer/Label")
#endregion

#region Configuration
@export_group("Spawning")
@export var level_start_fade_duration := 2.0 # How long the fade-in lasts and input is disabled.

@export_group("Movement")
const MAX_SLOPE_ANGLE := 40.0
@export var speed := 10.0
@export var jump_force := 10.0
@export var gravity := 30.0
@export var grounded_gravity_multiplier: float = 2.0
@export var acceleration := 15.0
@export var deceleration := 20.0
@export var air_acceleration := 2.0
@export var air_deceleration := 0.1
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
@export var crouch_camera_offset := Vector3(0, -0.9, 0)
@export var crouch_transition_speed := 5.0

@export_group("Advanced Movement")
@export var slide_hop_boost := 1.6 # Multiplier for speed boost when jumping out of a slide.
@export var slide_hop_jump_multiplier := 0.8 # Multiplier for jump force when slide hopping.
@export var high_speed_decel_multiplier := 0.01 # How much to reduce deceleration when moving faster than base speed. Lower is less friction.

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

#region Gravity Gun Configuration
@export_group("Gravity Gun")
@export var gravity_gun_enabled := true
@export var gravity_gun_range := 15.0
@export var gravity_gun_hold_distance := 3.0
@export var gravity_gun_hold_offset_y := 0.0 # Vertical offset for held object
@export var gravity_gun_shoot_force := 50.0
@export var gravity_gun_lerp_speed := 15.0
@export var gravity_gun_debug := false
@export var knockback_force := 10.0
@export var shoot_ray_length := 1000.0
@export var shoot_position_offset := 0.1 # How far from the impact surface to place the object
#endregion
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
@onready var slide_ray: RayCast3D = $SlideRay
@onready var standing_collision: CollisionShape3D = $StandingCollision
@onready var sliding_collision: CollisionShape3D = $SlidingCollision
@onready var game_ui = get_node_or_null("/root/Main/GameUI")

# Gravity Gun Nodes
@onready var gravity_gun_ray: RayCast3D = $CameraPivot/Camera3D/GravityGunRay
@onready var hold_position: Marker3D = $CameraPivot/Camera3D/HoldPosition
#endregion

#region State Variables
var input_enabled := false
var gravity_fields: Array[Node] = []
var nearest_gravity_field: Area3D = null
var is_on_planet := false
var gravity_direction := Vector3.DOWN
var mouse_pitch := 0.0
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2
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
var current_camera_pivot

var vault_cooldown_timer := 0.0
var ledge_climb_cooldown_timer := 0.0

# Gravity Gun State
var held_object: RigidBody3D = null
#endregion

func _ready():
	# --- Spawn logic for input delay and screen fade ---
	input_enabled = false
	# Use a timer to enable input after the specified duration.
	var spawn_timer = Timer.new()
	spawn_timer.wait_time = level_start_fade_duration
	spawn_timer.one_shot = true
	# Connect the timer's timeout signal to enable input and then free the timer.
	spawn_timer.timeout.connect(func():
		input_enabled = true
		spawn_timer.queue_free()
	)
	add_child(spawn_timer)
	spawn_timer.start()

	# Tell the GameManager (your autoload) to start the fade-in effect.
	# NOTE: Replace "GameManager" if your autoload singleton is named differently (e.g., "Main").
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").start_level_fade_in(level_start_fade_duration)

	# --- Existing _ready() logic ---
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_gravity_gun()
	_cache_gravity_fields()
	_enter_planetary_mode()
	max_look_angle = deg_to_rad(max_look_angle)
	current_camera_pivot = standing_camera_pivot
	camera.reparent(current_camera_pivot)
	camera.position = Vector3.ZERO
	current_camera_offset = Vector3.ZERO
	target_camera_offset = Vector3.ZERO

	state_machine.init(self)

	if state_label:
		state_machine.state_changed.connect(func(new_state_name): state_label.text = "State: " + new_state_name)
		if state_machine.current_state:
			state_label.text = "State: " + state_machine.current_state.name


func _input(event: InputEvent):
	# --- Block discrete input events if disabled ---
	if not input_enabled:
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# --- Gravity Gun Input ---
	if gravity_gun_enabled:
		if Input.is_action_just_pressed("pickup_drop"):
			if held_object:
				_drop_object()
			else:
				_pickup_object()
		elif Input.is_action_just_pressed("shoot_object"):
			if held_object:
				_shoot_object()

	# --- Mouse Look ---
	if event is InputEventMouseMotion:
		_handle_mouse_movement(event)

	# --- State Machine Input ---
	state_machine.process_input(event)


func _handle_mouse_movement(event: InputEventMouseMotion):
	if state_machine.current_state.name == "LedgeClimbing":
		return

	if is_free_space_mode:
		free_space_rotation.x -= event.relative.y * free_space_mouse_sensitivity
		free_space_rotation.y -= event.relative.x * free_space_mouse_sensitivity
		free_space_rotation.x = clamp(free_space_rotation.x, -PI/2, PI/2)
	else:
		rotate(transform.basis.y, -event.relative.x * (mouse_sensitivity/1000))
		mouse_pitch = clamp(mouse_pitch - event.relative.y * (mouse_sensitivity/1000), -max_look_angle, max_look_angle)
		current_camera_pivot.rotation.x = mouse_pitch


func _process(delta):
	current_camera_offset = current_camera_offset.lerp(
		target_camera_offset,
		crouch_transition_speed * delta
	)
	camera.position = current_camera_offset
	state_machine.process_frame(delta)


func _physics_process(delta):
	if held_object:
		_update_held_object_position(delta)

	_update_nearest_gravity_field()

	if vault_cooldown_timer > 0:
		vault_cooldown_timer -= delta
	if ledge_climb_cooldown_timer > 0:
		ledge_climb_cooldown_timer -= delta

	if should_switch_modes() and not is_transitioning:
		_switch_movement_mode(nearest_gravity_field == null)

	state_machine.process_physics(delta)

	if is_instance_valid(game_ui):
		game_ui.update_debug_info(state_machine.current_state.name, velocity)


# --- Centralized Input Functions ---
# States will call these functions instead of Input directly.

func get_wish_direction() -> Vector2:
	"""
	Gets the player's movement input as a Vector2.
	Returns Vector2.ZERO if input is disabled.
	"""
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_backward", "move_forward")

func is_action_just_pressed_checked(action: StringName) -> bool:
	"""
	Checks if an action was just pressed, but only if input is enabled.
	"""
	if not input_enabled:
		return false
	return Input.is_action_just_pressed(action)

func is_action_pressed_checked(action: StringName) -> bool:
	"""
	Checks if an action is currently held down, but only if input is enabled.
	"""
	if not input_enabled:
		return false
	return Input.is_action_pressed(action)

func get_free_space_input() -> Vector3:
	"""
	Gets the combined movement input for the FreeSpace state.
	Returns Vector3.ZERO if input is disabled.
	"""
	if not input_enabled:
		return Vector3.ZERO
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	return Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()


#region Gravity Gun
#==============================================================================
# GRAVITY GUN SETUP GUIDE (UPDATED)
#
# 1. SCENE TREE:
#    - Player (CharacterBody3D) > CameraPivot > Camera3D > GravityGunRay / HoldPosition
#
# 2. PHYSICS LAYERS:
#    - Environment/World geometry should be on **Layer 1**.
#    - All grabbable RigidBody3D objects must be on **Layer 3**.
#
# 3. GROUPS:
#    - Add all grabbable `RigidBody3D` nodes to a group named "grabbable".
#
# 4. INPUT MAP:
#    - "pickup_drop" and "shoot_object" actions must be defined.
#
# 5. DEBUGGING:
#    - Enable the "Gravity Gun Debug" property in the Inspector to see print logs.
#
#==============================================================================

func _setup_gravity_gun():
	if not gravity_gun_enabled:
		return

	if is_instance_valid(gravity_gun_ray):
		gravity_gun_ray.target_position = Vector3(0, 0, -gravity_gun_range)
		# (1 << 0) is layer 1, (1 << 2) is layer 3.
		gravity_gun_ray.collision_mask = 4
	else:
		push_warning("Gravity Gun: 'GravityGunRay' node not found.")

	if is_instance_valid(hold_position):
		# Use offset variables to set the hold position
		hold_position.position = Vector3(0, gravity_gun_hold_offset_y, -gravity_gun_hold_distance)
	else:
		push_warning("Gravity Gun: 'HoldPosition' node not found.")

	if gravity_gun_debug: print("Gravity Gun: Setup complete.")


func _pickup_object():
	if not is_instance_valid(gravity_gun_ray): return
	if gravity_gun_debug: print("--- Gravity Gun: Attempting Pickup ---")

	gravity_gun_ray.force_raycast_update()

	if gravity_gun_ray.is_colliding():
		var collider = gravity_gun_ray.get_collider()
		if gravity_gun_debug: print("Raycast hit: ", collider.name if is_instance_valid(collider) else "Invalid Collider")

		if collider is RigidBody3D and collider.is_in_group("grabbable"):
			if gravity_gun_debug: print("SUCCESS: Target '", collider.name, "' is a valid grabbable object.")
			held_object = collider
			held_object.freeze = true
			held_object.collision_layer = 0
			held_object.collision_mask = 0
		else:
			if gravity_gun_debug:
				var reason = "not a RigidBody3D" if not collider is RigidBody3D else "not in 'grabbable' group"
				print("FAILURE: Target '", collider.name, "' is not a valid grabbable object (Reason: %s)." % reason)
	else:
		if gravity_gun_debug: print("FAILURE: Raycast did not hit any valid object.")

func _drop_object():
	if not held_object:
		if gravity_gun_debug: print("--- Gravity Gun: Drop failed. No object held. ---")
		return

	if gravity_gun_debug: print("--- Gravity Gun: Dropping '", held_object.name, "' ---")

	held_object.freeze = false
	# Restore object to layer 3 and set its mask to see layers 1 and 3.
	held_object.collision_layer = (1 << 2) # Set object's layer to 3
	held_object.collision_mask = (1 << 0) | (1 << 2) # Collide with layers 1 & 3

	# Give it a gentle push forward from player's momentum
	held_object.linear_velocity = velocity * 0.5
	held_object.angular_velocity = Vector3.ZERO

	held_object = null

func _shoot_object():
	if not held_object:
		if gravity_gun_debug: print("--- Gravity Gun: Shoot failed. No object held. ---")
		return

	var shot_object = held_object
	if gravity_gun_debug: print("--- Gravity Gun: Shooting '", shot_object.name, "' ---")
	held_object = null

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = camera.global_transform.origin
	var shoot_direction = -camera.global_transform.basis.z.normalized()
	query.to = query.from + shoot_direction * shoot_ray_length
	query.exclude = [self.get_rid(), shot_object.get_rid()]
	
	var result = space_state.intersect_ray(query)
	var impact_point = query.to # Default to max range if no collision
	if result:
		impact_point = result.position

	# --- Position the object ---
	if result:
		shot_object.global_transform.origin = impact_point + result.normal * shoot_position_offset
		if gravity_gun_debug: print("Shot object teleported to safe position:", shot_object.global_transform.origin)
	else:
		shot_object.global_transform.origin = impact_point
		if gravity_gun_debug: print("Shot object teleported to max range:", query.to)

	# --- Reset physics properties and apply velocity ---
	shot_object.freeze = false
	shot_object.collision_layer = (1 << 2)
	shot_object.collision_mask = (1 << 0) | (1 << 2)
	shot_object.angular_velocity = Vector3.ZERO
	shot_object.linear_velocity = shoot_direction * gravity_gun_shoot_force
	if gravity_gun_debug: print("Applied velocity %s to '%s'" % [shot_object.linear_velocity, shot_object.name])

	# --- Apply knockback to the player ---
	var knockback_direction = camera.global_transform.basis.z 
	velocity += knockback_direction * knockback_force
	if gravity_gun_debug: print("Applied knockback force:", knockback_direction * knockback_force)

func _update_held_object_position(delta: float):
	if not held_object or not is_instance_valid(hold_position): return

	var target_transform = hold_position.global_transform
	var new_transform = held_object.global_transform.interpolate_with(target_transform, delta * gravity_gun_lerp_speed)

	held_object.global_transform = new_transform

#endregion

func _pre_physics_process():
	if player_collider:
		player_collider.global_rotation = Vector3.ZERO

	was_grounded = is_grounded
	is_grounded = ground_ray.is_colliding()


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


func _switch_movement_mode(free_space: bool):
	if is_free_space_mode == free_space:
		return

	if held_object:
		if gravity_gun_debug: print("--- Gravity Gun: Auto-dropping '", held_object.name, "' due to movement mode switch. ---")
		_drop_object()

	is_transitioning = true
	transition_timer = 0.0
	transition_start_velocity = velocity
	is_free_space_mode = free_space

	var transition_tween = create_tween()
	transition_tween.tween_interval(transition_duration)
	await transition_tween.finished

	if free_space:
		state_machine.transition_to("FreeSpace")
	else:
		state_machine.transition_to("Grounded")

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
	was_sliding = false
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

	if is_grounded:
		velocity += gravity_direction * gravity * grounded_gravity_multiplier * delta
	else:
		velocity += gravity_direction * gravity * delta


func _is_going_uphill() -> bool:
	return is_grounded and was_sliding and -get_floor_normal().slide(gravity_direction).normalized().dot(velocity.normalized()) > 0.1


func should_switch_modes() -> bool:
	return (nearest_gravity_field == null) != is_free_space_mode


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
	velocity.y = 0
	global_pos.y = test_transform.origin.y
	global_position = global_pos
