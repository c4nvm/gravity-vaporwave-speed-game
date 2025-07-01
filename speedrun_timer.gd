# Timer.gd
# This script manages the core speedrunning timer logic.
# It should be placed in your level scene, often as a child of the Player node.

extends Node

# --- TIMER VARIABLES ---
var time_elapsed: float = 0.0
var timer_active: bool = false
var has_moved: bool = false

# --- NODE REFERENCES ---
var gameplay_ui: CanvasLayer
var player_node: CharacterBody3D # Or CharacterBody2D

func _ready() -> void:
	call_deferred("setup_references")

func setup_references() -> void:
	gameplay_ui = GameManager.gameplay_ui
	if not is_instance_valid(gameplay_ui):
		push_error("Timer.gd could not find a registered GameplayUI in GameManager.")
		return
	
	gameplay_ui.update_timer(0.0)
	gameplay_ui.display_best_time()

func register_player(p_node: CharacterBody3D) -> void:
	player_node = p_node

func _process(delta: float) -> void:
	if not has_moved and is_instance_valid(player_node) and player_node.velocity.length() > 0.1:
		has_moved = true
		start_timer()
		
	if timer_active:
		time_elapsed += delta
		if is_instance_valid(gameplay_ui):
			gameplay_ui.update_timer(time_elapsed)

func start_timer() -> void:
	if not timer_active:
		timer_active = true
		print("Timer started!")

func stop_timer() -> void:
	timer_active = false
	print("Timer stopped! Final time: ", time_elapsed)

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
	print("Timer has been manually reset.")
