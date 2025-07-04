# In your gravity field Area3D script
extends Area3D

@export var gravity_strength := 9.8
@export var is_directional := true # Set this for directional gravity fields
@export var is_spawn := false # 

var bodies_inside := []

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body is CharacterBody3D: # Replace with your player class if needed
		if not bodies_inside.has(body):
			bodies_inside.append(body)

func _on_body_exited(body):
	if body is CharacterBody3D:
		if bodies_inside.has(body):
			bodies_inside.erase(body)

func is_body_inside(body) -> bool:
	return bodies_inside.has(body)
