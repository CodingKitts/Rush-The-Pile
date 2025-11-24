# TapSystem.gd — Detect and resolve tap events (doubles, sandwiches), including tie-break logic
#
# Responsibilities
# - Inspect the center pile after each card to determine if a valid tap pattern exists
# - Open/close a tap window and accept human/AI tap attempts
# - Schedule AI tap attempts using AIProfile reaction ranges (with optional assist modifiers)
# - Resolve multiple taps deterministically with a small tie window biased toward the human
# - Award the pile to the winner and emit signals so Game/UI can react
#
extends Node
class_name TapSystem

# When tearing down (e.g., scene change), set this to true to prevent deferred callbacks
var _shutting_down: bool = false

## Emitted when a new valid tap opportunity becomes live (double/sandwich)
signal tap_window_opened()
## Emitted after center pile is awarded to a player (via tap or challenge)
signal pile_awarded(player_index: int)
## Emitted when a player taps without a valid window; Game may apply penalty animations
signal false_tap(player_index: int)
## Emitted when the center pile is physically moved to a player and cleared
## Parameters: player_index, card_count, total_value, reason ("tap" or "challenge")
signal pile_cleared(player_index: int, card_count: int, total_value: int, reason: String)

var tap_window_open: bool = false
var tap_valid: bool = false
var tap_winner_index: int = -1

# Rule toggles
var enable_doubles: bool = true
var enable_sandwiches: bool = true

# Tie-break configuration (ms) — within this window, favor the human when taps collide
var tie_break_ms: int = 20

var _players: Array = []
var _center_pile: Array = []
var _get_profile: Callable
var _num_players: int = 0
var _message_fn: Callable
var _update_center_label: Callable
var _rng: RandomNumberGenerator
var _last_award_reason: String = "tap"
# Assisted match modifiers for AI tap timing
var _assist_reaction_multiplier: float = 1.0
var _assist_extra_delay: float = 0.0

# Optional active-player callback (to ignore eliminated players)
var _is_active: Callable = Callable()

# Internal tie-break tracking
var _first_tap_index: int = -1
var _first_tap_time_msec: int = 0
var _tie_pending: bool = false
var _tie_timer: SceneTreeTimer = null

## Wire references to players/pile and callbacks, set RNG and active-player filter.
func setup(players: Array, center_pile: Array, get_profile: Callable, num_players: int, message_fn: Callable, update_center_label: Callable, rng: RandomNumberGenerator = null, is_active_callable: Callable = Callable()) -> void:
	_players = players
	_center_pile = center_pile
	_get_profile = get_profile
	_num_players = num_players
	_message_fn = message_fn
	_update_center_label = update_center_label
	_rng = rng
	_is_active = is_active_callable
	_shutting_down = false

## Configure temporary assist to slow AI tap reactions (multiplier >=0.5, extra delay in seconds).
func set_assist_modifiers(multiplier: float, extra_delay: float) -> void:
	_assist_reaction_multiplier = max(0.5, multiplier)
	_assist_extra_delay = max(0.0, extra_delay)

## Cleanly stop timers/callbacks and invalidate callables to avoid calling freed objects.
func teardown() -> void:
	_shutting_down = true
	# Close any active tap window and disable further processing
	tap_window_open = false
	tap_valid = false
	_tie_pending = false
	_tie_timer = null
	# Invalidate external callables and references to break links
	_get_profile = Callable()
	_message_fn = Callable()
	_update_center_label = Callable()
	_is_active = Callable()
	# Optionally drop references to arrays to help GC
	_players = []
	_center_pile = []

## Evaluate the pile after a card is played and open/close a tap window accordingly.
func on_card_added() -> void:
	# Evaluate tap event after a card is played
	tap_valid = _is_tap_event()
	if tap_valid:
		_open_tap_window()
	else:
		tap_window_open = false

## Attempt to tap from the given player index. Handles false taps and tie-window resolution.
func attempt_tap(player_index: int) -> void:
	if _shutting_down:
		return
	# Ignore taps from inactive/eliminated players
	if _is_active.is_valid() and not _is_active.call(player_index):
		return
	if not (tap_window_open and tap_valid):
		# False tap attempt. Consume a tap challenge if any remain; otherwise ignore attempt.
		if player_index >= 0 and player_index < _players.size():
			var p: Player = _players[player_index]
			if p.tap_challenges_left <= 0:
				# Announce that the player has no challenges left and ignore
				if _message_fn.is_valid():
					_message_fn.call("%s has no tap challenges left" % p.name)
				return
			# Decrement remaining challenges on an incorrect tap
			p.tap_challenges_left -= 1
		# Do not apply the card penalty here; Game handles it via signal to allow pause + animation.
		false_tap.emit(player_index)
		return
	# valid and open
	var now_ms: int = Time.get_ticks_msec()
	# If no tap recorded yet for this window, start tie window and record the first
	if not _tie_pending:
		_tie_pending = true
		_first_tap_index = player_index
		_first_tap_time_msec = now_ms
		# Start a tiny timer to allow other taps to arrive within tie_break_ms
		_start_tie_timer()
		return
	# Second (or subsequent) tap arrived before tie window finalized
	var dt: int = abs(now_ms - _first_tap_time_msec)
	var winner := _first_tap_index
	var used_tie_break := false
	if dt <= tie_break_ms:
		# Within tie window: bias toward human if involved
		if player_index == 0 or _first_tap_index == 0:
			winner = 0
			used_tie_break = true
		else:
			# No human involved -> earliest wins (already winner)
			pass
	else:
		# Outside tie window -> earliest tap wins (first)
		pass
	_finalize_award(winner, used_tie_break)

