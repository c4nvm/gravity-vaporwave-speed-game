# level_select.gd
extends Control

const LEVELS = {
	"Test World 1": "res://test_world.tscn",
	"Test World 2": "res://test_world_2.tscn",
	"Test World 3": "res://test_world_3.tscn"
}

@onready var level_buttons_container: VBoxContainer = $LevelButtonsContainer
@onready var back_button: Button = $BackButton

func _ready() -> void:
	back_button.pressed.connect(GameManager.goto_main_menu)
	
	# Clear existing buttons
	for child in level_buttons_container.get_children():
		child.queue_free()
	
	# Create buttons for each level
	for level_name in LEVELS:
		var level_path = LEVELS[level_name]
		var level_id = level_path.get_file().get_basename()
		var best_time = GameManager.load_best_time(level_id)
		
		# Create container for button and time label
		var button_container = HBoxContainer.new()
		button_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Create level button
		var button = Button.new()
		button.text = level_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_level_button_pressed.bind(level_path))
		
		# Create best time label
		var time_label = Label.new()
		time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		time_label.text = _format_best_time(best_time)
		
		# Add elements to container
		button_container.add_child(button)
		button_container.add_child(time_label)
		level_buttons_container.add_child(button_container)

func _on_level_button_pressed(level_path_to_load: String) -> void:
	GameManager.load_level(level_path_to_load)

func _format_best_time(time: float) -> String:
	if time <= 0.0:
		return "No record"
	
	var minutes := int(time / 60)
	var seconds := int(time) % 60
	var milliseconds := int(fmod(time, 1.0) * 1000)
	return "Best: %02d:%02d.%03d" % [minutes, seconds, milliseconds]
