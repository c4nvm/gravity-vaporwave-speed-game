extends Node3D

@export var player_scene: PackedScene = preload("res://player.tscn")
@export var pause_menu_scene: PackedScene = preload("res://Menus/pause_menu.tscn")
@export var soundtrack_profile: String = "default"
## Set this in the inspector for each level. It tells the level select screen how many icons to draw.
@export var total_collectibles_in_level: int = 0

@onready var start_position: Marker3D = $StartPosition
@onready var endpoint: Area3D = $Endpoint
@onready var speedrun_timer: Node = $SpeedrunTimer

var player_instance: CharacterBody3D

func _ready() -> void:
	# Set soundtrack through GameManager
	GameManager.audio_manager.set_soundtrack_profile(soundtrack_profile)
	
	# Instantiate pause menu
	var pause_instance = pause_menu_scene.instantiate()
	pause_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_instance)
	GameManager.register_pause_menu(pause_instance)
	
	# Update collectibles that have already been found.
	_initialize_collectibles()
	
	await get_tree().process_frame

	if not player_scene:
		push_error("Player scene not set in LevelController inspector")
		return

	spawn_player()
	endpoint.body_entered.connect(_on_endpoint_body_entered)
	
	# Tell the GameManager to start the fade-in using the duration from the player.
	GameManager.start_level_fade_in(player_instance.level_start_fade_duration)


func _initialize_collectibles() -> void:
	# Get the ID of the current level scene file.
	var level_id = get_tree().current_scene.scene_file_path.get_file().get_basename()
	
	# Load the list of collectibles that have already been found in this level.
	var found_collectibles = GameManager.load_collectibles(level_id)
	
	if found_collectibles.is_empty():
		return

	var collectibles_in_scene = get_tree().get_nodes_in_group("collectible_item")
	
	for item in collectibles_in_scene:
		if "collectible_id" in item:
			if item.collectible_id in found_collectibles:
				# This item was already found. Call its function to change its state.
				if item.has_method("set_as_collected"):
					item.set_as_collected()


func spawn_player() -> void:
	player_instance = player_scene.instantiate()
	player_instance.position = start_position.position
	player_instance.rotation = start_position.rotation
	add_child(player_instance)
	
	GameManager.register_player(player_instance)
	if speedrun_timer:
		speedrun_timer.register_player(player_instance)

func _on_endpoint_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if speedrun_timer:
			speedrun_timer.player_finished_level()
		
		endpoint.set_deferred("monitoring", false)
		GameManager.update_mouse_mode(false)
		
		await get_tree().create_timer(3.0).timeout
		GameManager.goto_level_select()
