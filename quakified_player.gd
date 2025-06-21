extends CharacterBody3D

# Movement settings
const MAX_SLOPE_ANGLE := 40.0
@export var speed := 10.0
@export var jump_force := 10.0
@export var gravity := 30.0
@export var acceleration := 15.0
@export var deceleration := 20.0

# Mouse look settings
@export var mouse_sensitivity := 0.002
@export var max_look_angle := 89.0
@export var rotation_smoothness := 30.0

# Camera references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var push_raycast: RayCast3D = $DirectionRay

# Planet variables
var planet: Node3D
var is_on_planet := false
var gravity_direction := Vector3.DOWN

# Rotation variables
var mouse_rotation := Vector2.ZERO  # x = yaw, y = pitch

# Jump variables
var can_jump := true
var jump_cooldown := 0.5
var jump_timer := 0.0

# Debug variables
var debug_timer := 0.0
const DEBUG_PRINT_INTERVAL := 0.2  # Print every 0.2 seconds

func _ready():
	_setup_planet()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	max_look_angle = deg_to_rad(max_look_angle)

func _setup_planet():
	planet = get_parent().find_child("Planet3D", false) if get_parent() else null
	is_on_planet = planet != null
	if is_on_planet:
		floor_max_angle = deg_to_rad(MAX_SLOPE_ANGLE)

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		mouse_rotation.x -= event.relative.x * mouse_sensitivity
		mouse_rotation.x = wrapf(mouse_rotation.x, -PI, PI)
		mouse_rotation.y = clamp(mouse_rotation.y - event.relative.y * mouse_sensitivity, 
							   -max_look_angle, max_look_angle)
		camera_pivot.rotation.x = mouse_rotation.y

func _physics_process(delta):
	if is_on_planet and planet:
		_update_gravity()
		_handle_movement(delta)
		_apply_gravity(delta)
		_align_with_surface(delta)
		move_and_slide()
	else:
		_handle_movement(delta)
		move_and_slide()
	
	_handle_jump_cooldown(delta)
	_update_debug_print(delta)

func _update_debug_print(delta):
	debug_timer += delta
	if debug_timer >= DEBUG_PRINT_INTERVAL:
		debug_timer = 0.0
		_print_input_debug()

func _print_input_debug():
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	
	# Create a nice visual representation of the input
	var debug_str := "Input Debug:\n"
	debug_str += "WASD Input:\n"
	debug_str += "  W (Forward):  %+.2f\n" % input_dir.y
	debug_str += "  A (Left):     %+.2f\n" % -input_dir.x
	debug_str += "  S (Backward): %+.2f\n" % -input_dir.y
	debug_str += "  D (Right):    %+.2f\n" % input_dir.x
	
	# Add combined direction info
	debug_str += "\nCombined Direction:\n"
	debug_str += "  X: %+.2f  Y: %+.2f\n" % [input_dir.x, input_dir.y]
	
	# Add movement state info
	debug_str += "\nMovement State:\n"
	debug_str += "  On Floor: %s\n" % str(is_on_floor())
	debug_str += "  Velocity: %s (%.2f m/s)\n" % [str(velocity.normalized()), velocity.length()]
	
	if is_on_planet:
		debug_str += "  Gravity Dir: %s\n" % str(gravity_direction.normalized())
	
	debug_str += "  Forward Dir: %s\n" % str(-global_transform.basis.z.normalized())
	
	print(debug_str)

func _update_gravity():
	gravity_direction = (planet.global_transform.origin - global_transform.origin).normalized()
	up_direction = -gravity_direction

func _apply_gravity(delta):
	if not is_on_floor():
		velocity += gravity_direction * gravity * delta

func _handle_movement(delta):
	var input_dir := Input.get_vector("move_left", "move_right", "move_backward", "move_forward")
	var raycast_forward = -push_raycast.global_transform.basis.z.normalized()
	var raycast_right = push_raycast.global_transform.basis.x.normalized()
	
	if is_on_planet:
		raycast_forward = _safe_project(raycast_forward, gravity_direction)
		raycast_right = _safe_project(raycast_right, gravity_direction)
		
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity = velocity.lerp(move_dir * speed, acceleration * delta)
		
		if Input.is_action_just_pressed("jump") and is_on_floor() and can_jump:
			velocity += -gravity_direction * jump_force
			_start_jump_cooldown()
	else:
		var move_dir = (raycast_forward * input_dir.y + raycast_right * input_dir.x).normalized()
		velocity += move_dir * acceleration * delta
		velocity = velocity.lerp(Vector3.ZERO, deceleration * delta)
		
		if Input.is_action_just_pressed("jump") and can_jump:
			velocity += -transform.basis.y * jump_force * 0.5
			_start_jump_cooldown()

func _align_with_surface(delta: float):
	if not is_on_planet or not planet:
		return
	
	var new_up = -gravity_direction
	var horizontal_rot = Basis(new_up, mouse_rotation.x)
	var tilt_rot = Basis(Vector3.RIGHT, camera_pivot.rotation.x)
	
	var new_basis = horizontal_rot * tilt_rot
	new_basis = new_basis.orthonormalized()
	new_basis.y = new_up.normalized()
	new_basis.x = new_basis.y.cross(new_basis.z).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	
	transform.basis = transform.basis.slerp(new_basis, rotation_smoothness * delta)

func _safe_project(vector: Vector3, normal: Vector3) -> Vector3:
	var projected = vector - vector.project(normal)
	return projected.normalized() if projected.length() > 0.001 else \
		   Vector3(normal.y, normal.z, normal.x).cross(normal).normalized()

func _start_jump_cooldown():
	can_jump = false
	jump_timer = jump_cooldown

func _handle_jump_cooldown(delta):
	if not can_jump:
		jump_timer -= delta
		if jump_timer <= 0:
			can_jump = true
