# settings_menu.gd
extends PanelContainer

# Audio bus names
const MASTER_BUS_NAME = "Master"
const MUSIC_BUS_NAME = "Music"
const SFX_BUS_NAME = "SFX"

# Node references
@onready var master_volume_slider: HSlider = $VBoxContainer/HBoxContainer/HSlider
@onready var fullscreen_checkbox: CheckBox = $VBoxContainer/HBoxContainer2/CheckBox
@onready var back_button: Button = $VBoxContainer/HBoxContainer3/Button

func _ready() -> void:
	# Hide on start, it will be shown by other menus.
	hide()

	# Connect signals
	back_button.pressed.connect(_on_back_button_pressed)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)

	# Set initial values from the AudioServer and DisplayServer
	_initialize_slider(master_volume_slider, MASTER_BUS_NAME)
	fullscreen_checkbox.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)

func _initialize_slider(slider: HSlider, bus_name: String) -> void:
	"""Sets a slider's initial value based on the current audio bus volume."""
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		var volume_db = AudioServer.get_bus_volume_db(bus_index)
		slider.value = db_to_linear(volume_db)

func _set_bus_volume(bus_name: String, linear_value: float) -> void:
	"""Sets the audio bus volume from a linear slider value."""
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		# A value of 0 in the slider should mute the audio completely.
		var volume_db = linear_to_db(linear_value) if linear_value > 0 else -80.0
		AudioServer.set_bus_volume_db(bus_index, volume_db)

func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume(MASTER_BUS_NAME, value)

func _on_fullscreen_toggled(is_toggled_on: bool) -> void:
	if is_toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_button_pressed() -> void:
	# Just hide the panel. The parent menu is still visible underneath.
	hide()
