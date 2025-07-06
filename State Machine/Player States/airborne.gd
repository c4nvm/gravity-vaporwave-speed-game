extends State

func enter():
	player.time_since_airborne = 0.0
	# Ensure the slide intent flag is false when becoming airborne.
	player.wants_to_slide_on_land = false

func process_physics(delta):
	player._pre_physics_process()
	player._update_gravity()
	player._apply_gravity(delta)
	_handle_air_movement(delta)
	player._align_with_surface(delta)
	player.move_and_slide()
	_handle_vaulting()
	_handle_ledge_climb()

func _handle_air_movement(delta):
	var input_dir : Vector2 = player.get_wish_direction()
	var raycast_forward = -player.direction_ray.global_transform.basis.z.normalized()
	var raycast_right = player.direction_ray.global_transform.basis.x.normalized()
	var vertical_velocity = player.velocity.project(player.up_direction)
	var horizontal_velocity = player.velocity - vertical_velocity

	raycast_forward = player._safe_project(raycast_forward, player.gravity_direction)
	raycast_right = player._safe_project(raycast_right, player.gravity_direction)
	var wish_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
	var target_h_velocity = wish_dir * player.speed
	var current_accel = player.air_acceleration
	var current_decel = player.air_deceleration

	if input_dir.length() > 0.01:
		horizontal_velocity = horizontal_velocity.lerp(target_h_velocity, current_accel * delta)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, current_decel * delta)

	player.velocity = horizontal_velocity + vertical_velocity

func _handle_vaulting():
	if not player.vault_enabled or player.ground_ray.is_colliding() or player.vault_cooldown_timer > 0:
		return

	var forward_velocity_component = player.velocity.dot(-player.transform.basis.z)
	var downward_velocity = player.velocity.dot(player.gravity_direction)
	if forward_velocity_component < 1.0 and downward_velocity < player.vault_min_downward_speed:
		return

	for i in range(player.get_slide_collision_count()):
		var collision = player.get_slide_collision(i)
		if collision:
			var angle_with_gravity = collision.get_normal().angle_to(-player.gravity_direction)
			if rad_to_deg(angle_with_gravity) > 80:
				if _check_and_perform_vault(collision):
					break

func _check_and_perform_vault(collision: KinematicCollision3D) -> bool:
	var world_space = player.get_world_3d().direct_space_state
	var player_center = player.global_position
	var player_height = player.player_collider.shape.height
	var up_direction = -player.gravity_direction

	# Ceiling check: Cast a short ray upwards from the player's head.
	var ceiling_check_start = player_center
	var ceiling_check_end = ceiling_check_start + (up_direction*2)
	var ceiling_query_params = PhysicsRayQueryParameters3D.create(ceiling_check_start, ceiling_check_end)
	ceiling_query_params.exclude = [player.get_rid()]

	# If the ray hits something, there's a ceiling, so don't vault.
	if world_space.intersect_ray(ceiling_query_params):
		return false

	var wall_normal = collision.get_normal()
	var downward_velocity = player.velocity.dot(player.gravity_direction)

	if downward_velocity > player.vault_min_downward_speed:
		var down_ray_start = player.global_position
		var down_ray_end = down_ray_start + player.gravity_direction * (player.vault_max_height_from_feet + 0.5)
		var down_query = PhysicsRayQueryParameters3D.create(down_ray_start, down_ray_end)
		down_query.exclude = [player.get_rid()]
		var floor_hit = world_space.intersect_ray(down_query)
		if floor_hit and (floor_hit.position.y > player.global_position.y - player.vault_max_height_from_feet):
			_perform_vault(wall_normal)
			return true

	var ray_start_vertical_offset = -player.gravity_direction * (player.vault_max_height_from_feet - (player_height / 2.0))
	var ray_start_horizontal_offset = -wall_normal * player.vault_forward_check_distance
	var ray_start = player_center + ray_start_vertical_offset + ray_start_horizontal_offset
	var ray_length = (player.vault_max_height_from_feet - player.vault_min_height_from_feet) + 0.2
	var ray_end = ray_start + player.gravity_direction * ray_length
	var query_params = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query_params.exclude = [player.get_rid()]
	query_params.hit_from_inside = true
	var ledge_result = world_space.intersect_ray(query_params)
	if not ledge_result: return false

	var landing_spot = ledge_result.position
	var clearance_check_start = landing_spot - player.gravity_direction * 0.05
	var clearance_check_end = clearance_check_start + -player.gravity_direction * (player_height + 0.1)
	var clearance_query = PhysicsRayQueryParameters3D.create(clearance_check_start, clearance_check_end)
	clearance_query.exclude = [player.get_rid()]
	if world_space.intersect_ray(clearance_query): return false

	_perform_vault(wall_normal)
	return true

