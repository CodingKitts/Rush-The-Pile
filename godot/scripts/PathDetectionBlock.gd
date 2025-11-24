# PathDetectionBlock.gd — Visual detection block that lights up when a moving block crosses it
#
# Attach to a Node2D placed as a child of the Path2D (same parent level as the PathFollow2D).
# It positions itself at the bottom-center of the Path2D's curve bounds and changes color
# when the moving block's edges overlap its rectangular area.
#
# Edge-based logic:
# - The zone lights up the moment the block's edge first touches the zone edge
#   (inclusive intersection, not center-based).
# - The zone stays lit until the block's opposite edge has fully left
#   (i.e., no AABB overlap between the block's polygon and the zone rect).

extends Node2D

@export var size: Vector2 = Vector2(64, 24)
# Make the detection zone translucent by default so the player can see the block through it
# You can tweak these alphas in the Inspector. "base" is less opaque than "lit" for clarity.
@export var base_color: Color = Color(0.2, 0.25, 0.35, 0.28)
@export var lit_color: Color = Color(0.95, 0.85, 0.2, 0.55)
@export var target_block_path: NodePath = NodePath("../BlockFollow")

var _visual: Polygon2D
var _half_size: Vector2
var _target_block: Node2D
var _target_polygon: Polygon2D
@export var z_index_visual: int = -1 # draw behind the moving block by default

# Public: true while the target block is inside the detection rectangle
var is_inside: bool = false

signal zone_entered
signal zone_exited

func _ready() -> void:
	_half_size = size * 0.5
	_visual = get_node_or_null("Visual") as Polygon2D
	if _visual == null:
		_visual = Polygon2D.new()
		_visual.name = "Visual"
		add_child(_visual)
		_visual.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	# Build a centered rectangle polygon
	# Note: In Godot 4, PackedVector2Array expects an Array of Vector2, not varargs
	_visual.polygon = PackedVector2Array([
		Vector2(-_half_size.x, -_half_size.y),
		Vector2(_half_size.x, -_half_size.y),
		Vector2(_half_size.x, _half_size.y),
		Vector2(-_half_size.x, _half_size.y)
	])
	_visual.antialiased = true
	_visual.color = base_color
	# Ensure draw order keeps the moving block visible above the zone
	_visual.z_index = z_index_visual

	# Try to locate the Path2D and target block for monitoring
	var path := get_parent() as Path2D
	if path != null:
		_place_at_bottom_center(path)
	_target_block = get_node_or_null(target_block_path) as Node2D

	set_process(true)

func _place_at_bottom_center(path: Path2D) -> void:
	if path.curve == null:
		return
	var pts: PackedVector2Array = path.curve.get_baked_points()
	if pts.is_empty():
		return
	var min_x := pts[0].x
	var max_x := pts[0].x
	var max_y := pts[0].y
	for p in pts:
		if p.x < min_x:
			min_x = p.x
		if p.x > max_x:
			max_x = p.x
		if p.y > max_y:
			max_y = p.y
	# Bottom-center of the path's bounding box
	position = Vector2((min_x + max_x) * 0.5, max_y)

func _process(_delta: float) -> void:
	if _visual == null:
		return
	if _target_block == null:
		_target_block = get_node_or_null(target_block_path) as Node2D
		if _target_block == null:
			_visual.color = base_color
			if is_inside:
				is_inside = false
				zone_exited.emit()
				return
	# Prefer edge-based detection using the actual block polygon's AABB in local space.
	var inside := _is_overlap_with_block()
	_visual.color = lit_color if inside else base_color
	if inside != is_inside:
		is_inside = inside
		if is_inside:
			zone_entered.emit()
		else:
			zone_exited.emit()

## Public helper: compute whether the target block is inside the zone right now.
## This performs an immediate check using the same logic as the per-frame update,
## which avoids a 1-frame delay when queried from UI button callbacks.
func is_block_inside_now() -> bool:
	return _is_overlap_with_block()

func _is_overlap_with_block() -> bool:
	# Try to find the visual polygon under the target block (commonly named "Block")
	if _target_polygon == null or not is_instance_valid(_target_polygon):
		_target_polygon = null
		if _target_block != null:
			# Search immediate children first
			for child in _target_block.get_children():
				if child is Polygon2D:
					_target_polygon = child
					break
			# Fallback: name-based search (in case of deeper hierarchy)
			if _target_polygon == null:
				var candidate := _target_block.get_node_or_null("Block")
				if candidate is Polygon2D:
					_target_polygon = candidate

	# If we still don't have a polygon or it has no points, fallback to center-point logic
	if _target_polygon == null:
		var local_p: Vector2 = to_local(_target_block.global_position)
		return abs(local_p.x) <= _half_size.x and abs(local_p.y) <= _half_size.y

	var poly: PackedVector2Array = _target_polygon.polygon
	if poly.is_empty():
		var local_p2: Vector2 = to_local(_target_block.global_position)
		return abs(local_p2.x) <= _half_size.x and abs(local_p2.y) <= _half_size.y

	# Compute the polygon's AABB in this node's local space
	var gt: Transform2D = _target_polygon.get_global_transform()
	var min_v := Vector2.INF
	var max_v := -Vector2.INF
	for v in poly:
		# In Godot 4, use the * operator to transform a point with Transform2D
		var world_v: Vector2 = gt * v
		var local_v: Vector2 = to_local(world_v)
		if local_v.x < min_v.x:
			min_v.x = local_v.x
		if local_v.y < min_v.y:
			min_v.y = local_v.y
		if local_v.x > max_v.x:
			max_v.x = local_v.x
		if local_v.y > max_v.y:
			max_v.y = local_v.y

	# Zone rectangle in local space is centered at (0,0) with half extents _half_size
	var zone_min := Vector2(-_half_size.x, -_half_size.y)
	var zone_max := Vector2(_half_size.x, _half_size.y)

	# Inclusive AABB overlap check (touching counts as inside)
	var separated := max_v.x < zone_min.x or min_v.x > zone_max.x or max_v.y < zone_min.y or min_v.y > zone_max.y
	return not separated
