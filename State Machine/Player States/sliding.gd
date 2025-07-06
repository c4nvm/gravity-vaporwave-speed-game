extends State

func enter():
	player.was_sliding = true
	player.standing_collision.disabled = true
	player.sliding_collision.disabled = false
	player.target_camera_offset = player.crouch_camera_offset

func exit():
	player.standing_collision.disabled = false
	player.sliding_collision.disabled = true
	player.target_camera_offset = Vector3.ZERO

func process_physics(delta):
	player._pre_physics_process()
	player._update_gravity()
	player._apply_gravity(delta)
	_apply_slide_physics(delta)
	player._align_with_surface(delta)
	player.move_and_slide()
	
	if player.is_action_just_pressed_checked("jump"):
		_perform_slide_hop()

func _apply_slide_physics(delta):
	var slope_normal = player.get_floor_normal()
	if slope_normal == Vector3.ZERO or player.gravity_direction == Vector3.ZERO:
		return

	var horizontal_vel = player.velocity.slide(player.gravity_direction)
	var vertical_vel = player.velocity.project(player.gravity_direction)
	
	# Get the direction pointing down the slope.
	var slope_dir = -slope_normal.slide(player.gravity_direction).normalized()

	# Check if we are moving downhill (velocity is aligned with the slope direction)
	# A dot product > 0 means the angle is less than 90 degrees.
	if slope_dir.dot(horizontal_vel.normalized()) > 0.1:
		# Sliding downhill: add acceleration to gain speed.
		horizontal_vel += slope_dir * player.slide_downhill_accel * delta
	else:
		# Sliding on flat ground or uphill: apply friction to slow down.
		horizontal_vel = horizontal_vel.lerp(Vector3.ZERO, player.slide_friction * delta)

	player.velocity = horizontal_vel + vertical_vel

func _perform_slide_hop():
	var horizontal_velocity = player.velocity - player.velocity.project(player.up_direction)
	horizontal_velocity *= player.slide_hop_boost
	var vertical_velocity = player.up_direction * (player.jump_force * player.slide_hop_jump_multiplier)
	player.velocity = horizontal_velocity + vertical_velocity
	
	# Set the flag to disable slamming on the next jump.
	player.just_did_slide_hop = true
	
	player.state_machine.transition_to("Airborne")

func get_next_state() -> String:
	# Exit sliding if the button is released or speed is too low.
	if not player.is_action_pressed_checked("slide") or player.velocity.length() < player.slide_min_speed:
		return "Grounded"
	# Exit sliding if the player is no longer on the ground.
	if not player.ground_ray.is_colliding():
		return "Airborne"
	return ""
