# speedrun_timer.gd
extends Node
class_name SpeedrunTimer

var time_elapsed: float = 0.0
var timer_active: bool = false
var has_moved: bool = false

var gameplay_ui: CanvasLayer
var player_node: CharacterBody3D

func _ready() -> void:
	call_deferred("setup_references")

func setup_references() -> void:
	gameplay_ui = GameManager.gameplay_ui
	if not is_instance_valid(gameplay_ui):
		push_error("SpeedrunTimer: GameplayUI not found in GameManager")
		return
	
	gameplay_ui.update_timer(0.0)
	gameplay_ui.load_record_time() 

func register_player(p_node: CharacterBody3D) -> void:
	player_node = p_node
	reset_timer()

func _process(delta: float) -> void:
	# This block detects the very first movement of the player.
	if not has_moved and is_instance_valid(player_node) and player_node.velocity.length() > 0.1:
		has_moved = true
		
		GameManager.audio_manager.start_gameplay_audio()
		
		start_timer()
		
	if timer_active:
		time_elapsed += delta
		if is_instance_valid(gameplay_ui):
			gameplay_ui.update_timer(time_elapsed)

func start_timer() -> void:
	if not timer_active:
		timer_active = true
		if is_instance_valid(gameplay_ui):
			gameplay_ui.set_timer_visibility(Color.GREEN_YELLOW)

func stop_timer() -> void:
	timer_active = false
	
	GameManager.audio_manager.play_end_level_audio()

func player_finished_level() -> void:
	if not timer_active:
		return
	
	stop_timer()
	
	if is_instance_valid(gameplay_ui):
		gameplay_ui.show_final_time(time_elapsed)

func reset_timer() -> void:
	time_elapsed = 0.0
	timer_active = false
	has_moved = false
	if is_instance_valid(gameplay_ui):
		gameplay_ui.update_timer(0.0)
		gameplay_ui.set_timer_visibility(Color.LIGHT_BLUE)
