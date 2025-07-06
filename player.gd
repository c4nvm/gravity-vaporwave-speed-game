#
# Advanced Character Controller
# Handles player movement, state management (grounded, sliding, zero-g),
# and interaction systems like the gravity gun.
#
extends CharacterBody3D

# Emitted on the first physics frame the player's velocity is non-zero.
signal first_move

#region State Machine
@onready var state_machine = $StateMachine
#endregion

#region Configuration
@export_group("Spawning")
@export var level_start_fade_duration := 2.0

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
@export var pre_land_slide_distance := 0.5

@export_group("Advanced Movement")
@export var slide_hop_boost := 1.6
@export var slide_hop_jump_multiplier := 0.8
@export var high_speed_decel_multiplier := 0.01

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

@export_group("Ground Slam")
@export var ground_slam_enabled := true
@export var slam_force := 50.0
@export var slam_horizontal_dampening := 0.2
@export var slam_takeoff_cooldown := 0.25
@export var slam_impact_radius := 5.0
@export var slam_impact_force := 3.0
@export var slam_boost_window := 0.3
@export var slam_boost_multiplier := 1.5
@export var slam_jump_boost_multiplier := 1.4

@export_group("Free Space Movement")
@export var free_space_max_speed := 20.0
@export var free_space_acceleration := 5.0
@export var free_space_deceleration := 2.0
@export var free_space_rotation_speed := 2.0
@export var free_space_momentum_gain := 0.95
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

@export_group("Gravity Gun")
@export var gravity_gun_enabled := true
@export var gravity_gun_range := 15.0
@export var gravity_gun_hold_distance := 3.0
@export var gravity_gun_hold_offset_y := 0.0
@export var gravity_gun_shoot_force := 50.0
@export var gravity_gun_lerp_speed := 15.0
@export var gravity_gun_debug := false
@export var knockback_force := 10.0
@export var shoot_ray_length := 1000.0
@export var shoot_position_offset := 0.1
@export var laser_beam_segment_scene: PackedScene
@export var laser_beam_lifetime := 0.5
@export var laser_fade_duration := 0.3
@export var laser_fade_delay_per_segment := 0.03

@export_group("Switch Interaction")
@export var switch_activation_area_scene: PackedScene
@export var switch_activation_duration := 0.5
@export var switch_activation_radius := 0.5
#endregion

#region Nodes
@onready var pre_land_slide_ray: RayCast3D = $PreLandSlideRay
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
@onready var gravity_gun_ray: RayCast3D = $CameraPivot/Camera3D/GravityGunRay
@onready var hold_position: Marker3D = $CameraPivot/Camera3D/HoldPosition
#endregion

#region State Variables
var wants_to_slide_on_land := false
var slam_boost_timer := 0.0
var time_since_airborne := 0.0
var just_did_slide_hop := false
var movement_locked := true
var spawn_protection_timer : Timer
var input_enabled := false
var _has_moved := false
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
const GroundSlamEffect = preload("res://VFX/ground_slam_effect.tscn")
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
var held_object: RigidBody3D = null
var spawn_time := 0.0
var last_mouse_movement := Vector2.ZERO
var _slam_query_params: PhysicsShapeQueryParameters3D
var _slam_shape: CylinderShape3D
#endregion

func set_fov(new_fov: float):
	if is_instance_valid(camera):
		camera.fov = new_fov

func set_mouse_sensitivity(new_sensitivity: float):
	mouse_sensitivity = new_sensitivity

func _ready():
	pre_land_slide_ray.target_position = Vector3.DOWN * pre_land_slide_distance
	spawn_time = Time.get_ticks_msec()
	velocity = Vector3.ZERO
	free_space_velocity = Vector3.ZERO
	
	spawn_protection_timer = Timer.new()
	spawn_protection_timer.wait_time = level_start_fade_duration
	spawn_protection_timer.one_shot = true
	spawn_protection_timer.timeout.connect(_on_spawn_protection_end)
	add_child(spawn_protection_timer)
	spawn_protection_timer.start()
	
	await get_tree().physics_frame
	is_grounded = ground_ray.is_colliding()
	
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_player(self)
	
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
	_setup_slam_query()
	state_machine.init(self)

