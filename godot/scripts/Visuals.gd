# Visuals.gd — Overlay VFX/HUD that reacts to Game/TapSystem
#
# Responsibilities
# - Render lightweight highlights, tokens, and HUD labels based on signals
# - Show pause/tutorial/game-over overlays and a simple match timer
# - Provide helper methods (flash_center, animate_false_tap, show_game_over_panel)
#
extends Node2D
class_name Visuals

## Lightweight visual effects overlay that listens to Game and TapSystem events.
## It draws simple shapes and animates temporary labels to indicate actions.

var center_area: Area2D
var center_label: Label
var player_areas: Array[Area2D] = []
var tap_system: Node
var game_ref: Node = null

# Visual state
var active_turn_index: int = 0
var center_highlight_active: bool = false
var center_flash_color: Color = Color(1,1,1,0)
var center_flash_time: float = 0.0
var center_flash_duration: float = 0.5
var last_pile_size: int = 0

# Colors per player index
var player_colors: Array[Color] = [Color.hex(0x3dbbffff), Color.hex(0xff6f61ff), Color.hex(0x7ed957ff), Color.hex(0xffc107ff)]

# Animation container
var overlay_layer := CanvasLayer.new()
var hud_label: Label = null
# Game timer label (under HUD at upper-left)
var timer_label: Label = null
# Per-player labels showing remaining tap challenges
var challenge_labels: Array[Label] = []
# Label showing remaining chances during a face-card challenge
var chances_label: Label = null
# Easy mode hint label (shown on tap window in EASY difficulty)
var easy_hint_label: Label = null
# Pause overlay and countdown
var pause_panel: Panel = null
var countdown_label: Label = null
# Tutorial overlay nodes
var tutorial_panel: Panel = null
var tutorial_visible: bool = false
# Game over overlay
var game_over_panel: Panel = null
var _scores_container: VBoxContainer = null
var _winner_label: Label = null
# Timer state
var _match_started: bool = false
var _match_start_msec: int = 0
var _final_elapsed_msec: int = 0
# HUD update throttling
var _timer_accum: float = 0.0
# Simple token pooling to reduce allocations
var _token_pool: Array[Label] = []
var _active_tokens: Array[Label] = []

# Initialize overlay layers, HUD labels, panels, and load persisted UI settings.
func _ready() -> void:
	add_child(overlay_layer)
	# Ensure overlay renders above UI CanvasLayer (which defaults to layer 0)
	overlay_layer.layer = 1
	set_process(true)
	# Create a simple HUD label to show human hand count and score
	hud_label = Label.new()
	overlay_layer.add_child(hud_label)
	# Position top-left with some padding
	hud_label.anchor_left = 0
	hud_label.anchor_top = 0
	hud_label.anchor_right = 0
	hud_label.anchor_bottom = 0
	hud_label.position = Vector2(16, 12)
	hud_label.add_theme_color_override("font_color", Color.WHITE)
	hud_label.text = ""
	# Create a timer label under the HUD (upper-left, beneath Score)
	timer_label = Label.new()
	overlay_layer.add_child(timer_label)
	# Position near top-left, directly beneath the HUD label
	timer_label.anchor_left = 0
	timer_label.anchor_top = 0
	timer_label.anchor_right = 0
	timer_label.anchor_bottom = 0
	timer_label.position = Vector2(16, 38)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	timer_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	timer_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	timer_label.add_theme_constant_override("outline_size", 3)
	timer_label.text = "00:00"
	# Create chances label near center (initially hidden)
	chances_label = Label.new()
	overlay_layer.add_child(chances_label)
	chances_label.add_theme_color_override("font_color", Color(1,0.95,0.5,1))
	chances_label.visible = false
	# Create easy hint label (initially hidden)
	easy_hint_label = Label.new()
	overlay_layer.add_child(easy_hint_label)
	easy_hint_label.add_theme_color_override("font_color", Color(0.7,1,0.7,1))
	easy_hint_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.8))
	easy_hint_label.add_theme_constant_override("outline_size", 3)
	easy_hint_label.visible = false
	easy_hint_label.text = "Tap Now!"
	# Build pause overlay (initially hidden)
	_build_pause_overlay()
	# Prepare tutorial panel (but do not show unless needed)
	_build_tutorial_panel()
	# Prepare game over panel (but keep hidden)
	_build_game_over_panel()
	# Load UI settings (e.g., GUI scale multiplier)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var gui_scale_mul: float = float(cfg.get_value("ui", "gui_scale", 1.0))
	_gui_scale = clamp(gui_scale_mul, 0.75, 1.75)
	# Apply initial UI scaling and listen to resize for consistent readability
	var vp: Viewport = get_viewport()
	if vp:
		vp.size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()

