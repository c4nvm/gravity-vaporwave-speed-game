# speedrun_timer.gd
extends Node
class_name SpeedrunTimer

var time_elapsed: float = 0.0
var timer_active: bool = false

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
	
	# Register the timer with the manager
	GameManager.register_speedrun_timer(self)
	
	# Connect to the GameManager's signal to start the timer.
	GameManager.gameplay_started.connect(start_timer)

func register_player(p_node: CharacterBody3D) -> void:
	player_node = p_node
	reset_timer()

func _process(delta: float) -> void:
	# This function now only needs to increment the timer when it's active.
	if timer_active:
		time_elapsed += delta
		if is_instance_valid(gameplay_ui):
			gameplay_ui.update_timer(time_elapsed)

func start_timer() -> void:
	# This function is now called by the GameManager.gameplay_started signal.
	if not timer_active:
		timer_active = true
		if is_instance_valid(gameplay_ui):
			gameplay_ui.set_timer_visibility(Color.GREEN_YELLOW)

func stop_timer() -> void:
	timer_active = false

func player_finished_level() -> void:
	if not timer_active:
		return
	
	stop_timer()
	
	# Tell the GameManager to handle the end-of-level logic.
	GameManager.save_best_time(time_elapsed)
	
	if is_instance_valid(gameplay_ui):
		gameplay_ui.show_final_time(time_elapsed)

func reset_timer() -> void:
	time_elapsed = 0.0
	timer_active = false
	if is_instance_valid(gameplay_ui):
		gameplay_ui.update_timer(0.0)
		gameplay_ui.set_timer_visibility(Color.LIGHT_BLUE)
