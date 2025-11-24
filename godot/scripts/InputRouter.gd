# InputRouter.gd — Encapsulates human input handling for Rush The Pile
# - Routes center area taps (slap attempts), human play area taps, and TAP button presses
# - Mirrors the guard logic previously in Game.gd while staying decoupled via callables
extends Node
class_name InputRouter

## True once teardown has begun; prevents new inputs from being processed
var _shutting_down: bool = false

# Callbacks provided by Game
## Returns true if input should be ignored due to pause/animation
var _is_blocked: Callable
## Returns true if a given player index is still active in the match
var _is_player_active: Callable
## Returns true if it is currently the human's turn
var _is_human_turn: Callable
## Returns current Game state enum value as int
var _get_state: Callable
## Request Game to play the human's current top card
var _play_current: Callable
## Request Game/TapSystem to attempt a tap for the given player index
var _attempt_tap: Callable
## Returns true if a valid tap window is currently live
var _is_tap_window_live: Callable

# Clean teardown to disconnect and invalidate callbacks to avoid calling freed nodes
func teardown() -> void:
	_shutting_down = true
	# Disconnect signals if nodes are still valid
	if is_instance_valid(_center_area) and _center_area.is_connected("input_event", Callable(self, "_on_center_input")):
		_center_area.disconnect("input_event", Callable(self, "_on_center_input"))
	if is_instance_valid(_player0_area) and _player0_area.is_connected("input_event", Callable(self, "_on_player0_input")):
		_player0_area.disconnect("input_event", Callable(self, "_on_player0_input"))
	if is_instance_valid(_tap_button) and _tap_button.has_signal("pressed") and _tap_button.is_connected("pressed", Callable(self, "_on_tap_button_pressed")):
		_tap_button.disconnect("pressed", Callable(self, "_on_tap_button_pressed"))
	# Invalidate callables
	_is_blocked = Callable()
	_is_player_active = Callable()
	_is_human_turn = Callable()
	_get_state = Callable()
	_play_current = Callable()
	_attempt_tap = Callable()
	_is_tap_window_live = Callable()

# References to interactive nodes
## The center pile input area; clicking here attempts a tap (when window is live)
var _center_area: Area2D
## The human player's play area; clicking here plays a card on their turn
var _player0_area: Area2D
## The on-screen TAP button; mirrors a tap attempt
var _tap_button: Node

## Wire up node references and callables from Game, then connect input signals safely.
func setup(center_area: Area2D, player0_area: Area2D, tap_button: Node,
	is_blocked_cb: Callable,
	is_player_active_cb: Callable,
	is_human_turn_cb: Callable,
	get_state_cb: Callable,
	play_current_cb: Callable,
	attempt_tap_cb: Callable,
	is_tap_window_live_cb: Callable) -> void:
	_shutting_down = false
	_center_area = center_area
	_player0_area = player0_area
	_tap_button = tap_button
	_is_blocked = is_blocked_cb
	_is_player_active = is_player_active_cb
	_is_human_turn = is_human_turn_cb
	_get_state = get_state_cb
	_play_current = play_current_cb
	_attempt_tap = attempt_tap_cb
	_is_tap_window_live = is_tap_window_live_cb
	# Connect signals
	if is_instance_valid(_center_area):
		_center_area.input_pickable = true
		if not _center_area.is_connected("input_event", Callable(self, "_on_center_input")):
			_center_area.connect("input_event", Callable(self, "_on_center_input"))
	if is_instance_valid(_player0_area):
		_player0_area.input_pickable = true
		# Ensure it has a usable collision shape for input if needed (create minimal circle if missing)
		var has_shape := false
		for child in _player0_area.get_children():
			if child is CollisionShape2D:
				has_shape = true
				break
		if not has_shape:
			var cs := CollisionShape2D.new()
			var shape := CircleShape2D.new()
			shape.radius = 60.0
			cs.shape = shape
			_player0_area.add_child(cs)
		if not _player0_area.is_connected("input_event", Callable(self, "_on_player0_input")):
			_player0_area.connect("input_event", Callable(self, "_on_player0_input"))
	if is_instance_valid(_tap_button) and _tap_button.has_signal("pressed"):
		if not _tap_button.is_connected("pressed", Callable(self, "_on_tap_button_pressed")):
			_tap_button.connect("pressed", Callable(self, "_on_tap_button_pressed"))

# Handle the UI action (keyboard/controller) that maps to a tap attempt for the human player.
func handle_ui_tap_action() -> void:
	if _shutting_down:
		return
	# Same behavior as TAP button: attempts a tap regardless of window; TapSystem handles false taps.
	if _is_blocked.is_valid() and _is_blocked.call():
		return
	# Only humans use this path; check active
	if _is_player_active.is_valid() and not _is_player_active.call(0):
		return
	if _attempt_tap.is_valid():
		_attempt_tap.call(0)

# Handle on-screen TAP button pressed by routing to the same tap attempt logic as keyboard/controller.
func _on_tap_button_pressed() -> void:
	if _shutting_down:
		return
	if _is_blocked.is_valid() and _is_blocked.call():
		return
	# Acts same as handle_ui_tap_action
	handle_ui_tap_action()

# Handle clicks/taps on the center pile area; attempts a tap only when a valid window is live.
func _on_center_input(_viewport, event: InputEvent, _shape_idx) -> void:
	if _shutting_down:
		return
	if _is_blocked.is_valid() and _is_blocked.call():
		return
	if event is InputEventMouseButton and event.pressed:
		# Center only allows taps during a live tap window.
		if _is_tap_window_live.is_valid() and _is_tap_window_live.call():
			if _is_player_active.is_valid() and _is_player_active.call(0):
				if _attempt_tap.is_valid():
					_attempt_tap.call(0)

# Handle clicks/taps on the human player's play area; plays a card when it's the human's turn.
func _on_player0_input(_viewport, event: InputEvent, _shape_idx) -> void:
	if _shutting_down:
		return
	if _is_blocked.is_valid() and _is_blocked.call():
		return
	if event is InputEventMouseButton and event.pressed:
		# Player0 area plays a card only when it's the human's turn and state allows plays
		var can_play := false
		if _is_human_turn.is_valid() and _is_human_turn.call():
			if _get_state.is_valid():
				var s = int(_get_state.call())
				# Match against GameState enum values (NORMAL_PLAY=1, CHALLENGE=2 by Game.gd order)
				# We avoid importing the enum here; rely on Game to interpret state.
				can_play = (s == 1 or s == 2)
		if can_play and _play_current.is_valid():
			_play_current.call()
