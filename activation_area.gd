extends Area3D

func _ready():
	
	# Set collision layers/masks appropriately
	collision_layer = 1 << 3
	collision_mask = 1 << 3 
	
	# Set the shape (configure in inspector)
	var shape = $CollisionShape3D.shape
	if shape is SphereShape3D:
		shape.radius = 0.5 # Match your desired radius
