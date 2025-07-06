extends State

const COYOTE_TIME = 0.15 # seconds
var _coyote_timer = 0.0

func enter():

	var state_machine = GameManager.player_node.state_machine

	# Check if the player intended to slide upon landing.
	if player.wants_to_slide_on_land:
		# Reset the flag immediately.
		player.wants_to_slide_on_land = false
		# Check if conditions are still met for a slide.
		if player.velocity.length() >= player.slide_enter_speed:
			state_machine.transition_to("Sliding")
			# Return early to skip the rest of the Grounded state's enter logic.
			return

	# --- Existing enter logic ---
	player.was_sliding = false
	_coyote_timer = 0.0
	player.just_did_slide_hop = false

func process_physics(delta):
	player._pre_physics_process()

	if player.ground_ray.is_colliding():
		_coyote_timer = 0.0
	else:
		_coyote_timer += delta

	player._update_gravity()
	player._apply_gravity(delta)
	_handle_movement(delta)
	player._align_with_surface(delta)
	player.move_and_slide()
	player._stair_step_down()

func _handle_movement(delta):
	var input_dir : Vector2 = player.get_wish_direction()
	var raycast_forward = -player.direction_ray.global_transform.basis.z.normalized()
	var raycast_right = player.direction_ray.global_transform.basis.x.normalized()

	var vertical_velocity = player.velocity.project(player.up_direction)
	var horizontal_velocity = player.velocity - vertical_velocity

	raycast_forward = player._safe_project(raycast_forward, player.gravity_direction)
	raycast_right = player._safe_project(raycast_right, player.gravity_direction)
	player.wish_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()

	var target_h_velocity = player.wish_dir * player.speed
	var current_accel = player.acceleration
	var current_decel = player.deceleration
	var current_h_speed = horizontal_velocity.length()

	# --- MODIFIED: Apply strong braking when moving fast with no input ---
	if current_h_speed > player.speed and input_dir == Vector2.ZERO:
		# Instead of reducing deceleration, we now significantly increase it
		# to act as a brake and stop the unwanted sliding from a slide hop.
		# A value of 5.0 provides a firm but not instant stop. Adjust as needed.
		current_decel *= 5.0
	# --- END MODIFICATION ---

	if input_dir.length() > 0.01:
		horizontal_velocity = horizontal_velocity.lerp(target_h_velocity, current_accel * delta)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, current_decel * delta)

	# Check for jump input.
	if player.is_action_just_pressed_checked("jump"):
		var jump_velocity = player.up_direction * player.jump_force
		
		# Check for and apply the slam jump boost.
		if player.slam_boost_timer > 0:
			jump_velocity *= player.slam_jump_boost_multiplier
			# Consume the boost so it can't be used for a slide as well.
			player.slam_boost_timer = 0
			
		vertical_velocity = jump_velocity
		_coyote_timer = COYOTE_TIME + 0.1

	player.velocity = horizontal_velocity + vertical_velocity
	player._stair_step_up()

func get_next_state() -> String:
	if _coyote_timer > COYOTE_TIME:
		return "Airborne"
		
	# Check for slide transition.
	if player.ground_ray.is_colliding() and player.is_action_pressed_checked("slide") and player.slide_enabled and player.velocity.length() >= player.slide_enter_speed:
		if player.slide_ray.is_colliding():
			# Check for and apply the slam slide boost.
			if player.slam_boost_timer > 0:
				player.velocity *= player.slam_boost_multiplier
				# Consume the boost.
				player.slam_boost_timer = 0
			return "Sliding"
			
	return ""
