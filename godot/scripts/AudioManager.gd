# AudioManager.gd — Minimal synthesized SFX + haptics manager
#
# Responsibilities
# - Generate short sound effects procedurally (no audio assets required)
# - Provide light haptics wrappers for mobile vibration
# - Persist/restore SFX volume and haptics toggle to user://settings.cfg
#
extends Node
class_name AudioManager

## Minimal synthesized SFX using AudioStreamGenerator
## Exposed methods:
## - play_card_flip()
## - play_tap_success()
## - play_error_buzz()
## - play_pile_whoosh()
## - vibrate_light()
## - vibrate_warning()
## Volume control:
## - set_master_volume_linear(0..1)
## - get_master_volume_linear()
## - set_sfx_volume_linear(0..1)
## - get_sfx_volume_linear()
## Haptics control:
## - set_haptics_enabled(bool)
## - get_haptics_enabled()
## Persists to user://settings.cfg (audio.sfx_vol, audio.master_vol read; haptics.enabled)

var _mix_rate: float = 44100.0
var _buffer_len: float = 0.25

var _sfx_volume_linear: float = 0.8
var _master_volume_linear_default: float = 1.0
var _haptics_enabled: bool = true

func _ready() -> void:
	_load_settings()

func set_sfx_volume_linear(v: float) -> void:
	_sfx_volume_linear = clamp(v, 0.0, 1.0)
	_save_settings()

func get_sfx_volume_linear() -> float:
	return _sfx_volume_linear

func set_haptics_enabled(flag: bool) -> void:
	_haptics_enabled = bool(flag)
	_save_settings()

func get_haptics_enabled() -> bool:
	return _haptics_enabled

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	if err == OK:
		_sfx_volume_linear = float(cfg.get_value("audio", "sfx_vol", _sfx_volume_linear))
		_haptics_enabled = bool(cfg.get_value("haptics", "enabled", _haptics_enabled))
	# Apply master volume from settings if present
	if err == OK and cfg.has_section_key("audio", "master_vol"):
		var m_lin: float = float(cfg.get_value("audio", "master_vol", _master_volume_linear_default))
		AudioServer.set_bus_volume_db(0, linear_to_db(clamp(m_lin, 0.0, 1.0)))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "sfx_vol", _sfx_volume_linear)
	# Persist current master volume as well so UI can restore it on next boot
	cfg.set_value("audio", "master_vol", get_master_volume_linear())
	cfg.set_value("haptics", "enabled", _haptics_enabled)
	# Do not overwrite master here; menu handles it
	cfg.save("user://settings.cfg")

## Master (Music) volume helpers
func set_master_volume_linear(v: float) -> void:
	var lin: float = clamp(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(lin))
	_save_settings()

func get_master_volume_linear() -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(0))

# Utility to spawn a generator player and push frames
# gen_fn should return either:
# - float: mono sample (sent to both channels), or
# - Vector2: stereo sample (x=left, y=right)
func _play_generated(duration: float, gen_fn: Callable) -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = _mix_rate
	stream.buffer_length = _buffer_len
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(_sfx_volume_linear)
	add_child(player)
	player.play()
	var pb: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if pb == null:
		player.queue_free()
		return
	var total_frames := int(duration * _mix_rate)
	var i := 0
	while i < total_frames:
		# fill in chunks to avoid starvation
		var frames_left := total_frames - i
		var frames_to_write: int = int(min(frames_left, int(_mix_rate * _buffer_len)))
		for j in range(frames_to_write):
			var t := float(i + j) / _mix_rate
			var sample = gen_fn.call(t)
			var out: Vector2
			match typeof(sample):
				TYPE_VECTOR2:
					var v: Vector2 = sample
					out = Vector2(clamp(v.x, -1.0, 1.0), clamp(v.y, -1.0, 1.0))
				_:
					var s: float = float(clamp(float(sample), -1.0, 1.0))
					out = Vector2(s, s)
			pb.push_frame(out)
		i += frames_to_write
	# schedule cleanup slightly after playback without awaiting (non-coroutine)
	var delay: float = float(max(0.05, duration + 0.05))
	var timer := get_tree().create_timer(delay)
	# Queue-free the player when the timer fires; use a lambda to safely free if still valid
	timer.timeout.connect(func():
		if is_instance_valid(player):
			player.queue_free()
	)

# SFX implementations
## Play a short flip/tick sound for a card play.
func play_card_flip() -> void:
	# Short tick + click using two decaying sines
	var dur := 0.06
	var f1 := 1000.0
	var f2 := 3500.0
	_play_generated(dur, func(t: float):
		var env := exp(-t * 40.0)
		return 0.5 * env * sin(TAU * f1 * t) + 0.35 * env * sin(TAU * f2 * t)
	)

