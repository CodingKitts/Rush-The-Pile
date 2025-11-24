# PathRenderer.gd — Renders a Path2D's curve using a Line2D so it is visible over the background
#
# Attach this script to a Path2D node. It will create (or reuse) a child Line2D
# named "PathLine" and update its points from the Path2D.curve's baked points.
# The line automatically refreshes when the curve changes.
extends Path2D

@export var line_width: float = 6.0
@export var line_color: Color = Color(0.9, 0.95, 1.0, 0.65) # light, slightly transparent
@export var antialiased: bool = true
@export var round_joints: bool = true
@export var round_corners: bool = true
@export var texture_mode: Line2D.LineTextureMode = Line2D.LINE_TEXTURE_NONE
@export var z_index_line: int = -1 # draw behind moving blocks by default

var _line: Line2D

func _ready() -> void:
	_ensure_line_node()
	_connect_curve_signal()
	_update_line()

func _exit_tree() -> void:
	# Best-effort disconnect if needed
	if curve != null and curve.changed.is_connected(_on_curve_changed):
		curve.changed.disconnect(_on_curve_changed)

func _ensure_line_node() -> void:
	_line = get_node_or_null("PathLine") as Line2D
	if _line == null:
		_line = Line2D.new()
		_line.name = "PathLine"
		add_child(_line)
		_line.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	_line.width = line_width
	_line.default_color = line_color
	_line.antialiased = antialiased
	_line.joint_mode = Line2D.LINE_JOINT_ROUND if round_joints else Line2D.LINE_JOINT_SHARP
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND if round_corners else Line2D.LINE_CAP_NONE
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND if round_corners else Line2D.LINE_CAP_NONE
	_line.texture_mode = texture_mode
	_line.z_index = z_index_line

func _connect_curve_signal() -> void:
	if curve == null:
		return
	if not curve.changed.is_connected(_on_curve_changed):
		curve.changed.connect(_on_curve_changed)

func _on_curve_changed() -> void:
	_update_line()

func _update_line() -> void:
	if _line == null:
		return
	if curve == null:
		_line.points = PackedVector2Array()
		return
	var pts: PackedVector2Array = curve.get_baked_points()
	_line.points = pts if pts.size() > 1 else PackedVector2Array()
	# Keep visual properties synced in case exports were tweaked in Inspector
	_line.width = line_width
	_line.default_color = line_color
	_line.antialiased = antialiased
	_line.joint_mode = Line2D.LINE_JOINT_ROUND if round_joints else Line2D.LINE_JOINT_SHARP
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND if round_corners else Line2D.LINE_CAP_NONE
	_line.end_cap_mode = Line2D.LINE_CAP_ROUND if round_corners else Line2D.LINE_CAP_NONE
	_line.texture_mode = texture_mode
	_line.z_index = z_index_line
