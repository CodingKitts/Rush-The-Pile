# PathFlowDemo.gd — Demo-level controller for PathFlowDemo.tscn
# Responsibilities:
# - Compute the path center and position a temporary popup label there
# - When the action is triggered (via Up Arrow UI), if the block is inside the zone, show "Got It!" for 1 second

extends Node2D

@onready var _path: Path2D = $World/Path
@onready var _detector: Node2D = $World/Path/DetectionBlock
@onready var _popup_label: Label = $World/CenterPopup
@onready var _btn_speed_up: Button = $UI/UIRoot/SpeedControls/IncreaseSpeedButton
@onready var _btn_speed_down: Button = $UI/UIRoot/SpeedControls/DecreaseSpeedButton
@onready var _btn_arrow_up: Button = $UI/UIRoot/DPad/ArrowUpButton
@onready var _attempts_label: Label = $UI/AttemptsLabel
@onready var _btn_quit: Button = $UI/QuitButton

var _hide_timer: SceneTreeTimer
var _attempts_max: int = 5
var _attempts_left: int = 5

func _ready() -> void:
	# Place the popup at the center of the path's bounds
	_position_popup_at_path_center()
	# Hide popup initially
	_popup_label.visible = false
	# Initialize attempts UI
	_attempts_left = _attempts_max
	_refresh_attempts_label()
	# Give the bottom-right Up Arrow the same behavior as the Press button
	if _btn_arrow_up:
		_btn_arrow_up.pressed.connect(_on_press_button)

	# Ensure UI buttons don't remain highlighted after being pressed
	_disable_button_focus_and_cleanup(_btn_speed_up)
	_disable_button_focus_and_cleanup(_btn_speed_down)
	_disable_button_focus_and_cleanup(_btn_arrow_up)
	_disable_button_focus_and_cleanup(_btn_quit)

	# Recalculate if the curve changes at edit/runtime
	if _path and _path.curve:
		if not _path.curve.changed.is_connected(_on_curve_changed):
			_path.curve.changed.connect(_on_curve_changed)

func _on_quit_pressed() -> void:
	# Close the application when Quit button is pressed
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	# Allow physical keyboard/gamepad input to trigger the same action as the Up Arrow button
	if _attempts_left <= 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Keyboard Up Arrow
		if event.keycode == Key.KEY_UP:
			_on_press_button()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		# Gamepad D-Pad Up or Left Stick Up button (if mapped on some controllers)
		if event.button_index == JOY_BUTTON_DPAD_UP:
			_on_press_button()
			get_viewport().set_input_as_handled()

func _refresh_attempts_label() -> void:
	if _attempts_label:
		_attempts_label.text = "Attempts: %d" % _attempts_left
	# Visually disable the Up Arrow when out of attempts
	if _btn_arrow_up:
		_btn_arrow_up.disabled = _attempts_left <= 0

func _on_curve_changed() -> void:
	_position_popup_at_path_center()

func _position_popup_at_path_center() -> void:
	if _path == null or _path.curve == null:
		return
	var pts := _path.curve.get_baked_points()
	if pts.is_empty():
		return
	var min_x := pts[0].x
	var max_x := pts[0].x
	var min_y := pts[0].y
	var max_y := pts[0].y
	for p in pts:
		if p.x < min_x:
			min_x = p.x
		if p.x > max_x:
			max_x = p.x
		if p.y < min_y:
			min_y = p.y
		if p.y > max_y:
			max_y = p.y
	var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	# Center the label on this point
	var size := _popup_label.size
	_popup_label.position = center - size * 0.5

func _on_press_button() -> void:
	# If no attempts left, ignore presses
	if _attempts_left <= 0:
		return
	# If block is inside detection zone when pressed, show popup for 1s
	if _detector:
		var inside := false
		# Prefer instantaneous geometry check to avoid 1-frame lag at high speeds
		if _detector.has_method("is_block_inside_now"):
			inside = _detector.call("is_block_inside_now")
		else:
			inside = bool(_detector.get("is_inside"))
		if inside:
			_show_popup_one_second()
		else:
			# Missed the zone -> consume an attempt
			_attempts_left = max(0, _attempts_left - 1)
			_refresh_attempts_label()

func _show_popup_one_second() -> void:
	_popup_label.text = "Got It!"
	_popup_label.visible = true
	# Always (re)create the timer so the popup actually hides after 1 second
	# If a previous timer existed, we simply replace it; any old connection will fire once and do no harm
	_hide_timer = get_tree().create_timer(1.0)
	_hide_timer.timeout.connect(func():
		_popup_label.visible = false
	)

## Remove lingering highlight/focus from a button after mouse/touch press
func _disable_button_focus_and_cleanup(btn: Button) -> void:
	if btn == null:
		return
	btn.focus_mode = Control.FOCUS_NONE
	# Also clear focus right after any press just in case
	btn.pressed.connect(func():
		btn.release_focus()
		# Ensure not stuck in pressed state (in case toggle_mode was enabled in editor)
		if btn.toggle_mode and btn.button_pressed:
			btn.set_pressed_no_signal(false)
	)