# Bind references to center area, labels, player areas, and tap system; connect visual signals.
func setup(center: Area2D, center_lbl: Label, player_area_root: Node, tap_sys: Node) -> void:
	center_area = center
	center_label = center_lbl
	player_areas.clear()
	for i in range(4):
		var n := player_area_root.get_node_or_null("Player%dArea" % i)
		if n and n is Area2D:
			player_areas.append(n)
	tap_system = tap_sys
	# Try to connect to tap system signals directly
	if tap_system and tap_system.has_signal("tap_window_opened"):
		tap_system.connect("tap_window_opened", Callable(self, "_on_tap_window_opened"))
	if tap_system and tap_system.has_signal("pile_awarded"):
		tap_system.connect("pile_awarded", Callable(self, "_on_pile_awarded"))
	# Update challenges when a false tap occurs (decrements remaining)
	if tap_system and tap_system.has_signal("false_tap"):
		tap_system.connect("false_tap", Callable(self, "_on_false_tap_vis"))
	# Build per-player challenge labels
	_build_challenge_labels()

# Connect to Game signals and cache game reference for HUD/timer updates.
func bind_game(game: Node) -> void:
	# Store reference to game to read player hands/scores for HUD updates
	game_ref = game
	# Listen to game-level signals
	if game.has_signal("turn_index_changed"):
		game.connect("turn_index_changed", Callable(self, "_on_turn_index_changed"))
	elif game.has_signal("turn_changed"):
		# Fallback without index; keep previous index
		game.connect("turn_changed", Callable(self, "_on_turn_changed_name"))
	if game.has_signal("card_played"):
		game.connect("card_played", Callable(self, "_on_card_played"))
	if game.has_signal("score_awarded"):
		game.connect("score_awarded", Callable(self, "_on_score_awarded"))
	# Also update HUD when pile is cleared/awarded (hand sizes can change)
	if game.has_signal("status"):
		# Not strictly needed, but can refresh HUD on general status changes after dealing
		game.connect("status", Callable(self, "_on_status_refresh"))
		# Start or reset the timer when match officially starts (status message like "X starts")
		game.connect("status", Callable(self, "_on_game_status"))
	# Forwarded tap window opened from game if present
	if game.has_signal("tap_window_opened_vis"):
		game.connect("tap_window_opened_vis", Callable(self, "_on_tap_window_opened"))
	# Connect to challenge chances updates from Game
	if game.has_signal("challenge_chances_changed"):
		game.connect("challenge_chances_changed", Callable(self, "_on_chances_changed"))
	# Initial HUD paint
	_update_hud()
	_update_challenge_labels_text()
	_update_challenge_labels_positions()
	_update_chances_label_position()
	# Reset timer display on bind
	_match_started = false
	_match_start_msec = 0
	_final_elapsed_msec = 0
	_update_timer_label(0)

# Per-frame update to advance flashes, timer throttling, and reposition overlay elements.
func _process(delta: float) -> void:
	if center_flash_time > 0.0:
		center_flash_time -= delta
	# Always clear the flash color alpha once the timer elapses
	if center_flash_time <= 0.0:
		center_flash_color.a = 0.0
	# Throttle timer label updates to reduce HUD churn
	_timer_accum += delta
	if _timer_accum >= 0.25:
		_update_match_timer()
		_timer_accum = 0.0
	# Keep labels positioned near their anchors
	_update_challenge_labels_positions()
	_update_chances_label_position()
	_update_easy_hint_position()
	queue_redraw()

# Position the face-card chances label near the center pile each frame.
func _update_chances_label_position() -> void:
	if chances_label == null:
		return
	if center_area != null:
		var base := center_area.global_position
		chances_label.global_position = base + Vector2(-60, -86)

# Keep the EASY mode tap hint anchored above the center label when visible.
func _update_easy_hint_position() -> void:
	if easy_hint_label == null or not easy_hint_label.visible:
		return
	if center_area != null:
		var base := center_area.global_position
		# Slightly above center label
		easy_hint_label.global_position = base + Vector2(-36, -122)

