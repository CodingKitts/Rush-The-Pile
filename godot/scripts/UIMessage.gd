# UIMessage.gd — Simple status banner that listens to Game.status
#
# Responsibilities
# - Bind to the root scene's `status` signal and reflect messages in a Label
# - Suppress the initial "X starts" message to keep the top-center clear (Visuals shows timer)
#
extends Label

## Connect to current_scene.status on ready.
func _ready() -> void:
	var root := get_tree().current_scene
	if root and root.has_signal("status"):
		root.status.connect(_on_status)

## Handle status messages; hides the initial "X starts" banner.
func _on_status(msg: String) -> void:
	# Suppress the initial "X starts" banner so only the timer shows at top center.
	# Visuals.gd still listens to the status signal to start the timer when it contains " starts".
	if typeof(msg) == TYPE_STRING and msg.ends_with(" starts"):
		text = ""
	else:
		text = msg