func _perform_vault(wall_normal: Vector3):
	var vertical_vel = player.velocity.project(player.gravity_direction)
	var horizontal_vel = player.velocity - vertical_vel
	var into_wall_vel = horizontal_vel.project(wall_normal)
	var preserved_vel = horizontal_vel - into_wall_vel * 0.8
	var upward_boost = -player.gravity_direction * player.vault_boost_vertical_force
	var outward_boost = wall_normal * player.vault_boost_horizontal_force * 0.5

	player.velocity = preserved_vel * 1.2 + upward_boost + outward_boost
	player.vault_cooldown_timer = player.vault_cooldown

func _handle_ledge_climb():
	if not player.ledge_climb_enabled or player.ground_ray.is_colliding() or player.ledge_climb_cooldown_timer > 0:
		return
	if player.velocity.dot(-player.gravity_direction) < player.ledge_climb_min_upward_speed:
		return

	if player.ledge_detector_ray.is_colliding():
		var point = player.ledge_detector_ray.get_collision_point()
		var normal = player.ledge_detector_ray.get_collision_normal()
		_check_and_perform_climb(point, normal)

func _check_and_perform_climb(wall_point: Vector3, wall_normal: Vector3):
	var world_space = player.get_world_3d().direct_space_state
	var player_height = player.player_collider.shape.height
	var ray_start = wall_point - wall_normal * 0.1 + (-player.gravity_direction * 0.3)
	var ray_end = ray_start + player.gravity_direction * 0.5
	var query_params = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query_params.exclude = [player.get_rid()]
	query_params.hit_from_inside = true
	var ledge_result = world_space.intersect_ray(query_params)
	if not ledge_result:
		return

	var landing_spot = ledge_result.position
	var landing_normal = ledge_result.normal
	if landing_normal.dot(-player.gravity_direction) < cos(deg_to_rad(player.MAX_SLOPE_ANGLE)):
		return

	var ceiling_check_start = landing_spot - player.gravity_direction * 0.05
	var ceiling_check_end = ceiling_check_start + -player.gravity_direction * (player_height + 0.1)
	var ceiling_query = PhysicsRayQueryParameters3D.create(ceiling_check_start, ceiling_check_end)
	ceiling_query.exclude = [player.get_rid()]
	if world_space.intersect_ray(ceiling_query):
		return

	player.state_machine.transition_to("LedgeClimbing")

func get_next_state() -> String:
	# Check for slide/slam input first.
	if player.is_action_just_pressed_checked("slide"):
		# Check if the player is close to the ground.
		if player.pre_land_slide_ray.is_colliding():
			# If close, set a flag to slide upon landing instead of slamming now.
			player.wants_to_slide_on_land = true
		# If not close to the ground, perform a normal ground slam check.
		elif player.ground_slam_enabled and \
				player.time_since_airborne > player.slam_takeoff_cooldown and \
				not player.just_did_slide_hop:
			return "GroundSlam"

	# Check if we have landed.
	if player.ground_ray.is_colliding():
		return "Grounded"
		
	return ""