func _setup_slam_query():
	_slam_shape = CylinderShape3D.new()
	_slam_query_params = PhysicsShapeQueryParameters3D.new()
	_slam_query_params.exclude = [get_rid()]

func _on_spawn_protection_end():
	movement_locked = false
	input_enabled = true
	spawn_protection_timer.queue_free()

func _input(event: InputEvent):
	if not input_enabled or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if gravity_gun_enabled:
		if Input.is_action_just_pressed("pickup_drop"):
			if held_object:
				_drop_object()
			else:
				_pickup_object()
		elif Input.is_action_just_pressed("shoot_object"):
			if held_object:
				_shoot_object()
	
	if event is InputEventMouseMotion:
		_handle_mouse_movement(event)
	
	state_machine.process_input(event)

func _handle_mouse_movement(event: InputEventMouseMotion):
	if state_machine.current_state.name == "LedgeClimbing":
		return
	
	last_mouse_movement = event.relative
	var sensitivity_factor = mouse_sensitivity / 1000.0
	
	if state_machine.current_state.name != "FreeSpace":
		rotate(transform.basis.y, -event.relative.x * sensitivity_factor)
		mouse_pitch = clamp(mouse_pitch - event.relative.y * sensitivity_factor, -max_look_angle, max_look_angle)
		current_camera_pivot.rotation.x = mouse_pitch

func _process(delta):
	current_camera_offset = current_camera_offset.lerp(
		target_camera_offset,
		crouch_transition_speed * delta
	)
	camera.position = current_camera_offset
	
	state_machine.process_frame(delta)

# Replace your existing _physics_process with this version
func _physics_process(delta):
	if movement_locked:
		velocity = Vector3.ZERO
		free_space_velocity = Vector3.ZERO
		return
	
	if held_object:
		_update_held_object_position(delta)
	
	_update_nearest_gravity_field()
	
	if vault_cooldown_timer > 0:
		vault_cooldown_timer -= delta
	if ledge_climb_cooldown_timer > 0:
		ledge_climb_cooldown_timer -= delta
	
	# Decrement the slam boost timer
	if slam_boost_timer > 0:
		slam_boost_timer -= delta
	
	# Update airborne timer and slide hop status
	if not is_on_floor():
		time_since_airborne += delta
	else:
		time_since_airborne = 0.0
		# Reset the slide hop flag once the player is grounded again
		just_did_slide_hop = false
	
	if should_switch_modes() and not is_transitioning:
		_switch_movement_mode(nearest_gravity_field == null)
	
	state_machine.process_physics(delta)
	
	if not _has_moved and velocity.length_squared() > 0.01 and not movement_locked:
		first_move.emit()
		_has_moved = true

func get_wish_direction() -> Vector2:
	if not input_enabled: return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_backward", "move_forward")

func is_action_just_pressed_checked(action: StringName) -> bool:
	if not input_enabled: return false
	return Input.is_action_just_pressed(action)

func is_action_pressed_checked(action: StringName) -> bool:
	if not input_enabled: return false
	return Input.is_action_pressed(action)

func get_free_space_input() -> Vector3:
	if not input_enabled: return Vector3.ZERO
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	return Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()

func _setup_gravity_gun():
	if not gravity_gun_enabled: return
	if is_instance_valid(gravity_gun_ray):
		gravity_gun_ray.target_position = Vector3(0, 0, -gravity_gun_range)
		gravity_gun_ray.collision_mask = 1 << 2
	else:
		push_warning("Gravity Gun: 'GravityGunRay' node not found.")

	if is_instance_valid(hold_position):
		hold_position.position = Vector3(0, gravity_gun_hold_offset_y, -gravity_gun_hold_distance)
	else:
		push_warning("Gravity Gun: 'HoldPosition' node not found.")

func _pickup_object():
	if not is_instance_valid(gravity_gun_ray): return
	gravity_gun_ray.force_raycast_update()
	if gravity_gun_ray.is_colliding():
		var collider = gravity_gun_ray.get_collider()
		if collider is RigidBody3D and collider.is_in_group("grabbable"):
			held_object = collider
			held_object.freeze = true
			held_object.collision_layer = 0
			held_object.collision_mask = 0
			if get_tree().root.has_node("GameManager"):
				get_tree().root.get_node("GameManager").play_gravity_gun_hold_sound()
				get_tree().root.get_node("GameManager").play_pickup_sound()

