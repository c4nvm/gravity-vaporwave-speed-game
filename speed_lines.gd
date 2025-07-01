extends ColorRect

@onready var player: CharacterBody3D = get_tree().get_first_node_in_group("player")

const MIN_SPEED_FOR_EFFECT = 11.0
const MAX_SPEED_FOR_EFFECT = 30.0
const MIN_EFFECT_POWER = 0.0
const MAX_EFFECT_POWER = 1.0
const LERP_SPEED = 5.0

var current_effect_power: float = 0.0

func _process(delta: float) -> void:
	if not material is ShaderMaterial:
		return

	var target_power: float = 0.0

	if is_instance_valid(player):
		var current_speed = player.velocity.length()
		target_power = remap(current_speed, MIN_SPEED_FOR_EFFECT, MAX_SPEED_FOR_EFFECT, MIN_EFFECT_POWER, MAX_EFFECT_POWER)
		target_power = clamp(target_power, MIN_EFFECT_POWER, MAX_EFFECT_POWER)
	
	current_effect_power = lerp(current_effect_power, target_power, LERP_SPEED * delta)

	material.set_shader_parameter("effect_power", current_effect_power)
