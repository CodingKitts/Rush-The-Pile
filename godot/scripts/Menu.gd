# Menu.gd — Main menu and settings UI
#
# Responsibilities
# - Start a game at a selected difficulty
# - Show a small settings panel for master/SFX volume and persist values
# - Provide basic hotkeys (fullscreen, escape)
#
extends Control

## Difficulty buttons
@onready var easy_btn: Button = $Center/VBox/Easy
@onready var medium_btn: Button = $Center/VBox/Medium
@onready var hard_btn: Button = $Center/VBox/Hard
## Quit and settings buttons
@onready var quit_btn: Button = $Center/VBox/Quit
@onready var settings_btn: Button = $Center/VBox/Settings
## Title label at top of menu
@onready var title_lbl: Label = $Center/VBox/Title
## Settings panel and controls
@onready var settings_panel: Panel = $SettingsPanel
@onready var master_slider: HSlider = $SettingsPanel/Center/VBox/MasterHBox/MasterSlider
@onready var sfx_slider: HSlider = $SettingsPanel/Center/VBox/SFXHBox/SFXSlider
@onready var close_btn: Button = $SettingsPanel/Center/VBox/Close


## Initialize UI, wire signals, and load persisted settings.
func _ready() -> void:
	var ver: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if ver != "":
		title_lbl.text = "Rush The Pile v%s" % ver
	else:
		title_lbl.text = "Rush The Pile"
	easy_btn.pressed.connect(_on_easy)
	medium_btn.pressed.connect(_on_medium)
	hard_btn.pressed.connect(_on_hard)
	quit_btn.pressed.connect(_on_quit)
	settings_btn.pressed.connect(_on_settings)
	close_btn.pressed.connect(_on_close_settings)
	master_slider.value_changed.connect(_on_master_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	# Ensure Settings panel has an opaque background (was transparent before)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 1.0) # solid black
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	settings_panel.add_theme_stylebox_override("panel", sb)
	# Load saved audio settings
	_load_settings()

# Global hotkeys: toggle fullscreen or handle Escape to close settings/quit.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("ui_cancel"):
		if settings_panel.visible:
			_on_close_settings()
		else:
			get_tree().quit()

# Toggle the primary window between fullscreen and windowed modes.
func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# Open the settings panel overlay.
func _on_settings() -> void:
	settings_panel.visible = true

# Close the settings panel overlay.
func _on_close_settings() -> void:
	settings_panel.visible = false

# Apply and persist the master audio volume slider value.
func _on_master_volume_changed(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clamp(v, 0.0, 1.0)))
	_save_settings()

# Persist the SFX volume and notify any live AudioManager in the current scene.
func _on_sfx_volume_changed(v: float) -> void:
	# Save; AudioManager will load on game scene open; also try to update if an AudioManager exists
	_save_settings()
	var audio := get_tree().current_scene.find_child("Audio", true, false)
	if audio != null and audio.has_method("set_sfx_volume_linear"):
		audio.set_sfx_volume_linear(v)



## Start the game scene after persisting the selected difficulty (0=EASY,1=MEDIUM,2=HARD).
func _start_game(diff_value: int) -> void:
	# Persist selected difficulty so the Game scene can read it on load
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("game", "difficulty", diff_value)
	cfg.save("user://settings.cfg")
	# Use atomic scene switch to avoid transient multiple root children
	var err := get_tree().change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		# Fallback: old approach, but avoid leaving duplicates if possible
		var main_packed: PackedScene = preload("res://scenes/Main.tscn")
		var main_scene: Node = main_packed.instantiate()
		get_tree().root.add_child(main_scene)
		get_tree().current_scene = main_scene
		queue_free()

# Start a new game on EASY difficulty.
func _on_easy() -> void:
	_start_game(0) # Difficulty.EASY

# Start a new game on MEDIUM difficulty.
func _on_medium() -> void:
	_start_game(1) # Difficulty.MEDIUM

# Start a new game on HARD difficulty.
func _on_hard() -> void:
	_start_game(2) # Difficulty.HARD

# Exit the application immediately.
func _on_quit() -> void:
	get_tree().quit()

# Load saved audio settings from user storage and apply to sliders and bus.
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	var master_val: float = 1.0
	var sfx_val: float = 0.8
	if err == OK:
		master_val = float(cfg.get_value("audio", "master_vol", master_val))
		sfx_val = float(cfg.get_value("audio", "sfx_vol", sfx_val))
	# Apply and set slider positions without re-saving immediately
	master_slider.value = clamp(master_val, 0.0, 1.0)
	sfx_slider.value = clamp(sfx_val, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(master_slider.value))

## Persist current master/SFX volume to user://settings.cfg.
func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "master_vol", master_slider.value)
	cfg.set_value("audio", "sfx_vol", sfx_slider.value)
	cfg.save("user://settings.cfg")
