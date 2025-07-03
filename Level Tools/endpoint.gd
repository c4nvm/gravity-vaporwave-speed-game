# end_point.gd
extends Area3D

func _ready():
	# Connect the signal from this Area3D to this script's function
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	# Check if the node that entered is the player
	if body.is_in_group("player"):
		# Tell the GameManager that the level has been completed.
		GameManager.player_did_finish_level()
