## PathFlowDemo.gd — Demo-level controller for PathFlowDemo.tscn
## Responsibilities:
## - Compute the path center and position a temporary popup label there
## - When the action is triggered (via Up Arrow UI), if the block is inside the zone, show "Got It!" for about 1.5 seconds

extends Node2D

@onready var _path: Path2D = $World/Path
@onready var _detector: Node2D = $World/Path/DetectionBlock
@onready var _popup_label: Label = $World/CenterPopup
@onready var _block: Node = $World/Path/BlockFollow
@onready var _btn_speed_up: Button = $UI/UIRoot/SpeedControls/IncreaseSpeedButton
@onready var _btn_speed_down: Button = $UI/UIRoot/SpeedControls/DecreaseSpeedButton
@onready var _btn_arrow_up: Button = $UI/UIRoot/DPad/ArrowUpButton
@onready var _attempts_label: Label = $UI/AttemptsLabel
@onready var _btn_quit: Button = $UI/QuitButton
@onready var _btn_pause: Button = $UI/UIRoot/PauseButton
@onready var _pause_overlay: Control = $UI/PauseOverlay
@onready var _resume_button: Button = $UI/PauseOverlay/Panel/VBox/ResumeButton
@onready var _exit_button: Button = $UI/PauseOverlay/Panel/VBox/ExitButton
@onready var _countdown_label: Label = $UI/PauseOverlay/CountdownLabel
@onready var _pause_panel: Panel = $UI/PauseOverlay/Panel
@onready var _pause_dim: ColorRect = $UI/PauseOverlay/Dim
@onready var _music_slider: HSlider = $UI/PauseOverlay/Panel/VBox/MusicRow/MusicSlider
@onready var _sfx_slider: HSlider = $UI/PauseOverlay/Panel/VBox/SfxRow/SfxSlider
@onready var _audio: AudioManager = $Audio
@onready var _green_line: ColorRect = $UI/OneThirdLine

## Swipe indicator debug label removed per request — popups remain for feedback

# Simple swipe tracking
var _swipe_active: bool = false
var _swipe_start_pos: Vector2 = Vector2.INF
var _swipe_start_id: int = -1
const SWIPE_MIN_DISTANCE := 60.0 # pixels
const SWIPE_MAX_DURATION := 1.0 # seconds (optional soft cap)
var _swipe_start_time: float = 0.0

var _attempts_max: int = 5
var _attempts_left: int = 5
var _popup_tween: Tween

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
	_disable_button_focus_and_cleanup(_btn_pause)
	_disable_button_focus_and_cleanup(_resume_button)
	_disable_button_focus_and_cleanup(_exit_button)

	# Ensure the pause overlay and its controls work while the tree is paused
	# so the Resume button can be pressed to unpause.
	if _pause_overlay:
		_pause_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if _resume_button:
		_resume_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if _exit_button:
		_exit_button.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if _countdown_label:
		_countdown_label.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# Hook up Pause/Resume and volume sliders
	if _btn_pause:
		_btn_pause.pressed.connect(_on_pause_pressed)
	if _resume_button:
		_resume_button.pressed.connect(_on_resume_pressed)
	if _exit_button:
		_exit_button.pressed.connect(_on_quit_pressed)
	# Initialize slider values from AudioManager if available
	if _audio:
		if _music_slider:
			_music_slider.value = _audio.get_master_volume_linear()
			_music_slider.value_changed.connect(_on_music_changed)
		if _sfx_slider:
			_sfx_slider.value = _audio.get_sfx_volume_linear()
			_sfx_slider.value_changed.connect(_on_sfx_changed)

	# Recalculate if the curve changes at edit/runtime
	if _path and _path.curve:
		if not _path.curve.changed.is_connected(_on_curve_changed):
			_path.curve.changed.connect(_on_curve_changed)

	# Swipe debug label removed; using center popups only

func _on_quit_pressed() -> void:
	# Close the application when Quit button is pressed
	get_tree().quit()


func _input(event: InputEvent) -> void:
	# Handle pause/resume hotkey even if UI consumes input
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if get_tree().paused:
			_on_resume_pressed()
		else:
			_on_pause_pressed()
		get_viewport().set_input_as_handled()
		return

	# Touch-based swipe handling (processed early so UI controls won't block it)
	if event is InputEventScreenTouch:
		if event.pressed:
			# Start tracking on press if below green line
			var pos: Vector2 = event.position
			if _is_pos_below_green_line(pos) and not _swipe_active:
				_swipe_active = true
				_swipe_start_pos = pos
				_swipe_start_id = event.index
				_swipe_start_time = Time.get_unix_time_from_system()
		else:
			# Release: if we're tracking this finger, evaluate swipe
			if _swipe_active and event.index == _swipe_start_id:
				_process_swipe_end(event.position)
				_reset_swipe()
		return

	# Mouse-based swipe handling (desktop)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var mpos: Vector2 = event.position
				if _is_pos_below_green_line(mpos) and not _swipe_active:
					_swipe_active = true
					_swipe_start_pos = mpos
					_swipe_start_id = 0
					_swipe_start_time = Time.get_unix_time_from_system()
			else:
				if _swipe_active and _swipe_start_id == 0:
					_process_swipe_end(event.position)
					_reset_swipe()
			return

	# Right Arrow (keyboard/gamepad) should toggle the moving block direction — same as on-screen Right button
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == Key.KEY_RIGHT:
			if _block and _block.has_method("toggle_direction"):
				_block.toggle_direction()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_DPAD_RIGHT:
			if _block and _block.has_method("toggle_direction"):
				_block.toggle_direction()
			get_viewport().set_input_as_handled()
			return

	# The following actions should respect remaining attempts
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

