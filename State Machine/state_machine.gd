# StateMachine.gd
extends Node

signal state_changed(new_state_name: String)

var states: Dictionary = {}
var current_state: Node
var player: CharacterBody3D

func init(player_controller: CharacterBody3D):
	player = player_controller
	for child in get_children():
		if child is Node:
			states[child.name.to_lower()] = child
			child.player = player
	if states.has("grounded"):
		current_state = states["grounded"]
		current_state.enter()
		state_changed.emit(current_state.name)

func process_input(event: InputEvent):
	if current_state:
		current_state.process_input(event)

func process_frame(delta: float):
	if current_state:
		current_state.process_frame(delta)

func process_physics(delta: float):
	if current_state:
		current_state.process_physics(delta)
		var next_state_name = current_state.get_next_state()
		if next_state_name:
			transition_to(next_state_name)

func transition_to(state_name: String):
	var new_state = states.get(state_name.to_lower())
	if not new_state or new_state == current_state:
		return
		
	if current_state:
		current_state.exit()
		
	current_state = new_state
	current_state.enter()
	state_changed.emit(new_state.name)
