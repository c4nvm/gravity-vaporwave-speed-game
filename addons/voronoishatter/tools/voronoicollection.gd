## A simple wrapper node that contains the fractured meshes generated from a VoronoiShatter node.
@tool
extends Node3D

class_name VoronoiCollection

@export_tool_button("Create Rigid Bodies", "RigidBody3D") var create_rigid_bodies_callback = create_rigid_bodies

func create_rigid_bodies():
	for child in get_children():
		if is_instance_of(child, MeshInstance3D):
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.create_convex_collision(true, true)

			for maybe_static in mesh_instance.get_children():
				if is_instance_of(maybe_static, StaticBody3D):
					var static_body: StaticBody3D = maybe_static
					var rigid_body = RigidBody3D.new()
					rigid_body.name = "Rigid_" + mesh_instance.name
					
					static_body.replace_by(rigid_body)
					rigid_body.reparent(self)
					mesh_instance.reparent(rigid_body)
					mesh_instance.scale = rigid_body.scale
					rigid_body.scale = Vector3.ONE
					rigid_body.add_to_group("grabbable")

## Applies a variable force to all child RigidBody3D nodes based on their distance to the player.
## The closer the object, the stronger the force.

# The strongest force applied when the object is at or closer than `min_distance_effect`.
@export var max_force: float = 150.0
# The weakest force applied when the object is at or farther than `max_distance_effect`.
@export var min_force: float = 5.0
# The distance at which the force starts to increase from `min_force`.
@export var max_distance_effect: float = 25.0
# The distance at which the force reaches `max_force`.
@export var min_distance_effect: float = 1.0


func _ready() -> void:
	# Ensure the player node is valid before proceeding.
	if not GameManager.player_node:
		push_error("Player node not found in GameManager. Cannot apply force.")
		return

	var player = GameManager.player_node

	# Iterate through all children of this node.
	for body in get_children():
		# Check if the child is a 3D rigid body. The 'is' keyword is a modern, clean way to type-check.
		if body is RigidBody3D:
			body.add_to_group("grabbable")

			# 1. Calculate the distance from the rigid body to the player.
			var distance: float = body.global_position.distance_to(player.global_position)

			# 2. Map the distance to a force magnitude.
			# As 'distance' decreases from 'max_distance_effect' to 'min_distance_effect',
			# the returned 'force_magnitude' will increase from 'min_force' to 'max_force'.
			var force_magnitude: float = remap(distance, max_distance_effect, min_distance_effect, min_force, max_force)

			# 3. Clamp the value to ensure the force doesn't exceed the defined min/max bounds.
			# This handles cases where the object is outside the min/max distance effect range.
			force_magnitude = clamp(force_magnitude, min_force, max_force)

			# 4. Define the force direction (maintaining the original script's upward direction).
			var force_direction: Vector3 = -player.up_direction

			# 5. Apply the final calculated force.
			# We use apply_central_force() to apply force without causing the object to rotate.
			body.apply_central_force(force_direction * force_magnitude)