func _is_pos_below_green_line(pos: Vector2) -> bool:
	if _green_line == null:
		return true # if line missing, don't block for safety
	# For a 1-2px ColorRect line, top is effectively the line. Compare against its global Y.
	var line_y := _green_line.global_position.y
	return pos.y >= line_y

func _process_swipe_end(end_pos: Vector2) -> void:
	# Start must be inside the swipe detection zone (below the green line)
	if not _is_pos_below_green_line(_swipe_start_pos):
		return
	var delta := end_pos - _swipe_start_pos
	if delta.length() < SWIPE_MIN_DISTANCE:
		return
	# Determine if it's an upward swipe (vertical-dominant and moving up)
	var vertical_dominant := absf(delta.y) >= absf(delta.x)
	var is_up_swipe := vertical_dominant and delta.y < 0.0
	# If it's not an upward swipe, still require the end to be inside the zone
	if not is_up_swipe and not _is_pos_below_green_line(end_pos):
		return
	# Optionally check duration
	var _dur: float = max(0.0, Time.get_unix_time_from_system() - _swipe_start_time)
	# Determine primary direction for feedback
	var dir_text := ""
	if absf(delta.x) > absf(delta.y):
		if delta.x > 0.0:
			dir_text = "Right"
		else:
			dir_text = "Left"
	else:
		if delta.y > 0.0:
			dir_text = "Down"
		else:
			dir_text = "Up"

	# Invoke gameplay for swipe-right: same as pressing the Right Arrow button
	if dir_text == "Right":
		if _block and _block.has_method("toggle_direction"):
			_block.toggle_direction()
	# Debug output to console
	print("Swipe:", dir_text)

	# Show the swipe direction in the center of the path for ~1.5 seconds
	_show_swipe_popup(dir_text)

func _reset_swipe() -> void:
	_swipe_active = false
	_swipe_start_pos = Vector2.INF
	_swipe_start_id = -1
	_swipe_start_time = 0.0

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
	for i in range(pts.size()):
		var px := pts[i].x
		var py := pts[i].y
		if px < min_x:
			min_x = px
		if px > max_x:
			max_x = px
		if py < min_y:
			min_y = py
		if py > max_y:
			max_y = py
	var center_local := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	# Convert from Path2D local to canvas/global space so Control aligns visually with the path
	var center_world := _path.to_global(center_local)
	# Center the label on this point
	var size := _popup_label.size
	_popup_label.position = center_world - size * 0.5

## Show a temporary popup at the path center with the given text (used for swipe feedback)
func _show_swipe_popup(text: String) -> void:
	# Configure appearance for swipe: bright yellow/white, outlined, consistent size
	_popup_label.text = text
	_popup_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.35))
	_popup_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_popup_label.add_theme_constant_override("outline_size", 3)
	_popup_label.add_theme_font_size_override("font_size", 48)

	# Ensure scaling is from the visual center
	var size := _popup_label.size
	_popup_label.pivot_offset = size * 0.5

	# Ensure position is at the path center (in case the path moved)
	_position_popup_at_path_center()

	# Prepare animation state
	_popup_label.visible = true
	_popup_label.modulate.a = 0.0
	_popup_label.scale = Vector2(0.85, 0.85)

	# Stop any previous tween
	if _popup_tween:
		_popup_tween.kill()

	_popup_tween = create_tween()
	_popup_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade and scale in
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 1.0, 0.12).from(0.0)
	_popup_tween.parallel().tween_property(_popup_label, "scale", Vector2(1.0, 1.0), 0.16).from(Vector2(0.85, 0.85))
	# Hold, then fade out so total visible time is about 1.5s
	_popup_tween.tween_interval(1.15)
	_popup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 0.0, 0.22)
	_popup_tween.tween_callback(func():
		_popup_label.visible = false
		_popup_label.scale = Vector2(1, 1)
	)

func _on_press_button() -> void:
	# If no attempts left, ignore presses
	if _attempts_left <= 0:
		return
	# If block is inside detection zone when pressed, show popup for ~1.5s
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
			# Missed the zone -> show feedback and consume an attempt
			_show_miss_popup()
			_attempts_left = max(0, _attempts_left - 1)
			_refresh_attempts_label()

