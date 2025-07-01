extends Label

var player: CharacterBody3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	text = "Velocity = " + str(round(sqrt((player.velocity.length_squared()))))