func _drop_object():
	if not held_object: return
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").stop_gravity_gun_hold_sound()
	held_object.freeze = false
	held_object.collision_layer = 1 << 2
	held_object.collision_mask = (1 << 0) | (1 << 2)
	held_object.linear_velocity = velocity * 0.5
	held_object.angular_velocity = Vector3.ZERO
	held_object = null

func _create_switch_activation_area(collision_point: Vector3, collision_normal: Vector3):
	if not switch_activation_area_scene:
		push_warning("No switch activation area scene assigned!")
		return
	var area_instance = switch_activation_area_scene.instantiate()
	get_tree().current_scene.add_child(area_instance)
	area_instance.global_transform.origin = collision_point + collision_normal * 0.05
	area_instance.scale = Vector3.ONE * switch_activation_radius
	var timer = Timer.new()
	timer.wait_time = switch_activation_duration
	timer.one_shot = true
	timer.timeout.connect(func():
		area_instance.queue_free()
		timer.queue_free()
	)
	area_instance.add_child(timer)
	timer.start()
	return area_instance

func _shoot_object():
	if not held_object: return
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").stop_gravity_gun_hold_sound()
		get_tree().root.get_node("GameManager").play_gravity_gun_shoot_sound()

	var shot_object = held_object
	var start_position = shot_object.global_transform.origin
	held_object = null

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = camera.global_transform.origin
	var shoot_direction = -camera.global_transform.basis.z.normalized()
	query.to = query.from + shoot_direction * shoot_ray_length
	query.exclude = [self.get_rid(), shot_object.get_rid()]
	var result = space_state.intersect_ray(query)

	var impact_point = query.to
	if result:
		impact_point = result.position
		_create_switch_activation_area(result.position, result.normal)

	_create_laser_beam(start_position, impact_point)

	if result:
		shot_object.global_transform.origin = impact_point + result.normal * shoot_position_offset
	else:
		shot_object.global_transform.origin = impact_point

	shot_object.freeze = false
	shot_object.collision_layer = 1 << 2
	shot_object.collision_mask = (1 << 0) | (1 << 2)
	shot_object.angular_velocity = Vector3.ZERO
	shot_object.linear_velocity = shoot_direction * gravity_gun_shoot_force

	var knockback_direction = camera.global_transform.basis.z
	velocity += knockback_direction * knockback_force
	if $CanvasLayer/Shockwave/AnimationPlayer.is_playing():
		$CanvasLayer/Shockwave/AnimationPlayer.play("RESET")
	$CanvasLayer/Shockwave/AnimationPlayer.play("Shockwave")

func _create_laser_beam(start_pos: Vector3, end_pos: Vector3):
	if not laser_beam_segment_scene:
		push_warning("Gravity Gun: 'laser_beam_segment_scene' is not set.")
		return

	var beam_path = Path3D.new()
	beam_path.name = "LaserBeamPath"
	beam_path.curve = Curve3D.new()
	get_tree().current_scene.add_child(beam_path)

	var curve = beam_path.curve
	var direction = (end_pos - start_pos).normalized()
	var total_distance = start_pos.distance_to(end_pos)
	var segment_length = 1.0

	var current_distance = 0.0
	while current_distance < total_distance:
		var point_position = start_pos + direction * current_distance
		curve.add_point(point_position)
		current_distance += segment_length
	curve.add_point(end_pos)

	for i in range(curve.get_point_count()):
		var segment = laser_beam_segment_scene.instantiate()
		beam_path.add_child(segment)
		segment.global_position = curve.get_point_position(i)
		segment.look_at(segment.global_position + direction, Vector3.UP)

	_fade_out_beam(beam_path)

