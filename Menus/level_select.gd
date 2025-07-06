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
	
	# Create UI for each level
	for level_name in LEVELS:
		var level_path = LEVELS[level_name]
		var level_id = level_path.get_file().get_basename()
		var best_time = GameManager.load_best_time(level_id)
		
		# Main container for the entire row (button, time, collectibles)
		var row_container = HBoxContainer.new()
		row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Create level button
		var button = Button.new()
		button.text = level_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Button takes up available space
		button.pressed.connect(_on_level_button_pressed.bind(level_path))
		
		# Create best time label
		var time_label = Label.new()
		time_label.custom_minimum_size = Vector2(200, 0) # Give it a fixed width
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.text = _format_best_time(best_time)
		
		# --- Create container for collectible icons ---
		var collectibles_container = HBoxContainer.new()
		collectibles_container.alignment = HBoxContainer.ALIGNMENT_END
		# Add some spacing between icons
		collectibles_container.add_theme_constant_override("separation", 5)
		
		# Load the level scene as a resource to inspect its properties
		# without adding it to the main scene tree.
		var level_resource = load(level_path) as PackedScene
		if level_resource:
			var level_instance = level_resource.instantiate()
			
			# Check if the level's root node has our custom property.
			if level_instance and "total_collectibles_in_level" in level_instance:
				var total_collectibles = level_instance.total_collectibles_in_level
				var found_collectibles: Array = GameManager.load_collectibles(level_id)
				var num_found = found_collectibles.size()

				for i in range(total_collectibles):
					var panel = Panel.new() # Use a Panel for styling
					panel.custom_minimum_size = Vector2(25, 25)
					
					var style_box = StyleBoxFlat.new()
					style_box.border_width_bottom = 1
					style_box.border_width_top = 1
					style_box.border_width_left = 1
					style_box.border_width_right = 1
					style_box.border_color = Color(0.1, 0.1, 0.1)
					
					# Set color based on whether it's found
					if i < num_found:
						style_box.bg_color = Color.GOLD
					else:
						style_box.bg_color = Color(0.3, 0.3, 0.3) # Greyed out
					
					panel.add_theme_stylebox_override("panel", style_box)
					collectibles_container.add_child(panel)
			
			# IMPORTANT: Clean up the temporary instance immediately to avoid memory leaks.
			level_instance.queue_free()

		# Add all elements to the main row container
		row_container.add_child(button)
		row_container.add_child(time_label)
		row_container.add_child(collectibles_container)
		
		level_buttons_container.add_child(row_container)

func _on_level_button_pressed(level_path_to_load: String) -> void:
	GameManager.load_level(level_path_to_load)

func _format_best_time(time: float) -> String:
	if time <= 0.0:
		return "No record"
	
	var minutes := int(time / 60)
	var seconds := int(time) % 60
	var milliseconds := int(fmod(time, 1.0) * 1000)
	return "Best: %02d:%02d.%03d" % [minutes, seconds, milliseconds]
