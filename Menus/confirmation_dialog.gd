# confirmation_dialog.gd
extends ConfirmationDialog

func _ready():
	# Set dialog to be modal (blocks input to other UI)
	exclusive = true
	# Connect signals
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)

func _on_confirmed():
	print("Action confirmed!")

func _on_canceled():
	print("Action canceled!")
