# level_select.gd
extends Control

# Define your levels here. Key is the display name, value is the scene file path.
const LEVELS = {
	"Test World 1": "res://test_world.tscn",
	"Test World 2": "res://test_world_2.tscn"
}

@onready var level_buttons_container: VBoxContainer = $LevelButtonsContainer
@onready var back_button: Button = $BackButton

func _ready() -> void:
	# Connect the back button's signal.
	back_button.pressed.connect(GameManager.goto_main_menu)
	
	# Clear any old buttons first (good practice).
	for child in level_buttons_container.get_children():
		child.queue_free()
	
	# Create a button for each level defined in our dictionary.
	for level_name in LEVELS:
		var level_path = LEVELS[level_name]
		
		var button = Button.new()
		button.text = level_name
		
		# Connect the button's pressed signal to the _on_level_button_pressed function.
		# We use .bind() to pass the level_path as an argument to the function.
		button.pressed.connect(_on_level_button_pressed.bind(level_path))
		
		level_buttons_container.add_child(button)

func _on_level_button_pressed(level_path_to_load: String) -> void:
	# Tell the Game Manager to load the level that was chosen.
	GameManager.load_level(level_path_to_load)
