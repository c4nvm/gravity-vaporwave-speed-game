extends CanvasLayer

@onready var timer_label: Label = %TimerLabel
@onready var record_time_label: Label = %BestTimeLabel
@onready var debug_label: Label = %DebugLabel

var current_level_id: String = ""
var current_record: float = 0.0

func _ready() -> void:
	GameManager.register_gameplay_ui(self)
	
	# Set default text values
	record_time_label.text = "Record: --:--:---"
	timer_label.text = "00:00:000"

	# Directly get the level ID from the GameManager when the UI is ready.
	current_level_id = GameManager.current_level_id
	
	# Call the function to load and display the record.
	load_record_time()

func load_record_time() -> void:
	# This guard is still good practice.
	if current_level_id.is_empty():
		return
	
	current_record = GameManager.load_best_time(current_level_id)
	
	if current_record > 0.0:
		record_time_label.text = "Record: " + format_time(current_record)
	else:
		# This now shows if there is genuinely no record saved.
		record_time_label.text = "Record: No record"

func update_timer(time_in_seconds: float) -> void:
	timer_label.text = format_time(time_in_seconds)

func show_final_time(final_time: float) -> void:
	timer_label.text = "Time: " + format_time(final_time)

	# Check against the current record to see if a new one was set.
	if current_record <= 0.0 or final_time < current_record:
		GameManager.save_best_time(final_time)
		
		current_record = final_time
		record_time_label.text = "New Record: " + format_time(final_time)
		set_timer_visibility(Color.GOLD)
	else:
		record_time_label.text = "Record: " + format_time(current_record)
		set_timer_visibility(Color.WHITE)

func set_timer_visibility(color: Color) -> void:
	timer_label.add_theme_color_override("font_color", color)

func update_debug(debug_string: String) -> void:
	debug_label.text = debug_string

func format_time(seconds: float) -> String:
	var minutes := int(seconds / 60)
	var secs := int(seconds) % 60
	var ms := int(fmod(seconds, 1.0) * 1000)
	return "%02d:%02d:%03d" % [minutes, secs, ms]