# Custom drawing of center highlight, flash ring, and per-player turn indicators.
func _draw() -> void:
	# Draw center highlight
	if center_area:
		var pos := center_area.global_position
		var local := to_local(pos)
		if center_highlight_active:
			var t := float(Time.get_ticks_msec() % 600) / 600.0
			var radius := 90.0 + 10.0 * sin(TAU * t)
			draw_circle(local, radius, Color(1, 1, 0, 0.12))
			draw_arc(local, radius, 0, TAU, 48, Color(1, 1, 0, 0.8), 4.0, true)
		# Draw center flash border
		if center_flash_color.a > 0.0:
			draw_arc(local, 110.0, 0, TAU, 64, center_flash_color, 6.0, true)
	# Draw turn indicators
	for i in range(player_areas.size()):
		var pa: Area2D = player_areas[i]
		var p := to_local(pa.global_position)
		var col: Color = player_colors[i % player_colors.size()]
		var base_col: Color = col.darkened(0.2)
		draw_circle(p, 24.0, Color(base_col.r, base_col.g, base_col.b, 0.25))
		if i == active_turn_index:
			var t2 := float(Time.get_ticks_msec() % 1000) / 1000.0
			var th := 3.0 + 2.0 * sin(TAU * t2)
			draw_arc(p, 28.0, 0, TAU, 48, Color(col.r, col.g, col.b, 0.9), th, true)

# Update the active turn highlight when Game changes the current player index.
func _on_turn_index_changed(idx: int) -> void:
	active_turn_index = idx
	queue_redraw()

# Fallback hook when only a player name is provided; index highlight remains unchanged.
func _on_turn_changed_name(_name: String) -> void:
	# Unknown index, no change
	pass

# Enable center highlight and optional EASY mode hint when a valid tap window opens.
func _on_tap_window_opened() -> void:
	center_highlight_active = true
	# If game is in EASY difficulty, show a helpful tap hint near the center
	if _is_easy_difficulty():
		_show_easy_tap_hint()
	queue_redraw()

# Turn off the center highlight and hide any EASY hint once tapping is no longer valid.
func end_tap_highlight() -> void:
	center_highlight_active = false
	_hide_easy_tap_hint()
	queue_redraw()

func _on_status_refresh(_msg: String) -> void:
	# Generic refresh hook on status messages (e.g., after dealing)
	_update_hud()
	_update_challenge_labels_text()

func _on_pile_awarded(player_index: int) -> void:
	# Flash center border in the winner's color; also animate a pile token moving
	var col: Color = player_colors[player_index % player_colors.size()]
	flash_center(col, center_flash_duration)
	# Animate a small pile token
	_spawn_and_tween_token(center_area.global_position, player_areas[player_index].global_position, "Pile")
	# Stop any tap highlight (also hides easy hint if visible)
	end_tap_highlight()
	# Hand sizes likely changed; refresh HUD and per-player counts
	_update_hud()
	_update_challenge_labels_text()

## Public helper to flash center border a color for a duration
func flash_center(color: Color, duration: float = 0.25) -> void:
	center_flash_color = color
	center_flash_color.a = 1.0
	center_flash_duration = max(0.05, duration)
	center_flash_time = center_flash_duration
	queue_redraw()

func _on_card_played(player_index: int, label: String) -> void:
	# Animate a small label from player to center
	if player_index >= 0 and player_index < player_areas.size():
		_spawn_and_tween_token(player_areas[player_index].global_position, center_area.global_position, label)
	# Any card play likely closes a previous tap window visually
	end_tap_highlight()
	# Update HUD and per-player counts as hands changed
	if player_index == 0:
		_update_hud()
	_update_challenge_labels_text()

func _get_token_label() -> Label:
	if not _token_pool.is_empty():
		var lbl: Label = _token_pool.pop_back()
		if is_instance_valid(lbl):
			return lbl
	# create new if pool empty
	var n := Label.new()
	n.add_theme_color_override("font_color", Color.WHITE)
	return n

func _recycle_token(lbl: Label) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.visible = false
	lbl.modulate = Color(1,1,1,1)
	lbl.scale = Vector2.ONE
	_active_tokens.erase(lbl)
	_token_pool.append(lbl)

