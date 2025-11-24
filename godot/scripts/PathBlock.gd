# PathBlock.gd — Moves a Sprite2D along a Path2D using PathFollow2D
# NOTE: This file uses TAB characters for leading indentation. Avoid spaces at line starts.
#
# Usage:
# - Attach to a PathFollow2D that is a child of a Path2D.
# - Add a Sprite2D as a child (used as the visual block).
# - Optionally add an arrow Sprite2D (child of the block) to indicate flow direction.
#
# Features:
# - Continuous movement along the path at configurable speed.
# - Spawn point can be set to the start (top, opposite of player's bottom position).
# - Visual indicator rotates with path to show flow direction.
# - Ability to remove the block programmatically via remove_block().
extends PathFollow2D

@export var speed: float = 220.0
@export var looping: bool = false
## If true, the block will be freed when it reaches an end (non-looping).
## If false, it will bounce (reverse direction) at the ends instead of disappearing.
@export var despawn_at_ends: bool = false
## 1 = forward along the curve, -1 = backward
@export var flow_direction: int = 1
## If true, spawn at the start of the curve (ratio 0). If false, spawn at end (ratio 1).
## By default we spawn opposite of the player position (player at bottom → spawn at top/start).
@export var spawn_at_start: bool = true

signal reached_end

# Keep track of which Curve2D we are connected to (if any), so we can manage signals safely.
var _connected_curve: Curve2D = null
## Optional visual arrow (e.g., Line2D) that indicates current flow direction
var _arrow: Node2D = null
var _last_flow_dir: int = 0

func _ready() -> void:
	# Ensure we rotate with the path so the indicator points the way.
	rotates = true
	# Initialize spawn only if the parent Path2D has a valid curve.
	# If no curve yet, defer until it becomes available.
	_ensure_curve_signal_connection()
	# Try to initialize now (will enable/disable processing accordingly)
	_init_spawn_if_possible()
	# Cache arrow node if present and sync its visual
	_arrow = get_node_or_null("FlowArrow") as Node2D
	_last_flow_dir = flow_direction
	_update_arrow_visual()

func _process(delta: float) -> void:
	# Skip all logic if we don't have a usable curve yet
	if not _has_valid_curve():
		# Keep trying to connect if the curve resource is assigned later
		_ensure_curve_signal_connection()
		return
	if speed == 0:
		# Still keep the arrow visual in sync even if not moving
		if flow_direction != _last_flow_dir:
			_last_flow_dir = flow_direction
			_update_arrow_visual()
		return
	# Move along the curve in the chosen direction
	progress += float(flow_direction) * speed * delta

	# Update arrow visual if direction has changed externally
	if flow_direction != _last_flow_dir:
		_last_flow_dir = flow_direction
		_update_arrow_visual()

	# Handle end conditions
	if looping:
		_wrap_progress()
	else:
		if flow_direction >= 0 and progress_ratio >= 0.9999:
			reached_end.emit()
			if despawn_at_ends:
				queue_free()
			else:
				# Bounce: reverse direction and nudge slightly inside the path
				flow_direction = -1
				_last_flow_dir = flow_direction
				progress_ratio = 0.9998
				_update_arrow_visual()
		elif flow_direction < 0 and progress_ratio <= 0.0001:
			reached_end.emit()
			if despawn_at_ends:
				queue_free()
			else:
				# Bounce: reverse direction and nudge slightly inside the path
				flow_direction = 1
				_last_flow_dir = flow_direction
				progress_ratio = 0.0002
				_update_arrow_visual()

func _wrap_progress() -> void:
	# Wrap progress to keep moving indefinitely
	# We can simply clamp ratio into [0,1] by cycling the underlying offset.
	# Using progress instead of progress_ratio allows continuous motion.
	var l: float = 1.0
	var path := get_parent() as Path2D
	if path != null and path.curve != null:
		l = max(1.0, path.curve.get_baked_length())
	if progress < 0.0:
		progress = fmod(progress, l) + l
	elif progress > l:
		progress = fmod(progress, l)

# Attempt to set the initial spawn point if a valid curve exists.
# Enables processing when valid, disables when not.
func _init_spawn_if_possible() -> void:
	if _has_valid_curve():
		# Spawn position opposite of player (player at bottom → start/top of curve)
		progress_ratio = 0.0 if spawn_at_start else 1.0
		set_process(true)
	else:
		# Disable processing until a curve is available
		set_process(false)

# Returns true when the parent is a Path2D with a non-null curve of non-zero length
func _has_valid_curve() -> bool:
	var path := get_parent() as Path2D
	if path == null or path.curve == null:
		return false
	# Use baked length to ensure there is actual distance to traverse
	return path.curve.get_baked_length() > 0.0

func _on_curve_changed() -> void:
	# Re-attempt initialization when the curve content changes
	_init_spawn_if_possible()

# Ensure we are connected to the current Path2D.curve's "changed" signal (Curve2D emits this).
# Safely disconnect from any previous curve to avoid duplicate callbacks.
func _ensure_curve_signal_connection() -> void:
	var path := get_parent() as Path2D
	var current_curve: Curve2D = null
	if path != null:
		current_curve = path.curve
	# If we were connected to a different curve before, disconnect.
	if _connected_curve != null:
		if is_instance_valid(_connected_curve) and _connected_curve != current_curve:
			if _connected_curve.changed.is_connected(_on_curve_changed):
				_connected_curve.changed.disconnect(_on_curve_changed)
			_connected_curve = null
	# Connect to the current curve if available and not already connected
	if current_curve != null:
		if not current_curve.changed.is_connected(_on_curve_changed):
			current_curve.changed.connect(_on_curve_changed)
		_connected_curve = current_curve

## Public API: remove this block programmatically
func remove_block() -> void:
	queue_free()

## Public API: toggle the flow direction (forward/backward)
func toggle_direction() -> void:
	flow_direction = -flow_direction
	# If we are exactly at an end and not looping, slightly nudge the ratio away
	# from the boundary in the opposite direction so we don't trigger the
	# end-despawn check on the very next frame after changing direction.
	if not looping:
		if flow_direction < 0 and progress_ratio >= 0.9999:
			# Was at end (1.0), now moving backward → nudge just inside the path
			progress_ratio = 0.9998
		elif flow_direction >= 0 and progress_ratio <= 0.0001:
			# Was at start (0.0), now moving forward → nudge just inside the path
			progress_ratio = 0.0002
	_last_flow_dir = flow_direction
	_update_arrow_visual()

## Keep the directional arrow pointing along the current flow direction.
## Expects the arrow to be authored pointing along +X in local space.
func _update_arrow_visual() -> void:
	if _arrow == null:
		# Try to lazily find it if not cached yet
		_arrow = get_node_or_null("FlowArrow") as Node2D
	if _arrow != null:
		var sx := 1.0 if flow_direction >= 0 else -1.0
		# Only change X scale to mirror horizontally; preserve Y to avoid thickness changes
		_arrow.scale.x = sx

## Public API: adjust the current speed by a delta. Clamped to a minimum of 0.
func adjust_speed(delta_speed: float) -> void:
	speed = max(0.0, speed + delta_speed)

## Public API: increase speed (UI Up Arrow)
func increase_speed() -> void:
	adjust_speed(50.0)

## Public API: decrease speed (UI Down Arrow)
func decrease_speed() -> void:
	adjust_speed(-50.0)
