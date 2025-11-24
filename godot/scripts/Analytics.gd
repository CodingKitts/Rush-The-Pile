# Analytics.gd — Opt-in analytics stub (no data collection by default)
#
# This stub provides a safe, local event logger that only activates if the
# user explicitly opts in via settings (settings.cfg: analytics.opt_in=true).
# There is no network or third-party SDK. Intended for future extension.
extends Node
class_name Analytics

## True if the user has opted in to local analytics logging (persisted in settings.cfg)
var _enabled: bool = false

## Read the opt-in flag from user settings on startup.
func _ready() -> void:
	# Read opt-in flag; default is false for privacy by default
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	_enabled = bool(cfg.get_value("analytics", "opt_in", false))

func set_opt_in(flag: bool) -> void:
	_enabled = bool(flag)
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("analytics", "opt_in", _enabled)
	cfg.save("user://settings.cfg")

func get_opt_in() -> bool:
	return _enabled

func log_event(_name: String, _params: Dictionary = {}) -> void:
	if not _enabled:
		return
	# Local-only: write to a small rotating log file under user:// for dev/debug
	# No network calls here.
	var msg := "[ANALYTICS] %s %s\n" % [_name, JSON.stringify(_params)]
	var f := FileAccess.open("user://analytics.log", FileAccess.WRITE_READ)
	if f:
		f.seek_end()
		f.store_string(msg)
		f.close()
