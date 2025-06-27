# State.gd
class_name State
extends Node

var player: CharacterBody3D

func enter():
	pass

func exit():
	pass

func process_input(event: InputEvent):
	pass

func process_frame(delta: float):
	pass

func process_physics(delta: float):
	pass

func get_next_state() -> String:
	return ""