## Award the pile to player_index due to a challenge outcome (not a tap).
func award_pile_to(player_index: int) -> void:
	if _shutting_down:
		return
	_last_award_reason = "challenge"
	_award_center_to_player(player_index)
	pile_awarded.emit(player_index)

## Clear any tap/tie state so the next pile starts with no active window.
func _reset_pattern_state() -> void:
	# Fully reset tap detection/window and tie state so a new pile starts clean
	tap_window_open = false
	tap_valid = false
	tap_winner_index = -1
	_tie_pending = false
	_first_tap_index = -1
	_first_tap_time_msec = 0
	_tie_timer = null

## Return true if the current center pile shows a valid tap pattern (double/sandwich).
func _is_tap_event() -> bool:
	if _center_pile.size() < 2:
		return false
	var n := _center_pile.size()
	var last = _center_pile[n-1]
	var prev = _center_pile[n-2]
	if enable_doubles and last.rank == prev.rank:
		return true
	if enable_sandwiches and n >= 3:
		var prev2 = _center_pile[n-3]
		if prev2.rank == last.rank:
			return true
	return false

## Open a new tap window for doubles/sandwich and schedule AI tap attempts.
func _open_tap_window() -> void:
	if _shutting_down:
		return
	tap_window_open = true
	tap_valid = true
	tap_winner_index = -1
	# Reset tie tracking
	_first_tap_index = -1
	_first_tap_time_msec = 0
	_tie_pending = false
	_tie_timer = null
	tap_window_opened.emit()
	# Schedule AI reactions
	for i in range(1, _num_players):
		# Skip eliminated/inactive players if callback provided
		if _is_active.is_valid() and not _is_active.call(i):
			continue
		var profile: AIProfile = _get_profile.call(i)
		var delay := profile.pick_tap_reaction(_rng)
		# Enforce a global minimum delay for AI on real tap events to favor the human
		delay = max(delay, 1.5)
		# Apply assisted-match modifiers
		delay = delay * _assist_reaction_multiplier + _assist_extra_delay
		_call_deferred_ai_tap(i, delay, profile)

## After a delay based on AI profile, make AI i attempt a tap unless window closed or missed.
func _call_deferred_ai_tap(i: int, delay: float, profile: AIProfile) -> void:
	if _shutting_down:
		return
	var timer := get_tree().create_timer(delay)
	await timer.timeout
	if _shutting_down:
		return
	if not tap_window_open:
		return
	if tap_valid:
		var r := _rng if _rng != null else RandomNumberGenerator.new()
		if _rng == null:
			r.randomize()
		if r.randf() < profile.miss_tap_probability:
			return
		attempt_tap(i)

## Start a short timer (tie_break_ms) to allow competing taps; earliest/human favored wins on expiry.
func _start_tie_timer() -> void:
	# Create a short timer equal to tie_break_ms; when it expires, if still pending, award to first tap
	var d: float = max(0.0, float(tie_break_ms) / 1000.0)
	_tie_timer = get_tree().create_timer(d)
	await _tie_timer.timeout
	if _shutting_down:
		return
	# If already resolved or window closed, ignore
	if not tap_window_open or not tap_valid or not _tie_pending or tap_winner_index != -1:
		return
	_finalize_award(_first_tap_index, false)

## Close the window and deterministically award the pile, optionally noting human-biased tie-break.
func _finalize_award(player_index: int, used_tie_break: bool) -> void:
	if _shutting_down:
		return
	# Close window and award pile deterministically
	_tie_pending = false
	tap_winner_index = player_index
	tap_window_open = false
	_last_award_reason = "tap"
	if used_tie_break and _message_fn.is_valid():
		_message_fn.call("Tie-break: Human win")
	_award_center_to_player(player_index)
	tap_valid = false
	pile_awarded.emit(player_index)

## Move all cards from center to the winner's hand, clear pile, and emit pile_cleared.
func _award_center_to_player(player_index: int) -> void:
	if _shutting_down:
		return
	if _center_pile.is_empty():
		return
	# collect stats before moving
	var count := _center_pile.size()
	var total_value := 0
	for c in _center_pile:
		if c is Card:
			total_value += c.get_value()
	var p: Player = _players[player_index]
	p.receive_cards(_center_pile)
	_center_pile.clear()
	# Reset any tap pattern/window state so the next pile starts fresh
	_reset_pattern_state()
	if _update_center_label.is_valid():
		_update_center_label.call()
	if _message_fn.is_valid():
		_message_fn.call("%s takes the pile" % p.name)
	pile_cleared.emit(player_index, count, total_value, _last_award_reason)
