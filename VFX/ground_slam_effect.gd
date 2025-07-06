# GroundSlamEffect.gd
# This script controls the shockwave effect.
# It should be attached to the root node of the GroundSlamEffect.tscn scene.
extends Node3D

# The MeshInstance3D node that holds the ring shape.
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

# Configurable properties for the effect.
# These will be set by the player script when the effect is created.
var target_radius: float = 5.0
var duration: float = 0.4

var tween: Tween

func _ready():
	# It's crucial to duplicate the material. If you don't, all active
	# shockwave effects will animate and fade out at the same time.
	# This code now correctly handles materials in either the override slot or the surface slot.
	var material_to_duplicate = mesh_instance.material_override
	if not material_to_duplicate:
		material_to_duplicate = mesh_instance.get_surface_override_material(0)

	if material_to_duplicate:
		var new_material = material_to_duplicate.duplicate()
		# Assign the duplicated material back to the correct slot.
		if mesh_instance.material_override:
			mesh_instance.material_override = new_material
		else:
			mesh_instance.set_surface_override_material(0, new_material)
	else:
		push_error("GroundSlamEffect has no material to duplicate. The effect will not be visible.")

	# Start the animation as soon as the scene is ready.
	_start_animation()

func _start_animation():
	# Ensure any previous tween is killed before starting a new one.
	if tween:
		tween.kill()

	# Create a new tween for the animation.
	tween = create_tween()

	# Get the material, whether it's an override or a surface material.
	var material: StandardMaterial3D
	if mesh_instance.material_override:
		material = mesh_instance.material_override as StandardMaterial3D
	else:
		material = mesh_instance.get_surface_override_material(0) as StandardMaterial3D

	# If we successfully found a material, set up the animations.
	if material:
		# The effect starts invisible and at zero size.
		scale = Vector3.ZERO
		material.albedo_color.a = 1.0 # Start fully visible

		# Animate the scale and alpha (fade) properties in parallel.
		# The scale expands from 0 to the target_radius.
		tween.parallel().tween_property(self, "scale", Vector3(target_radius, target_radius, target_radius), duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		
		# The alpha fades from 1.0 to 0.0.
		tween.parallel().tween_property(material, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		# If no material is found, we can't animate. Log an error and self-destruct to prevent issues.
		push_error("GroundSlamEffect has no material to animate. Destroying effect node.")
		queue_free()
		return # Exit the function to avoid connecting the 'finished' signal on an empty tween.

	# Connect the tween's finished signal to the queue_free method.
	# This automatically cleans up and removes the effect scene once the animation is complete.
	tween.finished.connect(queue_free)