func _fade_out_beam(beam_path: Path3D):
	await get_tree().create_timer(laser_beam_lifetime).timeout
	if not is_instance_valid(beam_path): return

	var segments = beam_path.get_children()
	for segment in segments:
		if not is_instance_valid(segment): continue

		var tween = create_tween()
		var mesh_instance: MeshInstance3D = null
		if segment is MeshInstance3D:
			mesh_instance = segment
		else:
			for child in segment.get_children():
				if child is MeshInstance3D:
					mesh_instance = child
					break
		
		if mesh_instance and mesh_instance.get_surface_override_material(0):
			var material = mesh_instance.get_surface_override_material(0).duplicate()
			mesh_instance.set_surface_override_material(0, material)
			var start_color = material.albedo_color
			var end_color = Color(start_color.r, start_color.g, start_color.b, 0.0)
			tween.tween_property(material, "albedo_color", end_color, laser_fade_duration)
		else:
			tween.tween_interval(laser_fade_duration)

		tween.tween_callback(segment.queue_free)
		
		await get_tree().create_timer(laser_fade_delay_per_segment).timeout

	await get_tree().create_timer(laser_fade_duration).timeout
	if is_instance_valid(beam_path):
		beam_path.queue_free()

func _update_held_object_position(delta: float):
	if not held_object or not is_instance_valid(hold_position): return
	var target_transform = hold_position.global_transform
	var new_transform = held_object.global_transform.interpolate_with(target_transform, delta * gravity_gun_lerp_speed)
	held_object.global_transform = new_transform

func _pre_physics_process():
	if player_collider:
		player_collider.global_rotation = Vector3.ZERO
	was_grounded = is_grounded
	is_grounded = ground_ray.is_colliding()

func _align_with_surface(delta: float):
	if not is_on_planet or not is_instance_valid(nearest_gravity_field): return
	var target_up = -gravity_direction.normalized()
	var current_up = transform.basis.y
	var rot = Quaternion(current_up, target_up)
	transform.basis = transform.basis.slerp(Basis(rot) * transform.basis, gravity_smoothness * delta).orthonormalized()

func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	var projected = vector - vector.project(normal)
	return projected.normalized() if projected.length() > 0.001 else Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()

func _switch_movement_mode(free_space: bool):
	if is_free_space_mode == free_space: return
	if held_object: _drop_object()

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
	if not is_transitioning: return
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
	var spawn_field: Area3D = null
	for field in gravity_fields:
		if field.get("is_spawn") and field.is_spawn:
			spawn_field = field
			break
	if is_instance_valid(spawn_field):
		nearest_gravity_field = spawn_field
	elif not gravity_fields.is_empty():
		_update_nearest_gravity_field()
	else:
		nearest_gravity_field = null
	is_on_planet = nearest_gravity_field != null
	if is_on_planet:
		_update_gravity()
	floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

func _update_nearest_gravity_field():
	gravity_fields = get_tree().get_nodes_in_group("gravity_fields")
	if gravity_fields.is_empty():
		is_on_planet = false
		nearest_gravity_field = null
		last_gravity_field = null
		return

	if nearest_gravity_field and nearest_gravity_field.get("is_spawn") and nearest_gravity_field.is_spawn and nearest_gravity_field.is_body_inside(self):
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
	for field in gravity_fields:
		if not is_instance_valid(field): continue
		if field.is_body_inside(self):
			candidate_fields.append({
				"field": field, "priority": field.priority,
				"strength": field.gravity_strength, "distance": global_position.distance_to(field.global_position),
				"is_new": field != nearest_gravity_field, "is_directional": not field.gravity_point,
				"is_spawn": field.get("is_spawn")
			})
	return candidate_fields

func _sort_gravity_fields(a, b) -> bool:
	if a.is_spawn != b.is_spawn: return a.is_spawn
	if a.priority != b.priority: return a.priority > b.priority
	var a_dot = a.field.global_position.direction_to(global_position).dot(velocity.normalized())
	var b_dot = b.field.global_position.direction_to(global_position).dot(velocity.normalized())
	if abs(a_dot - b_dot) > 0.1: return a_dot < b_dot
	elif a.is_new != b.is_new: return a.is_new
	elif a.is_directional != b.is_directional: return a.is_directional
	else: return a.strength > b.strength if a.is_directional else a.distance < b.distance

func _should_switch_gravity_field(new_field) -> bool:
	if nearest_gravity_field == null: return true
	if nearest_gravity_field.get("is_spawn") and nearest_gravity_field.is_spawn and not nearest_gravity_field.is_body_inside(self):
		return true
	if new_field.priority > nearest_gravity_field.priority: return true
	return (gravity_field_transition_timer <= 0 and (new_field != nearest_gravity_field or not nearest_gravity_field.is_body_inside(self)))

