# StateMachine.gd
extends Node

signal state_changed(new_state_name: String)

var states: Dictionary = {}
var current_state: Node
var player: CharacterBody3D

# Initialize the state machine with player reference and optional initial state
func init(player_controller: CharacterBody3D, initial_state_name: String = "grounded"):
	player = player_controller
	
	# Register all child nodes as states
	for child in get_children():
		if child is Node:
			var state_name = child.name.to_lower()
			states[state_name] = child
			child.player = player  # Pass player reference to each state
	
	# Set initial state
	if states.has(initial_state_name.to_lower()):
		transition_to(initial_state_name)
	else:
		push_error("Initial state '%s' not found in state machine. Available states: %s" % [
			initial_state_name,
			states.keys()
		])
		# Fallback to first available state if specified state doesn't exist
		if states.size() > 0:
			transition_to(states.keys()[0])

# Handle input processing for current state
func process_input(event: InputEvent):
	if current_state and current_state.has_method("process_input"):
		current_state.process_input(event)

# Handle frame processing for current state
func process_frame(delta: float):
	if current_state and current_state.has_method("process_frame"):
		current_state.process_frame(delta)

# Handle physics processing for current state
func process_physics(delta: float):
	if current_state and current_state.has_method("process_physics"):
		current_state.process_physics(delta)
		
		# Check for state transitions
		var next_state_name = current_state.get_next_state()
		if next_state_name:
			transition_to(next_state_name)

# Transition to a new state
func transition_to(state_name: String):
	var new_state = states.get(state_name.to_lower())
	
	# Validate transition
	if not new_state:
		push_error("State '%s' not found in state machine" % state_name)
		return
	
	if new_state == current_state:
		return  # Already in this state
	
	# Exit current state
	if current_state and current_state.has_method("exit"):
		current_state.exit()
	
	# Enter new state
	current_state = new_state
	if current_state.has_method("enter"):
		current_state.enter()
	
	# Emit signal with the new state name
	state_changed.emit(current_state.name)

# Helper function to get current state name
func get_current_state_name() -> String:
	return current_state.name if current_state else ""
