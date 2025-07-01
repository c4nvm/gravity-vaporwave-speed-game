# GameplayUI.gd
extends CanvasLayer

## Gameplay UI
## Displays timer, best times, and other in-game info.

@onready var timer_label: Label = %TimerLabel
@onready var best_time_label: Label = %BestTimeLabel
@onready var debug_label: Label = %DebugLabel

var current_level: String = ""

func _ready() -> void:
	GameManager.register_gameplay_ui(self)
	GameManager.level_loaded.connect(_on_level_loaded)
	set_timer_visibility(Color.LIGHT_BLUE)

func _on_level_loaded(level_path: String) -> void:
	# Store the basename of the level file (e.g., "level_1")
	current_level = level_path.get_file().get_basename()
	display_best_time()

func update_timer(time_in_seconds: float) -> void:
	if timer_label:
		timer_label.text = format_time(time_in_seconds)

func update_debug(debug_string: String) -> void:
	if debug_label:
		debug_label.text = debug_string

func set_timer_visibility(color: Color) -> void:
	if timer_label:
		timer_label.add_theme_color_override("font_color", color)

func display_best_time() -> void:
	if not best_time_label or current_level.is_empty():
		return

	var best_time: float = GameManager.load_best_time(current_level)
	if best_time > 0.0:
		best_time_label.text = "Best: " + format_time(best_time)
	else:
		best_time_label.text = "Best: --:--:---"

func show_final_time(final_time: float) -> void:
	if not timer_label or not best_time_label:
		return
	
	timer_label.text = "Time: " + format_time(final_time)
	
	var best_time: float = GameManager.load_best_time(current_level)
	
	# If there's no best time or the new time is better, save it.
	if best_time <= 0.0 or final_time < best_time:
		GameManager.save_best_time(current_level, final_time)
		best_time_label.text = "New Best: " + format_time(final_time)
	else:
		best_time_label.text = "Best: " + format_time(best_time)

func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60)
	var secs := int(seconds) % 60
	var ms := int(fmod(seconds, 1.0) * 1000)
	return "%02d:%02d:%03d" % [minutes, secs, ms]
