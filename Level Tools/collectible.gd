# collectible.gd
extends Area3D

## A unique identifier for this collectible within its level (e.g., "coin_1", "secret_gem_alpha").
@export var collectible_id: String

@export_group("Animation")
## How fast the collectible rotates, in full rotations per second.
@export var rotation_speed: float = 0.5
## How high and low the collectible will hover from its starting point.
@export var hover_amplitude: float = 0.15
## How many up-and-down cycles the collectible completes per second.
@export var hover_frequency: float = 1.0

@export_group("State")
## The material to apply when the collectible has already been found.
@export var collected_material: Material

# This expects a child node named "MeshInstance3D". If yours has a different name, change it here.
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _time: float = 0.0
var _initial_position: Vector3
var is_collected := false

func _ready() -> void:
	# Add to a group so the LevelController can find all collectibles.
	add_to_group("collectible_item")
	
	# Store the starting position to prevent animation drift.
	_initial_position = global_position
	
	# Connect the body_entered signal to our collection logic.
	body_entered.connect(_on_body_entered)
	
	# Check if the required nodes were found.
	if not mesh:
		push_error("Collectible is missing its MeshInstance3D child node!")
	if not collision_shape:
		push_error("Collectible is missing its CollisionShape3D child node!")

func _process(delta: float) -> void:
	_time += delta

	# --- Rotation ---
	if is_instance_valid(mesh):
		mesh.rotate_y(rotation_speed * TAU * delta)

	# --- Hovering ---
	var hover_offset = sin(_time * hover_frequency * TAU) * hover_amplitude
	global_position = _initial_position + Vector3.UP * hover_offset

## Changes the item's appearance and disables it. Called by the LevelController.
func set_as_collected():
	is_collected = true
	
	# Apply the special material if one is assigned.
	if collected_material and is_instance_valid(mesh):
		mesh.set_surface_override_material(0, collected_material)
		$GPUParticles3D.emitting = false
	
	# Disable collision so it can't be picked up again.
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true
	
	# Disconnect the signal as a final measure.
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Ignore all interactions if already collected or if not the player.
	if is_collected or not body.is_in_group("player"):
		return
		
	if collectible_id.is_empty():
		push_error("Collectible is missing its unique 'collectible_id' in the inspector!")
		return
			
	print("Player collected item: %s" % collectible_id)
	
	# Tell the GameManager to save this collectible as found.
	GameManager.save_collectible(GameManager.current_level_id, collectible_id)

	# Play a sound effect.
	if GameManager.audio_manager and GameManager.audio_manager.has_method("play_sfx"):
		GameManager.audio_manager.play_sfx("CollectiblePickup")

	# The collectible has been collected, so remove it from the level.
	queue_free()
