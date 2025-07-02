extends StaticBody3D

@export var active_color := Color.GREEN
@export var inactive_color := Color.RED
@export var linked_doors: Array[NodePath] = []

var is_active := false
var material: StandardMaterial3D

func _ready():
	# Get the mesh instance to change its material properties.
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance:
		var base_material := mesh_instance.get_active_material(0)
		if base_material:
			material = base_material.duplicate() as StandardMaterial3D
			mesh_instance.set_surface_override_material(0, material)
		else:
			push_warning("Switch has no base material on MeshInstance3D. Creating a new one.")
			material = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, material)
		_update_visuals()
	
	# --- FIX ---
	# Connect to the area_entered signal to detect other Area3D nodes.
	var area := get_node_or_null("Area3D") as Area3D
	if area:
		# Set this area to look for collisions on physics layer 4.
		# The bitwise left shift (1 << 3) corresponds to layer 4 (since layers are 0-indexed).
		area.collision_mask = 1 << 3 
		
		# Connect to the correct signal for Area3D-to-Area3D detection.
		area.area_entered.connect(_on_area_entered)

# --- FIX ---
# This function now correctly handles an Area3D entering the switch's trigger zone.
func _on_area_entered(area: Area3D):
	# Activate the switch if the entering area is in the "activation_area" group.
	if area.is_in_group("activation_area"):
		activate()

func activate():
	if is_active:
		return
	
	is_active = true
	_update_visuals()
	
	# Trigger all linked doors.
	for door_path in linked_doors:
		var door = get_node_or_null(door_path)
		if door and door.has_method("switch_activated"):
			door.switch_activated(self)

func deactivate():
	if not is_active:
		return
	
	is_active = false
	_update_visuals()
	
	# Notify all linked doors of deactivation.
	for door_path in linked_doors:
		var door = get_node_or_null(door_path)
		if door and door.has_method("switch_deactivated"):
			door.switch_deactivated(self)

func _update_visuals():
	# Update the albedo color based on the switch's active state.
	if material:
		material.albedo_color = active_color if is_active else inactive_color