func _spawn_and_tween_token(from_pos: Vector2, to_pos: Vector2, text: String) -> void:
	var lbl := _get_token_label()
	lbl.text = text
	lbl.visible = true
	lbl.modulate = Color(1,1,1,1)
	if lbl.get_parent() != overlay_layer:
		overlay_layer.add_child(lbl)
	lbl.global_position = from_pos + Vector2(-12, -12)
	_active_tokens.append(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "global_position", to_pos + Vector2(-8, -8), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.2).set_delay(0.35)
	tw.finished.connect(Callable(self, "_recycle_token").bind(lbl))

func _has_property(obj: Object, prop_name: String) -> bool:
	for prop in obj.get_property_list():
		if prop.has("name") and prop.name == prop_name:
			return true
	return false

func _update_hud() -> void:
	if hud_label == null:
		return
	if game_ref == null:
		hud_label.text = ""
		return
	# Safely read human (index 0) hand size and score if available
	var hand_count := 0
	var score_val := 0
	var has_players := _has_property(game_ref, "players")
	if has_players:
		var arr = game_ref.get("players")
		if typeof(arr) == TYPE_ARRAY and arr.size() > 0 and arr[0] != null:
			var p = arr[0]
			if _has_property(p, "hand"):
				var hand_val = p.get("hand")
				if typeof(hand_val) == TYPE_ARRAY:
					hand_count = hand_val.size()
			if _has_property(p, "score"):
				var score_any = p.get("score")
				if typeof(score_any) == TYPE_INT:
					score_val = int(score_any)
	# Compose HUD text
	hud_label.text = "You — Cards: %d | Score: %d" % [hand_count, score_val]

func _on_score_awarded(player_index: int, delta: int, _reason: String, _total: int) -> void:
	# Spawn a floating "+X" near the player's area
	if player_index < 0 or player_index >= player_areas.size():
		return
	var start := player_areas[player_index].global_position
	var end := start + Vector2(0, -28)
	var txt := "+%d" % delta
	_spawn_and_tween_token(start, end, txt)
	# If human score changed, refresh HUD
	if player_index == 0:
		_update_hud()