func _show_popup_one_second() -> void:
	# Update look and feel
	_popup_label.text = "Got It!"
	# Make it pop with a friendly green, outlined and larger font if no theme is set in the scene
	_popup_label.add_theme_color_override("font_color", Color(0.18, 0.9, 0.3))
	_popup_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_popup_label.add_theme_constant_override("outline_size", 3)
	_popup_label.add_theme_font_size_override("font_size", 48)

	# Ensure it scales from its center
	var size := _popup_label.size
	_popup_label.pivot_offset = size * 0.5

	# Make sure it's positioned right at the path center (in case the path moved)
	_position_popup_at_path_center()

	# Prepare for animation
	_popup_label.visible = true
	_popup_label.modulate.a = 0.0
	_popup_label.scale = Vector2(0.85, 0.85)

	# Kill any previous animation to avoid overlapping tweens
	if _popup_tween:
		_popup_tween.kill()

	_popup_tween = create_tween()
	_popup_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade and scale in
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 1.0, 0.12).from(0.0)
	_popup_tween.parallel().tween_property(_popup_label, "scale", Vector2(1.0, 1.0), 0.16).from(Vector2(0.85, 0.85))
	# Hold briefly, then fade out (extended by +0.5s)
	_popup_tween.tween_interval(1.15)
	_popup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 0.0, 0.22)
	_popup_tween.tween_callback(func():
		_popup_label.visible = false
		# Reset scale for the next time
		_popup_label.scale = Vector2(1, 1)
	)

func _show_miss_popup() -> void:
	# Configure appearance for a miss: red text, outlined, same size for consistency
	_popup_label.text = "Miss!"
	_popup_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
	_popup_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_popup_label.add_theme_constant_override("outline_size", 3)
	_popup_label.add_theme_font_size_override("font_size", 48)

	# Center-based scaling
	var size := _popup_label.size
	_popup_label.pivot_offset = size * 0.5

	# Ensure position is still at path center
	_position_popup_at_path_center()

	# Prepare animation state
	_popup_label.visible = true
	_popup_label.modulate.a = 0.0
	_popup_label.scale = Vector2(0.85, 0.85)

	# Stop any previous tween
	if _popup_tween:
		_popup_tween.kill()

	_popup_tween = create_tween()
	_popup_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade and scale in
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 1.0, 0.10).from(0.0)
	_popup_tween.parallel().tween_property(_popup_label, "scale", Vector2(1.0, 1.0), 0.14).from(Vector2(0.85, 0.85))
	# Brief hold, then fade out a bit quicker than success
	_popup_tween.tween_interval(0.65)
	_popup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_popup_tween.parallel().tween_property(_popup_label, "modulate:a", 0.0, 0.18)
	_popup_tween.tween_callback(func():
		_popup_label.visible = false
		_popup_label.scale = Vector2(1, 1)
	)

## Pause/Resume handlers and audio volume wiring
func _on_pause_pressed() -> void:
	# Show pause overlay and pause the game
	if _pause_overlay:
		_pause_overlay.visible = true
	# Ensure pause menu elements are visible and countdown is hidden when entering pause
	if _pause_panel:
		_pause_panel.visible = true
	if _pause_dim:
		_pause_dim.visible = true
	if _countdown_label:
		_countdown_label.visible = false
	get_tree().paused = true

func _on_resume_pressed() -> void:
	# Begin a 3-second visible countdown, then resume the game
	if not get_tree().paused:
		return
	if _resume_countdown_running:
		return
	_start_resume_countdown()

var _resume_countdown_running: bool = false

func _start_resume_countdown() -> void:
	_resume_countdown_running = true
	if _resume_button:
		_resume_button.disabled = true
	# Hide the pause menu while showing the countdown
	if _pause_panel:
		_pause_panel.visible = false
	if _pause_dim:
		_pause_dim.visible = false
	if _countdown_label:
		_countdown_label.visible = true
	# Show 3,2,1 with 1 second intervals even while paused
	for n in [3, 2, 1]:
		if _countdown_label:
			_countdown_label.text = str(n)
		await get_tree().create_timer(1.0, true).timeout
	# Hide overlay and resume gameplay
	if _countdown_label:
		_countdown_label.visible = false
	if _pause_overlay:
		_pause_overlay.visible = false
	get_tree().paused = false
	if _resume_button:
		_resume_button.disabled = false
	# Restore pause menu default visibility for the next pause
	if _pause_panel:
		_pause_panel.visible = true
	if _pause_dim:
		_pause_dim.visible = true
	_resume_countdown_running = false

func _on_music_changed(value: float) -> void:
	if _audio:
		_audio.set_master_volume_linear(value)

func _on_sfx_changed(value: float) -> void:
	if _audio:
		_audio.set_sfx_volume_linear(value)

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
