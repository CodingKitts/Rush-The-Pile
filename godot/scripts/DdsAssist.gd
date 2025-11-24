# DdsAssist.gd — Encapsulates Dynamic Difficulty Assist (DDS)
extends Node
class_name DdsAssist

## Emitted when DDS activation toggles; UI can show/hide assist indicator
signal dds_active_changed(active: bool)

## Number of missed valid tap windows within miss_window_sec to trigger DDS
@export var miss_threshold: int = 3
## Sliding window (seconds) for counting missed tap windows
@export var miss_window_sec: float = 60.0
## Number of false taps within false_window_sec to trigger DDS
@export var false_threshold: int = 2
## Sliding window (seconds) for counting false taps
@export var false_window_sec: float = 12.0
## How long DDS remains active once triggered (seconds)
@export var duration_sec: float = 45.0
# Extra delay added to AI tap reaction when DDS is active (seconds)
@export var ai_extra_delay: float = 0.035

## True while DDS is currently active
var _active: bool = false
## Wall-clock msec timestamp when DDS will auto-deactivate
var _expires_msec: int = 0
## Recent timestamps (msec) of missed valid tap windows
var _missed_tap_times: Array[int] = []
## Recent timestamps (msec) of false taps
var _false_tap_times: Array[int] = []

## Reference to TapSystem to apply reaction modifiers
var _tap_system: TapSystem = null
## Callback for status banner messages
var _status_cb: Callable
## Base multiplier applied to AI tap reactions (1.0 = unchanged)
var _base_multiplier_tap: float = 1.0
## Base extra delay (seconds) added to AI tap reactions
var _base_extra_delay: float = 0.0

## Initialize references and base modifiers. ai_delay is the DDS-specific added delay in seconds.
func setup(tap_system: TapSystem, status_cb: Callable, base_multiplier_tap: float, base_extra_delay: float, ai_delay: float) -> void:
	_tap_system = tap_system
	_status_cb = status_cb
	_base_multiplier_tap = max(0.5, base_multiplier_tap)
	_base_extra_delay = max(0.0, base_extra_delay)
	ai_extra_delay = max(0.0, ai_delay)
	# Ensure tap system reflects base values at start
	_apply_assist_modifiers(_base_multiplier_tap, _base_extra_delay)

## Return true if DDS is currently active.
func is_active() -> bool:
	return _active

## Clear tracked events, deactivate DDS, and restore base modifiers.
func reset() -> void:
	_missed_tap_times.clear()
	_false_tap_times.clear()
	_deactivate()
	# Restore base modifiers
	_apply_assist_modifiers(_base_multiplier_tap, _base_extra_delay)

## Record that the human missed a valid tap window and check if DDS should activate.
func record_missed_window() -> void:
	var now := Time.get_ticks_msec()
	_missed_tap_times.append(now)
	_trim_old_entries(_missed_tap_times, miss_window_sec)
	_check_thresholds()

## Record that the human made a false tap and check if DDS should activate.
func record_false_tap() -> void:
	var now := Time.get_ticks_msec()
	_false_tap_times.append(now)
	_trim_old_entries(_false_tap_times, false_window_sec)
	_check_thresholds()

## Per-frame watcher that auto-deactivates DDS when its duration expires.
func _process(_delta: float) -> void:
	if _active and Time.get_ticks_msec() >= _expires_msec:
		_deactivate()

## Check recent misses/false taps against thresholds, toggling DDS accordingly.
func _check_thresholds() -> void:
	if _active:
		# refresh duration
		_expires_msec = Time.get_ticks_msec() + int(duration_sec * 1000.0)
		return
	if _missed_tap_times.size() >= miss_threshold or _false_tap_times.size() >= false_threshold:
		_activate()

## Activate DDS, apply extra AI delay, announce status, and start expiry countdown.
func _activate() -> void:
	_active = true
	_expires_msec = Time.get_ticks_msec() + int(duration_sec * 1000.0)
	_apply_assist_modifiers(_base_multiplier_tap, _base_extra_delay + ai_extra_delay)
	if _status_cb.is_valid():
		_status_cb.call("Focus assist active")
	dds_active_changed.emit(true)

## Deactivate DDS, restore base modifiers, and notify UI via signal and status.
func _deactivate() -> void:
	if not _active:
		return
	_active = false
	_apply_assist_modifiers(_base_multiplier_tap, _base_extra_delay)
	if _status_cb.is_valid():
		_status_cb.call("Focus assist ended")
	dds_active_changed.emit(false)

## Drop timestamps older than window_sec from the front of the given array.
func _trim_old_entries(arr: Array[int], window_sec: float) -> void:
	var cutoff := Time.get_ticks_msec() - int(window_sec * 1000.0)
	while arr.size() > 0 and arr[0] < cutoff:
		arr.pop_front()

## Apply current assist multipliers to the TapSystem, if available.
func _apply_assist_modifiers(multiplier: float, extra_delay: float) -> void:
	if _tap_system != null and _tap_system.has_method("set_assist_modifiers"):
		_tap_system.set_assist_modifiers(multiplier, extra_delay)
