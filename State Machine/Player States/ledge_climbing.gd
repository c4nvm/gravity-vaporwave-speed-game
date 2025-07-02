extends State

var tween: Tween

func enter():
	player.velocity = Vector3.ZERO
	var player_height = player.player_collider.shape.height
	var player_radius = player.player_collider.shape.radius if player.player_collider.shape is CapsuleShape3D else 0.5

	var wall_point = player.ledge_detector_ray.get_collision_point()
	var wall_normal = player.ledge_detector_ray.get_collision_normal()

	var hang_pos = wall_point + wall_normal * player_radius + player.gravity_direction * (player_height / 2.0 - 0.2)
	var final_pos = wall_point + (-player.gravity_direction * (player_height / 2.0 + 0.2))

	tween = create_tween()
	tween.set_parallel(false)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(player, "global_position", hang_pos, player.ledge_climb_duration * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(player, "global_position", final_pos, player.ledge_climb_duration * 0.6).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_climb_finished)

func _on_climb_finished():
	player.ledge_climb_cooldown_timer = player.ledge_climb_cooldown
	player.is_grounded = true
	player.was_grounded = true
	player.state_machine.transition_to("Grounded")

func exit():
	if tween and tween.is_running():
		tween.kill()
