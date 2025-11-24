# PathDebugLabel.gd — Tiny HUD label that shows Path2D baked point count
extends Label

@export var path_node: NodePath

func _ready() -> void:
    # Initialize text and keep it non-interactive
    text = "Baked: -"
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
    var p := get_node_or_null(path_node) as Path2D
    if p != null and p.curve != null:
        text = "Baked: %d" % p.curve.get_baked_points().size()
    else:
        text = "Baked: -"
