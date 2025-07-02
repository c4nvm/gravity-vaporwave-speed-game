extends State

const COYOTE_TIME = 0.15 # seconds
var _coyote_timer = 0.0

func enter():
	player.was_sliding = false
	_coyote_timer = 0.0

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
	player._update_debug_print(delta)

func _handle_movement(delta):
	# Get input from the player script
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

	if current_h_speed > player.speed and input_dir == Vector2.ZERO:
		current_decel *= player.high_speed_decel_multiplier

	if input_dir.length() > 0.01:
		horizontal_velocity = horizontal_velocity.lerp(target_h_velocity, current_accel * delta)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, current_decel * delta)

	# Check for jump via the player script
	if player.is_action_just_pressed_checked("jump"):
		vertical_velocity = player.up_direction * player.jump_force
		_coyote_timer = COYOTE_TIME + 0.1

	player.velocity = horizontal_velocity + vertical_velocity
	player._stair_step_up()

func get_next_state() -> String:
	if _coyote_timer > COYOTE_TIME:
		return "Airborne"
		
	# Check for slide via the player script
	if player.ground_ray.is_colliding() and player.is_action_pressed_checked("slide") and player.slide_enabled and player.velocity.length() >= player.slide_enter_speed:
		if player.slide_ray.is_colliding():
			return "Sliding"
			
	return ""