func _update_gravity():
	if nearest_gravity_field and is_instance_valid(nearest_gravity_field):
		gravity_direction = (nearest_gravity_field.global_transform.origin - global_transform.origin).normalized() if nearest_gravity_field.gravity_point else nearest_gravity_field.gravity_direction
		self.up_direction = -gravity_direction

func _apply_gravity(delta):
	if is_free_space_mode or nearest_gravity_field == null: return
	if is_grounded:
		velocity += gravity_direction * gravity * grounded_gravity_multiplier * delta
	else:
		velocity += gravity_direction * gravity * delta

func _is_going_uphill() -> bool:
	return is_grounded and was_sliding and -get_floor_normal().slide(gravity_direction).normalized().dot(velocity.normalized()) > 0.1

func should_switch_modes() -> bool:
	return (nearest_gravity_field == null) != is_free_space_mode

func perform_ground_slam_impact():
	# 1. Play visual and audio feedback
	_play_ground_slam_feedback()

	# 2. Configure the query shape and position for this specific impact
	_slam_shape.radius = slam_impact_radius
	_slam_shape.height = slam_impact_radius / 2.0 # Keep height minimal
	_slam_query_params.shape_rid = _slam_shape.get_rid()
	_slam_query_params.transform = global_transform

	# 3. Execute the physics query to find nearby objects
	var space_state = get_world_3d().direct_space_state
	var results = space_state.intersect_shape(_slam_query_params)

	# 4. Process all affected objects
	for hit in results:
		var collider = hit.collider
		if not is_instance_valid(collider):
			continue

		# Break any "breakable" objects
		if collider.is_in_group("breakable") and collider.has_method("break_object"):
			# Pass impact position and player velocity for a more dynamic shatter
			collider.break_object(global_position, velocity)

		# Apply force to any standard rigid bodies
		elif collider is RigidBody3D:
			var direction = (collider.global_position - global_position).normalized()
			var impulse = direction * slam_impact_force
			collider.apply_central_impulse(impulse)

	# 5. Activate the slam boost mechanic
	slam_boost_timer = slam_boost_window

func _play_ground_slam_feedback():
	# Instantiate and configure the visual effect
	if GroundSlamEffect:
		var slam_effect_instance = GroundSlamEffect.instantiate()
		get_tree().root.add_child(slam_effect_instance)
		slam_effect_instance.global_position = global_position
		
		# Configure the effect's properties based on player stats
		# Note: Your effect scene must have these properties (`target_radius`, `duration`)
		# defined with @export for this to work.
		if slam_effect_instance.has_method("configure"):
			slam_effect_instance.configure(slam_impact_radius, 0.4)
		else:
			if "target_radius" in slam_effect_instance:
				slam_effect_instance.target_radius = slam_impact_radius
			if "duration" in slam_effect_instance:
				slam_effect_instance.duration = 0.4 # Or another value

	# Play sound effect via the game manager
	if GameManager.audio_manager:
		GameManager.audio_manager.play_sfx("GroundSlamImpact")

func _stair_step_down():
	if is_free_space_mode or not is_grounded: return
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
	if is_free_space_mode or wish_dir == Vector3.ZERO or velocity.y > 0: return
	var body_test_params = PhysicsTestMotionParameters3D.new()
	var body_test_result = PhysicsTestMotionResult3D.new()
	var test_transform = global_transform
	var distance = wish_dir * 0.1
	body_test_params.from = self.global_transform
	body_test_params.motion = distance
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result): return
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
	if !PhysicsServer3D.body_test_motion(self.get_rid(), body_test_params, body_test_result): return
	test_transform = test_transform.translated(body_test_result.get_travel())
	var surface_normal = body_test_result.get_collision_normal()
	if (snappedf(surface_normal.angle_to(vertical), 0.001) > deg_to_rad(MAX_SLOPE_ANGLE)): return
	var global_pos = global_position
	velocity.y = 0
	global_pos.y = test_transform.origin.y
	global_position = global_pos