## Play a crisp blip for a successful tap.
func play_tap_success() -> void:
	# Snappy tap: short percussive blip
	var dur := 0.08
	var f := 1800.0
	_play_generated(dur, func(t: float):
		var env := exp(-t * 36.0)
		return 0.9 * env * sin(TAU * f * t)
	)
	# Light haptic feedback on mobile
	vibrate_light()

## Play a short warning buzz for errors/false taps.
func play_error_buzz() -> void:
	# Brief buzzy tone using two close frequencies to create beating
	var dur := 0.18
	var f1 := 120.0
	var f2 := 135.0
	_play_generated(dur, func(t: float):
		var env := exp(-t * 6.0)
		var sig := sin(TAU * f1 * t) * 0.7 + sin(TAU * f2 * t) * 0.7
		# soft clip for buzziness
		var x := sig * env
		return clamp(x - 0.2 * pow(x, 3), -1.0, 1.0)
	)
	# Stronger warning haptic on mobile
	vibrate_warning()

## Play a lively whoosh when the pile is awarded.
func play_pile_whoosh() -> void:
	# Livelier pile-take whoosh:
	# - Stereo filtered noise with rising cutoff for motion
	# - Subtle rising tone with gentle auto-pan for character
	# - Quick attack, smooth decay, slight randomization per trigger
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var dur: float = 0.4 + rng.randf() * 0.06 # vary the length a little
	# One-pole low-pass filter state per channel (stored in a reference container so closure updates persist)
	var filt := [0.0, 0.0] # [left, right]
	# Slight random pan speed and tone range for variety
	var pan_speed: float = 2.5 + rng.randf() * 1.5
	var f0: float = 220.0 + rng.randf() * 80.0
	var f1: float = 880.0 + rng.randf() * 220.0
	_play_generated(dur, func(t: float):
		var tt: float = clamp(t / dur, 0.0, 1.0)
		# Amplitude envelope: fast attack, smooth decay
		var attack: float = clamp(t * 40.0, 0.0, 1.0)
		var decay: float = exp(-tt * 3.2)
		var amp: float = attack * decay
		# Cutoff sweeps upward for a sense of movement
		var fc: float = lerp(300.0, 6000.0, pow(tt, 0.7))
		var alpha: float = 1.0 - exp(-TAU * fc / _mix_rate)
		# Stereo noise sources
		var n_l: float = (rng.randf() * 2.0 - 1.0)
		var n_r: float = (rng.randf() * 2.0 - 1.0)
		# Low-pass filter (update reference container so state persists across calls)
		filt[0] = filt[0] + alpha * (n_l - filt[0])
		filt[1] = filt[1] + alpha * (n_r - filt[1])
		var whoosh_l: float = float(filt[0]) * amp * 0.65
		var whoosh_r: float = float(filt[1]) * amp * 0.65
		# Rising tone with integrated phase based on linear freq ramp
		var phi: float = TAU * (f0 * t + 0.5 * (f1 - f0) * (t * t) / dur)
		var tone: float = sin(phi) * (0.18 * amp)
		# Auto-pan the tone left-right for a playful feel
		var pan: float = 0.5 + 0.5 * sin(TAU * pan_speed * t)
		var tone_l: float = tone * pan
		var tone_r: float = tone * (1.0 - pan)
		# Gentle transient thump near the start
		var th_env: float = exp(-t * 18.0)
		var th: float = sin(TAU * 90.0 * t) * 0.25 * th_env
		# Mix components with headroom
		var out_l: float = clamp(whoosh_l + tone_l + th * 0.6, -1.0, 1.0)
		var out_r: float = clamp(whoosh_r + tone_r + th * 0.6, -1.0, 1.0)
		return Vector2(out_l, out_r)
	)

# ===== Haptics (mobile vibration) =====
func _can_vibrate() -> bool:
	# Only allow on mobile platforms where handheld vibration is supported
	return _haptics_enabled and OS.has_feature("mobile") and Input != null and Input.has_method("vibrate_handheld")

## Trigger a light mobile vibration if available.
func vibrate_light() -> void:
	if _can_vibrate():
		# light tick
		Input.vibrate_handheld(25, 0.6)

## Trigger a stronger warning vibration if available.
func vibrate_warning() -> void:
	if _can_vibrate():
		# stronger and longer buzz
		Input.vibrate_handheld(70, 1.0)
