# A full-featured settings menu with saving, loading, and display options.

extends PanelContainer

# --- SIGNALS ---
signal fov_changed(new_fov: float)
signal sensitivity_changed(new_sensitivity: float)

# --- CONSTANTS ---
const SETTINGS_FILE_PATH = "user://settings.cfg"
const MASTER_BUS_NAME = "Master"
const MIN_VOLUME_DB = -80.0  # Minimum volume in decibels (near silent)
const MAX_VOLUME_DB = 0.0      # Maximum volume in decibels (full volume)

# Predefined list of common 16:9 resolutions.
const COMMON_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),   # HD
	Vector2i(1600, 900),   # HD+
	Vector2i(1920, 1080),  # Full HD
	Vector2i(2560, 1440),  # 2K
	Vector2i(3840, 2160),  # 4K
]

# --- NODE REFERENCES ---
@onready var master_volume_slider: HSlider = $VBoxContainer/Volume/HSlider
@onready var display_mode_button: OptionButton = $VBoxContainer/DisplayMode/OptionButton
@onready var resolution_button: OptionButton = $VBoxContainer/Resolution/OptionButton
@onready var fov_slider: HSlider = $VBoxContainer/FOV/HSlider
@onready var sensitivity_slider: HSlider = $VBoxContainer/Sensitivity/HSlider
@onready var back_button: Button = $VBoxContainer/Back/BackButton
# NEW: Add references to the labels next to your sliders
@onready var fov_label: Label = $VBoxContainer/FOV/FovLabel
@onready var sensitivity_label: Label = $VBoxContainer/Sensitivity/SensitivityLabel
@onready var volume_label: Label = $VBoxContainer/Volume/VolumeLabel


func _ready() -> void:
	hide() # Hide on start

	# Register with the GameManager to send signals to the player.
	# Make sure your autoload is named "GameManager".
	if get_tree().root.has_node("GameManager"):
		get_tree().root.get_node("GameManager").register_settings_menu(self)

	# Configure volume slider
	master_volume_slider.min_value = 0.0
	master_volume_slider.max_value = 1.0
	master_volume_slider.step = 0.01
	master_volume_slider.value = 1.0  # Default to full volume

	# Configure FOV slider
	fov_slider.min_value = 60.0
	fov_slider.max_value = 120.0
	fov_slider.step = 1.0
	fov_slider.value = 90.0 # Default FOV

	# Configure Sensitivity slider
	sensitivity_slider.min_value = 0.1
	sensitivity_slider.max_value = 5.0
	sensitivity_slider.step = 0.1
	sensitivity_slider.value = 1.2 # Default sensitivity

	_setup_display_options()
	load_settings()
	_update_labels() # NEW: Update labels with loaded values

	# Connect signals
	back_button.pressed.connect(_on_back_button_pressed)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	display_mode_button.item_selected.connect(_on_display_mode_selected)
	resolution_button.item_selected.connect(_on_resolution_selected)
	fov_slider.value_changed.connect(_on_fov_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)


# -------------------------------------------------------------------
# ---                           SETUP AND INITIALIZATION                          ---
# -------------------------------------------------------------------

