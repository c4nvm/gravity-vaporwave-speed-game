# posterize_time_controller.gd
extends Node

## The viewport that contains the outline effect.
@export var outline_viewport: SubViewport
## The number of frames to wait before updating the outline.
@export var update_interval: int = 12

var frame_counter: int = 0

func _process(delta: float) -> void:
	# Check if the viewport and interval are valid
	if not is_instance_valid(outline_viewport) or update_interval <= 0:
		return

	# Increment the frame counter
	frame_counter += 1

	# If the counter reaches the interval, trigger an update
	if frame_counter >= update_interval:
		# Reset the counter
		frame_counter = 0
		# Use the setter method to explicitly assign the enum value.
		outline_viewport.set_update_mode(SubViewport.UpdateMode.UPDATE_ONCE)
