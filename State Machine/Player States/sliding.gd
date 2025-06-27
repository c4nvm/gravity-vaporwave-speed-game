# Sliding.gd
extends State

func enter():
	player.was_sliding = true
	# player.slide_cooldown_timer = 0.0 <-- THIS LINE HAS BEEN REMOVED
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
	player._update_debug_print(delta)
	if Input.is_action_just_pressed("jump"):
		_perform_slide_hop()

func _apply_slide_physics(delta):
	var slope_normal = player.get_floor_normal()
	if slope_normal != Vector3.ZERO and player.gravity_direction != Vector3.ZERO:
		var slope_dir = -slope_normal.slide(player.gravity_direction)

		if slope_dir.length() > 0.01:
			slope_dir = slope_dir.normalized()
			var horizontal_vel = player.velocity.slide(player.gravity_direction)
			var vertical_vel = player.velocity.project(player.gravity_direction)

			if slope_dir.dot(horizontal_vel.normalized()) > 0.1:
				horizontal_vel = horizontal_vel.lerp(Vector3.ZERO, player.slide_friction * delta)
			else:
				horizontal_vel += slope_dir * player.slide_downhill_accel * delta

			player.velocity = horizontal_vel + vertical_vel

func _perform_slide_hop():
	var horizontal_velocity = player.velocity - player.velocity.project(player.up_direction)
	horizontal_velocity *= player.slide_hop_boost
	var vertical_velocity = player.up_direction * (player.jump_force * player.slide_hop_jump_multiplier)
	player.velocity = horizontal_velocity + vertical_velocity
	player.state_machine.transition_to("Airborne")

func get_next_state() -> String:
	# The condition to enter sliding in Grounded.gd already doesn't check for the cooldown,
	# so we don't need to change anything there.
	if not Input.is_action_pressed("slide") or player.velocity.length() < player.slide_min_speed:
		return "Grounded"
	if not player.ground_ray.is_colliding():
		return "Airborne"
	return ""
