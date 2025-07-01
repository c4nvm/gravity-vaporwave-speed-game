# compass.gd
extends Node3D

# --- Node References ---

@onready var arrow: Node3D = $Arrow
@onready var x_axis: MeshInstance3D = $XAxis
@onready var y_axis: MeshInstance3D = $YAxis
@onready var z_axis: MeshInstance3D = $ZAxis

# --- Lifecycle Methods ---

func _ready() -> void:
	# Register this compass with the GameManager singleton.
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_compass(self)
	else:
		push_error("GameManager not found. Compass will not update.")


func _exit_tree() -> void:
	# Unregister the compass to prevent errors and memory leaks.
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").unregister_compass(self)


# --- Public Methods ---

## Updates the compass to align with the camera, global axes, and gravity.
## This function should be called every frame from your GameManager or Player script.
func update_compass(gravity_direction: Vector3, camera_global_basis: Basis) -> void:
	# 1. Rotate the entire compass housing to match the camera's orientation.
	global_transform.basis = camera_global_basis
	
	var parent_inverse_basis: Basis = camera_global_basis.inverse()

	# 2. Update the Guide Axes to point along the GLOBAL directions.
	# This code assumes all three axis models point along their local +Y axis.
	# We apply corrective rotations to the X and Z axes.
	
	# Y-Axis (Green): Points along +Y by default, so its desired global
	# orientation is the default.
	y_axis.basis = parent_inverse_basis * Basis.IDENTITY

	# X-Axis (Red): We rotate it from its default +Y direction to point along +X.
	# This corresponds to a -90 degree rotation around the global Z axis.
	var x_correction = Basis().rotated(Vector3.BACK, PI / 2)
	x_axis.basis = parent_inverse_basis * x_correction

	# Z-Axis (Blue): We rotate it from its default +Y direction to point along +Z.
	# This corresponds to a +90 degree rotation around the global X axis.
	var z_correction = Basis().rotated(Vector3.RIGHT, PI / 2)
	z_axis.basis = parent_inverse_basis * z_correction
	

	# 3. Update the Gravity Arrow to point down.
	# This logic is independent of the guide axes and remains the same.
	var target_y_axis: Vector3 = gravity_direction.normalized()
	var reference_up: Vector3 = camera_global_basis.y

	if abs(reference_up.dot(target_y_axis)) > 0.999:
		reference_up = -camera_global_basis.z

	var target_x_axis: Vector3 = reference_up.cross(target_y_axis).normalized()
	var target_z_axis: Vector3 = target_x_axis.cross(target_y_axis).normalized()
	
	var arrow_target_global_basis: Basis = Basis(target_x_axis, target_y_axis, target_z_axis)
	
	arrow.basis = parent_inverse_basis * arrow_target_global_basis