## Animate mis-tap penalty: visually place up to `count` card tokens under the center pile.
## Returns when the last token finishes, allowing Game to pause during the sequence.
func animate_false_tap(player_index: int, count: int = 2) -> void:
	if player_index < 0 or player_index >= player_areas.size():
		return
	var from_pos := player_areas[player_index].global_position
	var to_pos := center_area.global_position if center_area else from_pos
	var actual: int = max(0, count)
	for i in range(actual):
		# Create a simple card-shaped Node2D + Polygon2D to represent the penalized card
		var card := Node2D.new()
		card.z_index = -10 # render beneath other overlay items to imply "bottom"
		overlay_layer.add_child(card)
		var width := 26.0
		var height := 36.0
		# Center pivot manually by offsetting position
		var half := Vector2(width, height) * 0.5
		card.global_position = from_pos - half
		# Main body
		var poly := Polygon2D.new()
		poly.color = Color(0.9, 0.9, 0.95, 1.0)
		poly.polygon = PackedVector2Array([Vector2(0,0), Vector2(width,0), Vector2(width,height), Vector2(0,height)])
		card.add_child(poly)
		# A thin top border/accent
		var accent := Polygon2D.new()
		accent.color = Color(0.2, 0.2, 0.25, 0.9)
		accent.polygon = PackedVector2Array([Vector2(0,0), Vector2(width,0), Vector2(width,2), Vector2(0,2)])
		card.add_child(accent)
		# First tween: move the card to the center pile
		var tw := create_tween()
		tw.tween_property(card, "global_position", to_pos - half, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await tw.finished
		# Second tween: slide slightly downward and fade to suggest going under the pile
		var tw2 := create_tween()
		tw2.tween_property(card, "global_position:y", (to_pos - half).y + 10.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw2.parallel().tween_property(card, "modulate:a", 0.0, 0.18)
		await tw2.finished
		card.queue_free()
		# small stagger between cards moving
		if i < actual - 1:
			await get_tree().create_timer(0.08).timeout
	# After the mis-tap animation, refresh challenge counts (already decremented in model)
	_update_challenge_labels_text()


# Build or rebuild labels to display per-player tap challenges
func _build_challenge_labels() -> void:
	# Clear existing labels
	for lbl in challenge_labels:
		if lbl and is_instance_valid(lbl):
			lbl.queue_free()
	challenge_labels.clear()
	# Create one label per player area
	for i in range(player_areas.size()):
		var lbl := Label.new()
		lbl.text = ""
		lbl.add_theme_color_override("font_color", Color(1,1,0.9,1))
		overlay_layer.add_child(lbl)
		challenge_labels.append(lbl)
	# Initial content and positioning
	_update_challenge_labels_text()
	_update_challenge_labels_positions()

# Position the labels near each player's area each frame (in case layout moves)
func _update_challenge_labels_positions() -> void:
	if player_areas.is_empty() or challenge_labels.is_empty():
		return
	for i in range(min(player_areas.size(), challenge_labels.size())):
		var pa: Area2D = player_areas[i]
		var lbl: Label = challenge_labels[i]
		if pa == null or lbl == null:
			continue
		# Offset slightly below the player's circle indicator
		var base := pa.global_position
		lbl.global_position = base + Vector2(-60, 34)

# Update the text on the per-player challenge labels from the game model
func _update_challenge_labels_text() -> void:
	if game_ref == null:
		return
	if not _has_property(game_ref, "players"):
		return
	var arr = game_ref.get("players")
	if typeof(arr) != TYPE_ARRAY:
		return
	for i in range(min(arr.size(), challenge_labels.size())):
		var p = arr[i]
		var challenges := 0
		var hand_size := 0
		if p != null:
			if _has_property(p, "tap_challenges_left"):
				var any = p.get("tap_challenges_left")
				if typeof(any) == TYPE_INT:
					challenges = int(any)
			if _has_property(p, "hand"):
				var hand_val = p.get("hand")
				if typeof(hand_val) == TYPE_ARRAY:
					hand_size = hand_val.size()
		var name_str := "P%d" % i
		if p != null and _has_property(p, "name"):
			var nm = p.get("name")
			if typeof(nm) == TYPE_STRING:
				name_str = nm
		challenge_labels[i].text = "%s — Cards: %d | Challenges: %d" % [name_str, hand_size, challenges]

# Respond to false_tap signal by refreshing the label texts
func _on_false_tap_vis(_player_index: int) -> void:
	_update_challenge_labels_text()

# Update chances label when Game notifies chances changed
func _on_chances_changed(chances_left: int) -> void:
	if chances_label == null:
		return
	if chances_left > 0:
		chances_label.text = "Chances left: %d" % chances_left
		chances_label.visible = true
		_update_chances_label_position()
	else:
		chances_label.visible = false


# Helpers for easy mode hint
func _is_easy_difficulty() -> bool:
	if game_ref == null:
		return false
	if not _has_property(game_ref, "difficulty"):
		return false
	var d = game_ref.get("difficulty")
	# EASY is 0 in Game.Difficulty enum
	return typeof(d) == TYPE_INT and int(d) == 0

func _show_easy_tap_hint() -> void:
	if easy_hint_label == null:
		return
	easy_hint_label.visible = true
	_update_easy_hint_position()
	# Pulse animate the label for a brief duration
	easy_hint_label.modulate = Color(1,1,1,1)
	var tw := create_tween()
	tw.tween_property(easy_hint_label, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(easy_hint_label, "scale", Vector2(1, 1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Auto-fade after a short delay if tap window persists
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(easy_hint_label, "modulate:a", 0.0, 0.6).set_delay(0.9)

func _hide_easy_tap_hint() -> void:
	if easy_hint_label == null:
		return
	easy_hint_label.visible = false
	easy_hint_label.modulate.a = 1.0
	easy_hint_label.scale = Vector2.ONE

# Helpers to persist UI settings
var _gui_scale: float = 1.0

func set_gui_scale_multiplier(s: float) -> void:
	_gui_scale = clamp(s, 0.75, 1.75)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("ui", "gui_scale", _gui_scale)
	cfg.save("user://settings.cfg")
	_apply_ui_scale()

func get_gui_scale_multiplier() -> float:
	return _gui_scale

# ===== Game Timer =====
func _on_game_status(msg: String) -> void:
	# Start timer when we get a message like "<name> starts"
	if typeof(msg) == TYPE_STRING and msg.findn(" starts") != -1:
		_match_started = true
		_match_start_msec = Time.get_ticks_msec()
		_final_elapsed_msec = 0
		_update_timer_label(0)

func _update_match_timer() -> void:
	if timer_label == null:
		return
	if game_ref != null and _has_property(game_ref, "game_over"):
		var over_any = game_ref.get("game_over")
		var is_over: bool = typeof(over_any) == TYPE_BOOL and bool(over_any)
		if is_over:
			# Freeze timer at final elapsed if just ended
			if _match_started:
				_final_elapsed_msec = Time.get_ticks_msec() - _match_start_msec
				_match_started = false
				_update_timer_label(_final_elapsed_msec)
			return
	# If match is running, update display
	if _match_started:
		var elapsed := Time.get_ticks_msec() - _match_start_msec
		_update_timer_label(elapsed)
	elif _final_elapsed_msec > 0:
		# Keep showing the final time after match ends
		_update_timer_label(_final_elapsed_msec)

func _update_timer_label(elapsed_msec: int) -> void:
	var total_sec := int(round(elapsed_msec / 1000.0))
	var minutes := int(total_sec / 60.0)
	var seconds := total_sec % 60
	var txt := "%02d:%02d" % [minutes, seconds]
	if timer_label != null:
		timer_label.text = txt

# ===== Game Over Overlay =====
func _build_game_over_panel() -> void:
	if game_over_panel != null and is_instance_valid(game_over_panel):
		return
	game_over_panel = Panel.new()
	overlay_layer.add_child(game_over_panel)
	game_over_panel.visible = false
	game_over_panel.anchor_left = 0
	game_over_panel.anchor_top = 0
	game_over_panel.anchor_right = 1
	game_over_panel.anchor_bottom = 1
	game_over_panel.offset_left = 0
	game_over_panel.offset_top = 0
	game_over_panel.offset_right = 0
	game_over_panel.offset_bottom = 0
	game_over_panel.add_theme_color_override("panel", Color(0,0,0,0.8))
	# Content
	var vb := VBoxContainer.new()
	game_over_panel.add_child(vb)
	vb.anchor_left = 0
	vb.anchor_top = 0
	vb.anchor_right = 1
	vb.anchor_bottom = 1
	vb.offset_left = 0
	vb.offset_top = 0
	vb.offset_right = 0
	vb.offset_bottom = 0
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	# Title
	var title := Label.new()
	title.text = "Game Over"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1,1,1,1))
	title.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	title.add_theme_constant_override("outline_size", 3)
	vb.add_child(title)
	# Winner label
	_winner_label = Label.new()
	_winner_label.text = ""
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.add_theme_color_override("font_color", Color(1,0.95,0.7,1))
	_winner_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	_winner_label.add_theme_constant_override("outline_size", 3)
	vb.add_child(_winner_label)
	# Scores list
	_scores_container = VBoxContainer.new()
	_scores_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_scores_container.add_theme_constant_override("separation", 6)
	vb.add_child(_scores_container)
	# Buttons row
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var play_again := Button.new()
	play_again.text = "Play Again"
	hb.add_child(play_again)
	play_again.pressed.connect(_on_play_again_pressed)
	var main_menu := Button.new()
	main_menu.text = "Main Menu"
	hb.add_child(main_menu)
	main_menu.pressed.connect(_on_main_menu_pressed)

func show_game_over_panel(scores: Array, winner_name: String) -> void:
	if game_over_panel == null:
		_build_game_over_panel()
	# Clear any previous entries
	for c in _scores_container.get_children():
		_scores_container.remove_child(c)
		c.queue_free()
	# Winner line
	_winner_label.text = "%s wins!" % winner_name
	# Populate scores
	# Expecting scores as array of dictionaries with keys name, score
	for item in scores:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = str(item.get("name", "Player")) + ":"
		name_lbl.add_theme_color_override("font_color", Color(1,1,1,0.95))
		var score_lbl := Label.new()
		score_lbl.text = str(item.get("score", 0))
		score_lbl.add_theme_color_override("font_color", Color(0.8,1,0.8,1))
		row.add_child(name_lbl)
		row.add_child(score_lbl)
		_scores_container.add_child(row)
	game_over_panel.visible = true

func _on_play_again_pressed() -> void:
	# Hide panel and restart
	if game_over_panel != null:
		game_over_panel.visible = false
	# Reset timer display and state
	_match_started = false
	_match_start_msec = 0
	_final_elapsed_msec = 0
	_update_timer_label(0)
	if game_ref != null and game_ref.has_method("start_new_game"):
		game_ref.start_new_game()

func _on_main_menu_pressed() -> void:
	if game_ref != null and game_ref.has_method("_return_to_menu"):
		game_ref._return_to_menu()

# ===== Pause/Resume Overlay =====
func _build_pause_overlay() -> void:
	if pause_panel != null and is_instance_valid(pause_panel):
		return
	pause_panel = Panel.new()
	overlay_layer.add_child(pause_panel)
	pause_panel.visible = false
	pause_panel.anchor_left = 0
	pause_panel.anchor_top = 0
	pause_panel.anchor_right = 1
	pause_panel.anchor_bottom = 1
	pause_panel.offset_left = 0
	pause_panel.offset_top = 0
	pause_panel.offset_right = 0
	pause_panel.offset_bottom = 0
	pause_panel.add_theme_color_override("panel", Color(0,0,0,0.65))
	# Label for paused + countdown
	var vb := VBoxContainer.new()
	pause_panel.add_child(vb)
	vb.anchor_left = 0
	vb.anchor_top = 0
	vb.anchor_right = 1
	vb.anchor_bottom = 1
	vb.offset_left = 0
	vb.offset_right = 0
	vb.offset_top = 0
	vb.offset_bottom = 0
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paused_lbl := Label.new()
	paused_lbl.text = "Paused"
	paused_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_lbl.add_theme_color_override("font_color", Color(1,1,1,0.95))
	paused_lbl.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	paused_lbl.add_theme_constant_override("outline_size", 3)
	vb.add_child(paused_lbl)
	countdown_label = Label.new()
	countdown_label.text = ""
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_color_override("font_color", Color(1,0.95,0.7,1))
	countdown_label.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	countdown_label.add_theme_constant_override("outline_size", 3)
	vb.add_child(countdown_label)

func show_pause_overlay(show_flag: bool) -> void:
	if pause_panel == null:
		_build_pause_overlay()
	pause_panel.visible = show_flag
	if not show_flag and countdown_label != null:
		countdown_label.text = ""

func resume_countdown_and_wait(seconds: int = 3) -> void:
	if pause_panel == null:
		_build_pause_overlay()
	pause_panel.visible = true
	# simple scaled countdown
	for i in range(seconds, 0, -1):
		if countdown_label != null:
			countdown_label.text = str(i)
			countdown_label.scale = Vector2.ONE
			var tw := create_tween()
			tw.tween_property(countdown_label, "scale", Vector2(1.3,1.3), 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			await get_tree().create_timer(0.7).timeout
	# Hide overlay at end
	show_pause_overlay(false)

# ===== Tutorial Overlay =====
## Emitted when the tutorial overlay is dismissed by the user.
signal tutorial_dismissed

func should_show_tutorial() -> bool:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var seen := bool(cfg.get_value("tutorial", "seen_tutorial", false))
	return not seen

func show_tutorial_and_wait() -> void:
	if tutorial_panel == null:
		_build_tutorial_panel()
	_show_tutorial_panel(true)
	# Wait for dismissal signal
	await tutorial_dismissed

func _build_tutorial_panel() -> void:
	if tutorial_panel != null and is_instance_valid(tutorial_panel):
		return
	tutorial_panel = Panel.new()
	overlay_layer.add_child(tutorial_panel)
	tutorial_panel.visible = false
	tutorial_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tutorial_panel.anchor_left = 0
	tutorial_panel.anchor_top = 0
	tutorial_panel.anchor_right = 1
	tutorial_panel.anchor_bottom = 1
	tutorial_panel.offset_left = 0
	tutorial_panel.offset_top = 0
	tutorial_panel.offset_right = 0
	tutorial_panel.offset_bottom = 0
	tutorial_panel.add_theme_color_override("panel", Color(0,0,0,0.82))
	# Build content
	var vb2 := VBoxContainer.new()
	tutorial_panel.add_child(vb2)
	vb2.anchor_left = 0
	vb2.anchor_top = 0
	vb2.anchor_right = 1
	vb2.anchor_bottom = 1
	vb2.offset_left = 0
	vb2.offset_right = 0
	vb2.offset_top = 0
	vb2.offset_bottom = 0
	vb2.alignment = BoxContainer.ALIGNMENT_CENTER
	vb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Title
	var title := Label.new()
	title.text = "How to Tap"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1,1,1,1))
	title.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	title.add_theme_constant_override("outline_size", 3)
	vb2.add_child(title)
	# Examples container
	var examples := VBoxContainer.new()
	vb2.add_child(examples)
	examples.alignment = BoxContainer.ALIGNMENT_CENTER
	examples.add_theme_constant_override("separation", 12)
	# Double example
	var dbl := _make_example_row("Double", ["7", "7"])
	examples.add_child(dbl)
	# Sandwich example
	var snd := _make_example_row("Sandwich", ["9", "J", "9"])
	examples.add_child(snd)
	# Continue hint
	var hint := Label.new()
	hint.text = "Tap anywhere to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1,1,1,0.9))
	vb2.add_child(hint)
	# Input to dismiss
	tutorial_panel.gui_input.connect(_on_tutorial_gui_input)

func _make_example_row(example_title: String, ranks: Array) -> Control:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = example_title + ":"
	lbl.add_theme_color_override("font_color", Color(1,1,0.85,1))
	hb.add_child(lbl)
	for r in ranks:
		var card := _make_card_visual(str(r))
		hb.add_child(card)
		# Animated arrow between cards
		if r != ranks.back():
			var arrow := _make_arrow()
			hb.add_child(arrow)
	return hb

func _make_card_visual(text: String) -> Control:
	var b := ColorRect.new()
	b.color = Color(1,1,1,1)
	b.custom_minimum_size = Vector2(36, 50)
	var inner := Label.new()
	inner.text = text
	inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.add_theme_color_override("font_color", Color(0,0,0,1))
	b.add_child(inner)
	inner.anchor_left = 0
	inner.anchor_top = 0
	inner.anchor_right = 1
	inner.anchor_bottom = 1
	inner.offset_left = 0
	inner.offset_top = 0
	inner.offset_right = 0
	inner.offset_bottom = 0
	return b

func _make_arrow() -> Control:
	var arrow := Label.new()
	arrow.text = "➜"
	arrow.add_theme_color_override("font_color", Color(1,1,0.5,1))
	# subtle animation
	var tw := create_tween()
	arrow.scale = Vector2(1,1)
	tw.set_loops()
	tw.tween_property(arrow, "scale", Vector2(1.15,1.15), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(arrow, "scale", Vector2(1,1), 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return arrow

func _on_tutorial_gui_input(event: InputEvent) -> void:
	if not tutorial_visible:
		return
	if event is InputEventMouseButton and event.pressed:
		_show_tutorial_panel(false)
	elif event.is_action_pressed("ui_tap"):
		_show_tutorial_panel(false)

func _show_tutorial_panel(show_flag: bool) -> void:
	tutorial_visible = show_flag
	if tutorial_panel == null:
		return
	tutorial_panel.visible = show_flag
	# Persist seen flag on dismiss
	if not show_flag:
		var cfg := ConfigFile.new()
		cfg.load("user://settings.cfg")
		cfg.set_value("tutorial", "seen_tutorial", true)
		cfg.save("user://settings.cfg")
		emit_signal("tutorial_dismissed")

# Responsive UI scaling to keep text readable across screen sizes
const BASE_FONT_SIZES := {
	"hud": 18,
	"timer": 28,
	"chances": 24,
	"hint": 26,
	"countdown": 64
}

func _apply_ui_scale() -> void:
	# Base at 1280x720; scale by the smaller axis ratio to keep balance
	var vp_size: Vector2i = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	var scale_w: float = float(vp_size.x) / 1280.0
	var scale_h: float = float(vp_size.y) / 720.0
	var s: float = clamp(min(scale_w, scale_h), 0.75, 1.75) * _gui_scale
	# Apply to known overlay labels
	if hud_label:
		hud_label.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["hud"] * s)))
	if timer_label:
		timer_label.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["timer"] * s)))
	if chances_label:
		chances_label.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["chances"] * s)))
	if easy_hint_label:
		easy_hint_label.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["hint"] * s)))
	if countdown_label:
		countdown_label.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["countdown"] * s)))
	# Also scale any active token labels
	for lbl in _active_tokens:
		if lbl and lbl is Label:
			lbl.add_theme_font_size_override("font_size", int(round(BASE_FONT_SIZES["hud"] * s)))
