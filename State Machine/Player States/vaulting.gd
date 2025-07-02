extends State

# Note: The vaulting logic has been integrated into the Airborne state.
# This script is a placeholder in case you want to expand vaulting into a more complex state.
# For now, it immediately transitions to the Airborne state.

func enter():
	player.state_machine.transition_to("Airborne")
