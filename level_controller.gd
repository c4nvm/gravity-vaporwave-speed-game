# Level.gd
extends Node3D

signal player_spawned(player_node)

@export var player_scene: PackedScene
@export var pause_menu_scene: PackedScene

# A unique name for this level, used for saving/loading times.
@export var level_name: String = "level_1" 

@onready var start_position: Marker3D = $StartPosition
@onready var endpoint: Area3D = $Endpoint
@onready var gameplay_ui: CanvasLayer = $GameUI

var is_timer_active: bool = false
var elapsed_time: float = 0.0
var player_instance: CharacterBody3D
var has_player_moved: bool = false

func _ready() -> void:
	# Instantiate the pause menu and set its process mode to 'Always'
	# so it can function while the game tree is paused.
	var pause_instance = pause_menu_scene.instantiate()
	pause_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_instance)

	# Wait a frame for the GameManager to be ready
	await get_tree().process_frame

	if not player_scene:
		push_error("Player scene not set in Level inspector")
		return

	spawn_player()
	endpoint.body_entered.connect(_on_endpoint_body_entered)
	
	if gameplay_ui:
		gameplay_ui.display_best_time()

func spawn_player() -> void:
	player_instance = player_scene.instantiate()
	player_instance.position = start_position.position
	player_instance.rotation = start_position.rotation
	add_child(player_instance)
	player_spawned.emit(player_instance)
	
	# Register the player with the GameManager
	GameManager.register_player(player_instance)

func _process(delta: float) -> void:
	if not is_instance_valid(player_instance):
		return
		
	# Start timer only when the player first moves
	if not has_player_moved and player_instance.velocity.length() > 0.1:
		has_player_moved = true
		start_timer()
		
	if is_timer_active:
		elapsed_time += delta
		update_ui_display()

func update_ui_display() -> void:
	if gameplay_ui:
		# Pass the raw float; the UI will handle formatting
		gameplay_ui.update_timer(elapsed_time)
		gameplay_ui.update_debug("Speed: %d" % player_instance.velocity.length())

func start_timer() -> void:
	elapsed_time = 0.0
	is_timer_active = true
	if gameplay_ui:
		gameplay_ui.set_timer_visibility(Color.GREEN_YELLOW)

func stop_timer() -> void:
	is_timer_active = false

func _on_endpoint_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		stop_timer()
		if gameplay_ui:
			gameplay_ui.show_final_time(elapsed_time)
		
		# Prevent re-triggering
		endpoint.monitoring = false 
		
		await get_tree().create_timer(3.0).timeout
		GameManager.goto_level_select()
