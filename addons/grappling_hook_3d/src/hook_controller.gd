class_name HookController
extends Node
## Manages hook mechanics including launching, retracting, and player movement effects

@export_category("Hook Controller")
@export_group("Required Settings")
@export var hook_raycast: RayCast3D
@export var player_body: CharacterBody3D
@export var launch_action_name: String = "grapple"
@export var retract_action_name: String = "grapple"
@export_group("Optional Settings")
@export var pull_speed: float = 15.0
@export var max_hook_distance: float = 30.0
@export var rope_tension: float = 0.5 # How much the rope resists stretching
@export var hook_source: Node3D
@export_group("Advanced Settings")
@export var hook_scene: PackedScene = preload("res://addons/grappling_hook_3d/src/hook.tscn")

enum HookState { INACTIVE, LAUNCHING, ATTACHED, RETRACTING }

var current_state: HookState = HookState.INACTIVE
var hook_instance: Node3D = null
var hook_target_position: Vector3 = Vector3.ZERO
var hook_target_normal: Vector3 = Vector3.ZERO
var hook_target_body: PhysicsBody3D = null
var hook_distance: float = 0.0
var launch_velocity: Vector3 = Vector3.ZERO

signal hook_launched()
signal hook_attached(body: PhysicsBody3D)
signal hook_detached()
signal hook_failed()
signal gravity_override_changed(should_override: bool)

func _ready():
	hook_raycast.target_position = Vector3(0, 0, -max_hook_distance)

func _physics_process(delta: float) -> void:
	match current_state:
		HookState.LAUNCHING:
			_process_launching(delta)
		HookState.ATTACHED:
			_process_attached(delta)
		HookState.RETRACTING:
			_process_retracting(delta)
	
	if Input.is_action_just_pressed(launch_action_name):
		if current_state == HookState.INACTIVE:
			_launch_hook()
	if Input.is_action_just_released(launch_action_name):
		_retract_hook()

func _launch_hook() -> void:
	if not hook_raycast.is_colliding():
		hook_failed.emit()
		return
	
	var collision_point = hook_raycast.get_collision_point()
	var collision_normal = hook_raycast.get_collision_normal()
	var collider = hook_raycast.get_collider()
	
	hook_target_position = collision_point
	hook_target_normal = collision_normal
	hook_target_body = collider
	hook_distance = player_body.global_position.distance_to(hook_target_position)
	
	# Create hook visual
	hook_instance = hook_scene.instantiate()
	add_child(hook_instance)
	
	# Calculate initial velocity based on player's current movement
	launch_velocity = player_body.velocity *  50
	
	current_state = HookState.LAUNCHING
	hook_launched.emit()

func _process_launching(delta: float) -> void:
		_attach_hook()

func _attach_hook() -> void:
	current_state = HookState.ATTACHED
	hook_attached.emit(hook_target_body)
	gravity_override_changed.emit(true) # Disable increased gravity
	
	if hook_target_body is PhysicsBody3D:
		hook_target_body.tree_exiting.connect(_on_hook_target_exited)


func _process_attached(delta: float) -> void:
	# Update hook target position if attached to moving body
	if hook_target_body:
		hook_target_position = hook_target_body.to_global(hook_target_body.to_local(hook_target_position))
	
	# Calculate pull direction
	var pull_direction = (hook_target_position - player_body.global_position).normalized()
	var current_distance = player_body.global_position.distance_to(hook_target_position)
	
	# Apply force based on distance (more force when rope is stretched)
	var distance_ratio = clamp(current_distance / hook_distance, 1.0, 2.0)
	var pull_force = pull_direction * pull_speed * distance_ratio
	
	# Add some upward force to help with movement
	if player_body.is_on_floor():
		pull_force += Vector3.UP * pull_speed * 0.5
	
	player_body.velocity += pull_force * delta
	
	# Update rope visual
	if hook_instance:
		var source_pos = hook_source.global_position if hook_source else player_body.global_position
		hook_instance.extend_from_to(source_pos, hook_target_position, hook_target_normal)

func _retract_hook() -> void:
	_cleanup_hook()  # Skip retraction state entirely
	hook_detached.emit()

func _process_retracting(delta: float) -> void:
	if hook_instance:
		# Animate hook returning to player
		var target_pos = hook_source.global_position if hook_source else player_body.global_position
		hook_instance.global_position = hook_instance.global_position.lerp(target_pos, delta * 15)
		
		# Check if hook returned to player
		if hook_instance.global_position.distance_squared_to(target_pos) < 0.1:
			_cleanup_hook()

func _cleanup_hook() -> void:
	if hook_instance:
		hook_instance.queue_free()
		hook_instance = null
	
	if hook_target_body and hook_target_body.tree_exiting.is_connected(_on_hook_target_exited):
		hook_target_body.tree_exiting.disconnect(_on_hook_target_exited)
	
	hook_target_body = null
	current_state = HookState.INACTIVE
	gravity_override_changed.emit(false) # Restore normal gravity

func _on_hook_target_exited() -> void:
	# If the hooked object is deleted, retract the hook
	_retract_hook()

func is_hook_active() -> bool:
	return current_state != HookState.INACTIVE

func get_hook_direction() -> Vector3:
	if current_state == HookState.INACTIVE:
		return Vector3.ZERO
	return (hook_target_position - player_body.global_position).normalized()