func _setup_display_options() -> void:
	# Clear existing items
	display_mode_button.clear()
	resolution_button.clear()

	# Populate Display Mode button
	display_mode_button.add_item("Windowed", DisplayServer.WINDOW_MODE_WINDOWED)
	display_mode_button.add_item("Borderless", DisplayServer.WINDOW_MODE_FULLSCREEN)
	display_mode_button.add_item("Fullscreen", DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	# Populate Resolution button
	var resolutions: Array[Vector2i] = _get_available_resolutions()
	for res in resolutions:
		resolution_button.add_item("%d × %d" % [res.x, res.y])


func _get_available_resolutions() -> Array[Vector2i]:
	"""Returns a sorted list of unique screen resolutions."""
	var resolutions: Array[Vector2i] = COMMON_RESOLUTIONS.duplicate()

	# Get the primary screen's native resolution
	var primary_screen_id = DisplayServer.get_primary_screen()
	var native_res: Vector2i = DisplayServer.screen_get_size(primary_screen_id)

	# Add the user's native resolution if it's not already in our list
	if not resolutions.has(native_res):
		resolutions.append(native_res)

	# Sort resolutions from smallest to largest
	resolutions.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	return resolutions


# -------------------------------------------------------------------
# ---                           SAVING AND LOADING                            ---
# -------------------------------------------------------------------

func save_settings() -> void:
	var config = ConfigFile.new()

	# Audio settings
	config.set_value("audio", "master_volume", master_volume_slider.value)

	# Display settings
	config.set_value("display", "mode_id", display_mode_button.get_selected_id())
	config.set_value("display", "resolution_idx", resolution_button.selected)
	
	# Player settings
	config.set_value("player", "fov", fov_slider.value)
	config.set_value("player", "sensitivity", sensitivity_slider.value)

	var err = config.save(SETTINGS_FILE_PATH)
	if err != OK:
		push_error("Failed to save settings to %s. Error code: %d" % [SETTINGS_FILE_PATH, err])


func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE_PATH)

	# If no config file exists, save the current default settings
	if err != OK:
		push_warning("No settings file found at %s. Creating one with default values." % SETTINGS_FILE_PATH)
		_set_bus_volume(MASTER_BUS_NAME, 1.0)  # Default to full volume
		_apply_settings_from_ui()
		# Emit default signals on first launch
		emit_signal("fov_changed", fov_slider.value)
		emit_signal("sensitivity_changed", sensitivity_slider.value)
		save_settings()
		return

	# --- Apply loaded audio settings ---
	var master_volume = config.get_value("audio", "master_volume", 1.0)
	master_volume_slider.value = master_volume
	_set_bus_volume(MASTER_BUS_NAME, master_volume)

	# --- Apply loaded display settings ---
	# Display mode (fallback to windowed)
	var mode_id = config.get_value("display", "mode_id", DisplayServer.WINDOW_MODE_WINDOWED)
	var item_index = display_mode_button.get_item_index(mode_id)
	display_mode_button.select(item_index if item_index != -1 else 0)

	# Resolution (fallback to highest available)
	var res_idx = config.get_value("display", "resolution_idx", resolution_button.item_count - 1)
	resolution_button.select(clamp(res_idx, 0, resolution_button.item_count - 1))

	# --- Apply loaded player settings ---
	var fov = config.get_value("player", "fov", 90.0)
	fov_slider.value = fov
	emit_signal("fov_changed", fov)

	var sensitivity = config.get_value("player", "sensitivity", 1.0)
	sensitivity_slider.value = sensitivity
	emit_signal("sensitivity_changed", sensitivity)
	
	_apply_settings_from_ui()


# -------------------------------------------------------------------
# ---                        APPLY SETTINGS & SIGNALS                             ---
# -------------------------------------------------------------------

func _apply_settings_from_ui() -> void:
	"""Reads settings from the UI and applies them to the game window and audio."""
	# --- Apply Display Mode ---
	var selected_mode_id = display_mode_button.get_selected_id()
	DisplayServer.window_set_mode(selected_mode_id)

	# Only enable resolution selection in windowed mode
	resolution_button.disabled = (selected_mode_id != DisplayServer.WINDOW_MODE_WINDOWED)

	# --- Apply Resolution ---
	if not resolution_button.disabled:
		var res_text = resolution_button.get_item_text(resolution_button.selected).split(" × ")
		var new_size = Vector2i(int(res_text[0]), int(res_text[1]))
		DisplayServer.window_set_size(new_size)

		# Center window on primary monitor
		var primary_screen_id = DisplayServer.get_primary_screen()
		var screen_size = DisplayServer.screen_get_size(primary_screen_id)
		var screen_pos = DisplayServer.screen_get_position(primary_screen_id)
		DisplayServer.window_set_position(screen_pos + (screen_size - new_size) / 2)

	# Auto-save after applying any changes
	save_settings()


func _on_display_mode_selected(index: int) -> void:
	_apply_settings_from_ui()


func _on_resolution_selected(index: int) -> void:
	if not resolution_button.disabled:
		_apply_settings_from_ui()


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume(MASTER_BUS_NAME, value)
	_update_labels() # NEW: Update the labels when the slider moves
	save_settings()  # Save immediately when volume changes

func _on_fov_changed(value: float) -> void:
	_update_labels() # NEW: Update the labels when the slider moves
	emit_signal("fov_changed", value)
	save_settings()

func _on_sensitivity_changed(value: float) -> void:
	_update_labels() # NEW: Update the labels when the slider moves
	emit_signal("sensitivity_changed", value)
	save_settings()

func _on_back_button_pressed() -> void:
	hide()  # No need to save here since we're auto-saving on changes


# -------------------------------------------------------------------
# ---                           HELPER FUNCTIONS                                ---
# -------------------------------------------------------------------

# NEW: This function updates the text of the labels to show the current slider values.
func _update_labels() -> void:
	if is_instance_valid(fov_label):
		# Format the FOV as a whole number
		fov_label.text = str(int(fov_slider.value))
	if is_instance_valid(sensitivity_label):
		# Format the sensitivity to two decimal places
		sensitivity_label.text = "%.2f" % sensitivity_slider.value
	if is_instance_valid(volume_label):
		# Format the sensitivity to two decimal places
		volume_label.text = "%.2f" % master_volume_slider.value


func _set_bus_volume(bus_name: String, linear_value: float) -> void:
	"""Sets the audio bus volume with an exponential curve for more natural control."""
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		var clamped_value = clampf(linear_value, 0.0, 1.0)
		var volume_db = linear_to_db(pow(clamped_value, 4.0))
		AudioServer.set_bus_volume_db(bus_index, volume_db)
