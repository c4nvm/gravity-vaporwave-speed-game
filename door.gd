extends Node3D

@export var required_switches_to_open := 1
@export var stays_open := true
@export var open_speed := 2.0

var active_switches := 0
var is_open := false
var animation_player: AnimationPlayer

func _ready():
	animation_player = $AnimationPlayer
	# Ensure we have open and close animations
	if not animation_player.has_animation("open"):
		push_warning("Door missing 'open' animation")
	if not animation_player.has_animation("close"):
		push_warning("Door missing 'close' animation")

func switch_activated(switch: Node):
	active_switches += 1
	_check_door_state()

func switch_deactivated(switch: Node):
	if stays_open and is_open:
		return
		
	active_switches -= 1
	_check_door_state()

func _check_door_state():
	var should_open = active_switches >= required_switches_to_open
	
	if should_open and not is_open:
		_open_door()
	elif not should_open and is_open and not stays_open:
		_close_door()

func _open_door():
	if animation_player.has_animation("open"):
		animation_player.play("open", -1, open_speed)
	is_open = true

func _close_door():
	if animation_player.has_animation("close"):
		animation_player.play("close", -1, open_speed)
	is_open = false
