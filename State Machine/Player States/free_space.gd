# FreeSpace.gd
extends State

func enter():
	player._enter_free_space_mode()
	if player.hook_controller:
		player.hook_controller.set_free_space_mode(true)

func exit():
	player._enter_planetary_mode()
	if player.hook_controller:
		player.hook_controller.set_free_space_mode(false)


func process_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_pressed("roll_left"):
			player.free_space_roll += player.free_space_roll_speed * get_process_delta_time()
		if Input.is_action_pressed("roll_right"):
			player.free_space_roll -= player.free_space_roll_speed * get_process_delta_time()

func process_physics(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var vertical_input := Input.get_action_strength("jump") - Input.get_action_strength("slide")
	var move_dir = Vector3(input_dir.x, vertical_input, -input_dir.y).normalized()
	var target_velocity = move_dir * player.free_space_max_speed
	var is_hook_pulling = player.hook_controller and player.hook_controller.is_hook_active()

	if is_hook_pulling:
		var hook_pull = player.hook_controller.get_hook_pull_vector(delta)
		player.velocity += hook_pull
		player.free_space_velocity = player.free_space_velocity.lerp(target_velocity * 0.3, player.free_space_acceleration * delta)
	else:
		player.free_space_velocity = player.free_space_velocity.lerp(target_velocity, player.free_space_acceleration * delta)
		if move_dir.length_squared() < 0.1:
			player.free_space_velocity = player.free_space_velocity.lerp(Vector3.ZERO, player.free_space_deceleration * delta)

	player.free_space_velocity *= player.free_space_momentum_gain
	var target_basis = Basis()
	target_basis = target_basis.rotated(Vector3.RIGHT, player.free_space_rotation.x)
	target_basis = target_basis.rotated(Vector3.UP, player.free_space_rotation.y)
	target_basis = target_basis.rotated(Vector3.BACK, player.free_space_roll)

	player.transform.basis = player.transform.basis.slerp(target_basis, player.free_space_rotation_speed * delta).orthonormalized()
	player.free_space_roll *= player.free_space_roll_decay

	_update_free_space_camera(input_dir, vertical_input, delta)

	if is_hook_pulling:
		player.velocity += player.transform.basis * player.free_space_velocity
	else:
		player.velocity = player.transform.basis * player.free_space_velocity
	player.move_and_slide()

func _update_free_space_camera(input_dir: Vector2, vertical_input: float, delta: float):
	var camera_target_position = Vector3.ZERO
	if abs(vertical_input) > 0.1:
		camera_target_position.y = vertical_input * 0.5
	if abs(input_dir.x) > 0.1:
		camera_target_position.x = input_dir.x * 0.5
	if abs(input_dir.y) > 0.1:
		camera_target_position.z = input_dir.y * 0.3

	player.free_space_camera_offset = player.free_space_camera_offset.lerp(camera_target_position, player.free_space_camera_lerp_speed * delta)
	player.camera.position = player.free_space_camera_offset

func get_next_state() -> String:
	return ""
