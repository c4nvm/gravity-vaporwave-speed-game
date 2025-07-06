# breakable_glass.gd
extends StaticBody3D

## Assign the scene that contains your pre-fractured RigidBody pieces.
@export var fractured_scene: PackedScene

# No need to get the original mesh if we are just deleting the whole object.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var is_broken := false

## This function is called by the AdvancedCharacterController during a ground slam.
func break_object(impact_position: Vector3, player_velocity: Vector3):
	# Prevent the object from breaking multiple times.
	if is_broken:
		return

	is_broken = true

	# Check if the fractured scene has been assigned in the editor.
	if not fractured_scene:
		push_warning("Fractured Scene not set! Please assign a PackedScene.")
		return

	# 1. Instantiate the scene containing all the fractured pieces.
	var shards_instance = fractured_scene.instantiate()
	
	# Add the new instance to the main scene tree.
	# We use get_parent() to ensure it's added at the same level as the original object.
	get_parent().add_child(shards_instance)
	
	# Position the new shards exactly where the original object was.
	shards_instance.global_transform = self.global_transform

	# 2. Make the pieces explode outwards from the impact point.
	for piece in shards_instance.get_children():
		if piece is RigidBody3D:
			# Calculate a direction from the impact point to the piece.
			var direction = (piece.global_position - impact_position).normalized()
			# Add some upward lift to the explosion.
			direction += Vector3.DOWN * 0.5
			
			# The force is based on the player's slam velocity.
			var strength = player_velocity.length() * 0.2
			
			piece.apply_central_impulse(direction.normalized() * strength)

	# Optional: Play a breaking sound effect here.
	# if GameManager.audio_manager:
	#     GameManager.audio_manager.play_sfx("GlassBreak")

	# 3. Remove the original, unbroken object from the game.
	queue_free()
