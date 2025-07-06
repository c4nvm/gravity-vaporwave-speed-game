# GroundSlam.gd
extends State

@onready var state_machine = $".."
var original_slam_velocity: Vector3

func enter():
	"""
	Called when entering the GroundSlam state.
	Calculates and applies the initial slam velocity. The horizontal velocity
	is dampened, and a strong downward force is applied.
	"""
	var vertical_velocity = player.velocity.project(player.up_direction)
	var horizontal_velocity = player.velocity - vertical_velocity
	original_slam_velocity = (horizontal_velocity * player.slam_horizontal_dampening) + (player.up_direction * -1 * player.slam_force)
	player.velocity = original_slam_velocity

func process_physics(delta):
	"""
	Handles the physics updates during the slam.
	"""
	player._pre_physics_process()
	player._apply_gravity(delta)
	
	# Maintain a strong downward velocity to ensure the slam feels forceful.
	# This prevents gravity from slowly overriding the initial slam force.
	var current_downward_velocity = player.velocity.dot(player.up_direction * -1)
	if current_downward_velocity < player.slam_force:
		player.velocity.y = original_slam_velocity.y

	player.move_and_slide()
	
	# Check if the player has landed on a surface after moving.
	if player.is_on_floor():
		# IMPACT!
		# The slam has concluded. Trigger the main impact function on the player.
		# This single function is responsible for the AOE damage check, breaking
		# objects, playing VFX, and handling audio.
		# This correctly breaks ALL objects in the radius, not just the one underfoot.
		if player.has_method("perform_ground_slam_impact"):
			player.perform_ground_slam_impact()
			
		# The slam is over. Transition the player to the Grounded state.
		state_machine.transition_to("Grounded")
		return # Exit the function, as we've changed state.
