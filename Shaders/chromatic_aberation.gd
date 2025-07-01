# gameplay_overlay.gd
extends ColorRect

@onready var player: CharacterBody3D = get_tree().get_first_node_in_group("player")

const MIN_SPEED_FOR_EFFECT = 11.0
const MAX_SPEED_FOR_EFFECT = 20.0
const MIN_SPREAD = 0.001
const MAX_SPREAD = 0.03

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not material is ShaderMaterial:
		return

	var current_speed = player.velocity.length()

	var calculated_spread = remap(current_speed, MIN_SPEED_FOR_EFFECT, MAX_SPEED_FOR_EFFECT, MIN_SPREAD, MAX_SPREAD)
	
	calculated_spread = clamp(calculated_spread, MIN_SPREAD, MAX_SPREAD)
	
	material.set_shader_parameter("spread", calculated_spread)
