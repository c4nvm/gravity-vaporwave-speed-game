# BouncePad.gd
extends Area3D

@export var bounce_force := 20.0  # Strength of the bounce
@export var rotation_speed := 5.0  # How quickly it aligns to the planet surface

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var direction_ray: RayCast3D = $DirectionRay

var nearest_planet: Node3D = null

func _ready():
	# Initialize the raycast direction (local space)
	direction_ray.target_position = Vector3(0, 20, 0)
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	

func _on_body_entered(body: Node3D):
	if body is CharacterBody3D:
		# Get the bounce direction in global space
		var bounce_direction = direction_ray.global_transform.basis.y.normalized()
		
		# Apply bounce force
		body.velocity += bounce_direction * bounce_force
