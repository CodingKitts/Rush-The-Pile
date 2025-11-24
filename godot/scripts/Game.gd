# Game.gd — Core match coordinator for Rush The Pile
#
# Responsibilities
# - Owns the match state machine (dealing → normal play → face-card challenge → tap window → pile clear → game over)
# - Coordinates Deck, Players, TapSystem, ChallengeSystem, Visuals, and AudioManager
# - Emits high-level signals for UI and VFX to react to without coupling to model logic
# - Schedules AI plays/taps based on AIProfile traits and difficulty settings
# - Applies fairness rules like tap tie-break and assisted difficulty (DDS) delays
#
# Key Signals (emitted by Game)
# - status(message): Any user-facing status text (e.g., "Alice starts", "Bob takes the pile")
# - pile_changed(top_label): Center label should update to show the top card text
# - turn_changed(name) / turn_index_changed(index): Notify UI of whose turn it is
# - card_played(player_index, card_label): A card moved from a player's hand to the center
# - tap_window_opened_vis(): Forward visual cue that a valid tap pattern just appeared
# - score_awarded(player_index, delta, reason, total_score): Scoring feedback for HUD popups
# - challenge_chances_changed(chances_left): Remaining chances during a face-card challenge
# - dds_active_changed(active): Dynamic Difficulty Assist is active (UI can show a Focus icon)
#
# Configuration (exported)
# - difficulty: EASY/MEDIUM/HARD affects AI reaction and hints
# - enable_doubles / enable_sandwiches: rule toggles for valid tap events
# - ai_min_play_delay: minimum think-time for AI card plays (readability)
# - pile_clear_delay: pause between pile collection and next play
# - challenge_tap_grace_delay: brief pause so tap windows after challenges are readable
# - ai_profile_resources: optional override of built-in AI profiles via .tres
# - game_seed: set for deterministic shuffle and AI timing
# - DDS settings: thresholds and effects for temporary assist when a player is struggling
#
# Interaction Map
# - TapSystem: asked to evaluate tap events and resolve taps deterministically (human-biased tie window)
# - ChallengeSystem: tracks face-card challenge flow and notifies of pass/fail transitions
# - Visuals: listens to Game/TapSystem signals to render overlays/labels and a game timer
# - AudioManager: provides synthesized SFX and optional vibration on actions
# - Menu: persists difficulty and audio settings; Game reads them on startup
#
# Notes for future contributors
# - Keep gameplay rules isolated in TapSystem and ChallengeSystem as much as possible.
# - Prefer emitting signals for UI/Audio instead of directly manipulating nodes.
# - When adding a new rule toggle, expose it here and thread into TapSystem checks.
# - Be careful with awaits/timers inside turn advancement to avoid overlapping schedules.
#
# Class: Game
# Coordinates the entire match and exposes signals consumed by Visuals/UI.
extends Node2D

const NUM_PLAYERS := 4

const FACE_RANKS := {"J":1, "Q":2, "K":3, "A":4}
const TAP_WIN_BONUS := 10

# Game state machine for clarity and input guarding
enum GameState { DEALING, NORMAL_PLAY, CHALLENGE, TAP_WINDOW, MIS_TAP_PAUSE, PILE_CLEAR_PAUSE, GAME_OVER }
var state: GameState = GameState.DEALING
# Soft focus pause flag (auto-pause on focus lost)
var _focus_paused: bool = false

# Typed UI/gameplay signals to decouple UI from Game
signal status(message: String)
## Emitted when the center pile label should update (e.g., after a card is played or pile cleared)
signal pile_changed(top_label: String)
## Human-readable turn change for UI overlays that don’t track indexes
signal turn_changed(name: String)
## Turn index changed; preferred for visuals (0 = human)
signal turn_index_changed(index: int)
## A card moved from player_index to the center; label is like "Q♠"
signal card_played(player_index: int, card_label: String)
## Visual hint hook for when a valid tap window opened (forwarded from TapSystem)
signal tap_window_opened_vis()
## Score delta was applied (e.g., tap bonus). Total is the player's new score
signal score_awarded(player_index: int, delta: int, reason: String, total_score: int)
## Remaining face-card challenge chances changed (for HUD badge)
signal challenge_chances_changed(chances_left: int)

# Difficulty as exported enum/int for inspector safety
enum Difficulty { EASY, MEDIUM, HARD }
@export var difficulty: Difficulty = Difficulty.MEDIUM

# Rule toggles
@export var enable_doubles: bool = true
@export var enable_sandwiches: bool = true

# Per-turn play timeout (seconds). If the current player does not play within this time,
# they lose their turn and must place one card into the center as a penalty.
@export var turn_play_timeout: float = 3.0

# Global minimum delay before any AI plays a card (to help humans follow turns)
@export var ai_min_play_delay: float = 0.35
# Delay after pile clears before allowing next play (human or AI)
@export var pile_clear_delay: float = 0.6
# Grace period to allow taps when a challenge ends on a tap event
@export var challenge_tap_grace_delay: float = 0.5

# Optionally allow injecting AI profiles from .tres resources
@export var ai_profile_resources: Array[AIProfile] = []

# Deterministic RNG support
@export var game_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Cached frequently used nodes
@onready var center_area: Area2D = $CenterPileArea
@onready var center_label: Label = $CenterLabel
@onready var message_label: Label = $UI/Message
@onready var player_areas_root: Node = $PlayerAreas
@onready var player0_area: Area2D = $PlayerAreas/Player0Area

var deck: Deck = Deck.new()
var players: Array[Player] = []
var ai_profiles: Array[AIProfile] = []
var active_ai_profiles: Array[AIProfile] = []
var current_player_index: int = 0
var center_pile: Array[Card] = []
var game_over: bool = false
# Track eliminated players (cannot tap back in or take turns)
var _eliminated: Array[bool] = []

# Systems
var tap_system := TapSystem.new()
# Assisted match flags
var _assist_first_match: bool = false
var _assist_multiplier_play: float = 1.0
var _assist_multiplier_tap: float = 1.0
var _assist_extra_tap_delay: float = 0.0
var challenge := ChallengeSystem.new()
var input_router: InputRouter = null
# Visuals ref (assigned in _ready)
var _visuals: Visuals = null
# Audio manager (node under Main scene)
@onready var _audio: AudioManager = $Audio


# Timers
var play_timer := Timer.new()
var turn_timeout_timer := Timer.new()
# AI scheduling guards to prevent off-turn plays
var _schedule_id: int = 0
var _scheduled_for_index: int = -1
# Turn-timeout token to cancel pending awaits safely
var _turn_timeout_token: int = 0

## Initialize game systems, load settings, wire signals, and start the first match.
func _ready() -> void:
	# Load chosen difficulty (saved by Menu) before setting up players
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var diff_any = cfg.get_value("game", "difficulty", int(difficulty))
	if typeof(diff_any) == TYPE_INT:
		# Enums are ints in GDScript; assign clamped int directly (avoid calling Difficulty(...) )
		difficulty = clamp(int(diff_any), 0, 2)
	add_child(play_timer)
	play_timer.one_shot = true
	add_child(turn_timeout_timer)
	turn_timeout_timer.one_shot = true
	_setup_ai_profiles()
	_setup_players()
	# Setup systems
	add_child(tap_system)
	tap_system.setup(players, center_pile, Callable(self, "_get_ai_profile_for_index"), NUM_PLAYERS, Callable(self, "_emit_status"), Callable(self, "_update_center_label"), rng, Callable(self, "_is_player_active"))
	# Apply rule toggles to tap system
	tap_system.enable_doubles = enable_doubles
	tap_system.enable_sandwiches = enable_sandwiches
	tap_system.pile_awarded.connect(_on_pile_awarded)
	tap_system.pile_cleared.connect(_on_pile_cleared)
	tap_system.tap_window_opened.connect(_on_tap_window_opened)
	tap_system.false_tap.connect(_on_false_tap)
	challenge.challenge_failed.connect(_on_challenge_failed)
	challenge.challenge_started.connect(_on_challenge_started)
	challenge.challenge_cleared.connect(_on_challenge_cleared)
	challenge.challenge_passed_to_next.connect(_on_challenge_passed_to_next)
	# Visuals overlay
	var vis := Visuals.new()
	add_child(vis)
	vis.setup(center_area, center_label, player_areas_root, tap_system)
	vis.bind_game(self)
	_visuals = vis
	# Connect Leave Match button if present in UI
	var leave_btn := get_node_or_null("UI/LeaveButton")
	if leave_btn and leave_btn.has_signal("pressed"):
		leave_btn.pressed.connect(_on_leave_pressed)
	# Tutorial overlay removed from gameplay — How to Play is now available from Main Menu > Settings
	# (Previously would show a tutorial panel here.)
	# Assisted first match: configure tap system multipliers based on config
	_configure_first_match_assist()
	# Setup input router (replaces direct input handlers)
	var tap_btn := get_node_or_null("UI/TapButton")
	input_router = InputRouter.new()
	add_child(input_router)
	input_router.setup(
		center_area,
		player0_area,
		tap_btn,
		Callable(self, "_is_input_blocked"),
		Callable(self, "_is_player_active"),
		Callable(self, "_is_human_turn_cb"),
		Callable(self, "_get_state_cb"),
		Callable(self, "_play_current_cb"),
		Callable(self, "_attempt_tap_cb"),
		Callable(self, "_is_tap_window_live_cb")
	)
	# Start game after input systems are ready
	start_new_game()
	# No self-connection; UI should listen to our typed signals instead

## Return true if input should be ignored due to pause, animation, or game-over states.
func _is_input_blocked() -> bool:
	return _focus_paused or game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE

## Callback for InputRouter: true if it's currently the human player's turn.
func _is_human_turn_cb() -> bool:
	if players.size() == 0:
		return false
	return players[current_player_index].is_human

## Callback for InputRouter: returns current GameState enum as int.
func _get_state_cb() -> int:
	return int(state)

## Callback for InputRouter: request to play the current player's top card (human only).
func _play_current_cb() -> void:
	_play_card(current_player_index)

## Callback for InputRouter: request TapSystem to attempt a tap on behalf of player i.
func _attempt_tap_cb(i: int) -> void:
	if tap_system != null:
		tap_system.attempt_tap(i)

## Callback for InputRouter: true if a valid tap window is currently open.
func _is_tap_window_live_cb() -> bool:
	if tap_system == null:
		return false
	return state == GameState.TAP_WINDOW and tap_system.tap_window_open and tap_system.tap_valid

## Configure temporary assist modifiers for the first match (tutorial-friendly pacing).
func _configure_first_match_assist() -> void:
	# Load tutorial/assist flags from config
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	var first_done: bool = bool(cfg.get_value("tutorial", "first_match_done", false))
	_assist_first_match = not first_done
	if _assist_first_match:
		_assist_multiplier_play = 1.2
		_assist_multiplier_tap = 1.15
		_assist_extra_tap_delay = 0.10
		# Inform TapSystem of tap assist
		if tap_system != null and tap_system.has_method("set_assist_modifiers"):
			tap_system.set_assist_modifiers(_assist_multiplier_tap, _assist_extra_tap_delay)
		# Mark first match as done so next matches are normal
		cfg.set_value("tutorial", "first_match_done", true)
		cfg.save("user://settings.cfg")
	else:
		_assist_multiplier_play = 1.0
		_assist_multiplier_tap = 1.0
		_assist_extra_tap_delay = 0.0
		if tap_system != null and tap_system.has_method("set_assist_modifiers"):
			tap_system.set_assist_modifiers(1.0, 0.0)

## Cancel any pending AI play/tap schedules to avoid off-turn actions.
func _cancel_scheduled_ai() -> void:
	# Stop current play timer and invalidate any pending AI awaits
	if play_timer != null:
		play_timer.stop()
	_schedule_id += 1
	_scheduled_for_index = -1

## Build the list of AI profiles to use, from resources or built-in defaults.
func _setup_ai_profiles() -> void:
	ai_profiles.clear()
	# Prefer profiles from exported resources if provided, but only if complete and valid (>= 8 entries)
	if not ai_profile_resources.is_empty():
		var provided: Array[AIProfile] = []
		for p in ai_profile_resources:
			if p is AIProfile and p != null:
				provided.append(p)
		if provided.size() >= 8:
			ai_profiles = provided
			return
	# Otherwise attempt to load from default resource paths (optional)
	var loaded: Array[AIProfile] = []
	var base_paths := [
		"res://resources/ai/easy_a.tres", "res://resources/ai/easy_b.tres",
		"res://resources/ai/normal_a.tres", "res://resources/ai/normal_b.tres",
		"res://resources/ai/hard_a.tres", "res://resources/ai/hard_b.tres",
		"res://resources/ai/pro_a.tres", "res://resources/ai/pro_b.tres"
	]
	for p in base_paths:
		if ResourceLoader.exists(p):
			var res = ResourceLoader.load(p)
			if res is AIProfile:
				loaded.append(res)
	if loaded.size() == 8:
		ai_profiles = loaded
		return
	# Fallback inline definitions
	var profiles: Array[AIProfile] = [
		AIProfile.new(), AIProfile.new(), AIProfile.new(), AIProfile.new(),
		AIProfile.new(), AIProfile.new(), AIProfile.new(), AIProfile.new()
	]
	profiles[0].name = "Easy A"; profiles[0].min_play_delay=0.9; profiles[0].max_play_delay=1.6; profiles[0].tap_reaction_min=0.35; profiles[0].tap_reaction_max=0.6; profiles[0].miss_tap_probability=0.4; profiles[0].false_tap_probability=0.1
	profiles[1].name = "Easy B"; profiles[1].min_play_delay=0.8; profiles[1].max_play_delay=1.5; profiles[1].tap_reaction_min=0.32; profiles[1].tap_reaction_max=0.55; profiles[1].miss_tap_probability=0.3; profiles[1].false_tap_probability=0.08
	profiles[2].name = "Normal A"; profiles[2].min_play_delay=0.6; profiles[2].max_play_delay=1.2; profiles[2].tap_reaction_min=0.26; profiles[2].tap_reaction_max=0.5; profiles[2].miss_tap_probability=0.15; profiles[2].false_tap_probability=0.04
	profiles[3].name = "Normal B"; profiles[3].min_play_delay=0.55; profiles[3].max_play_delay=1.1; profiles[3].tap_reaction_min=0.24; profiles[3].tap_reaction_max=0.48; profiles[3].miss_tap_probability=0.12; profiles[3].false_tap_probability=0.03; profiles[3].face_focus_bias=0.05
	profiles[4].name = "Hard A"; profiles[4].min_play_delay=0.5; profiles[4].max_play_delay=1.0; profiles[4].tap_reaction_min=0.22; profiles[4].tap_reaction_max=0.4; profiles[4].miss_tap_probability=0.06; profiles[4].false_tap_probability=0.02; profiles[4].face_focus_bias=0.1
	profiles[5].name = "Hard B"; profiles[5].min_play_delay=0.45; profiles[5].max_play_delay=0.95; profiles[5].tap_reaction_min=0.2; profiles[5].tap_reaction_max=0.38; profiles[5].miss_tap_probability=0.05; profiles[5].false_tap_probability=0.02; profiles[5].face_focus_bias=0.12
	profiles[6].name = "Pro A"; profiles[6].min_play_delay=0.42; profiles[6].max_play_delay=0.9; profiles[6].tap_reaction_min=0.18; profiles[6].tap_reaction_max=0.34; profiles[6].miss_tap_probability=0.02; profiles[6].false_tap_probability=0.01; profiles[6].face_focus_bias=0.15
	profiles[7].name = "Pro B"; profiles[7].min_play_delay=0.4; profiles[7].max_play_delay=0.85; profiles[7].tap_reaction_min=0.16; profiles[7].tap_reaction_max=0.32; profiles[7].miss_tap_probability=0.01; profiles[7].false_tap_probability=0.005; profiles[7].face_focus_bias=0.2
	ai_profiles = profiles

## Return a set of AI profiles balanced for the current difficulty setting.
func _get_profiles_for_difficulty() -> Array[AIProfile]:
	# Map difficulty to a selection of three AI profiles from easiest to hardest
	# Ensure we always return 3 entries
	var easy: Array[AIProfile] = [ai_profiles[0], ai_profiles[1], ai_profiles[2]] # Easy A, Easy B, Normal A
	var medium: Array[AIProfile] = [ai_profiles[2], ai_profiles[3], ai_profiles[4]] # Normal A, Normal B, Hard A
	var hard: Array[AIProfile] = [ai_profiles[4], ai_profiles[5], ai_profiles[7]] # Hard A, Hard B, Pro B
	match int(difficulty):
		Difficulty.EASY:
			return easy
		Difficulty.HARD:
			return hard
		_:
			return medium

## Create Player instances (1 human + 3 AI), shuffle/deal the deck, and set the starting player.
func _setup_players() -> void:
	players.clear()
	# Human is Player 0
	var human := Player.new()
	human.name = "You"
	human.is_human = true
	players.append(human)
	# Determine AI profiles for chosen difficulty
	active_ai_profiles = _get_profiles_for_difficulty()
	for i in range(1, NUM_PLAYERS):
		var ai := Player.new()
		var profile: AIProfile = active_ai_profiles[(i-1) % active_ai_profiles.size()]
		ai.name = profile.name
		ai.is_human = false
		players.append(ai)

## Reset match state, (re)deal cards, initialize systems, and begin the first turn.
func start_new_game() -> void:
	state = GameState.DEALING
	# Initialize RNG with provided seed (if 0, randomize) and display seed for determinism
	if game_seed != 0:
		rng.seed = game_seed
	else:
		rng.randomize()
		game_seed = rng.seed
	# Persist last used seed for reproducibility
	var _cfg := ConfigFile.new()
	_cfg.load("user://settings.cfg")
	_cfg.set_value("game", "last_seed", game_seed)
	_cfg.save("user://settings.cfg")
	status.emit("Seed %d — Shuffling and dealing..." % game_seed)
	deck.reset()
	deck.shuffle(rng)
	var hands: Array = deck.deal(NUM_PLAYERS)
	_eliminated.clear()
	for i in range(NUM_PLAYERS):
		players[i].hand = hands[i] as Array[Card]
		# Reset tap challenges for new game
		players[i].tap_challenges_left = 3
		_eliminated.append(false)
	center_pile.clear()
	_update_center_label()
	challenge.reset()
	game_over = false
	# Reset scheduling guards
	_cancel_scheduled_ai()
	current_player_index = rng.randi_range(0, NUM_PLAYERS - 1)
	turn_changed.emit(players[current_player_index].name)
	turn_index_changed.emit(current_player_index)
	status.emit("%s starts" % players[current_player_index].name)
	state = GameState.NORMAL_PLAY
	_schedule_next_action()

## Schedule the next action based on current state (AI play, face challenge, or open tap window).
func _schedule_next_action() -> void:
	if game_over:
		return
	if _check_game_over():
		return
	# Skip eliminated players
	if _eliminated.size() == NUM_PLAYERS and _eliminated[current_player_index]:
		_advance_to_next_active()
		return
	# If the current player has no cards, do not wait for their input — immediately proceed via _play_card,
	# which will handle advancing the turn or challenge logic appropriately.
	if not players[current_player_index].has_cards():
		_play_card(current_player_index)
		return
	if _eliminated.size() == NUM_PLAYERS and _eliminated[current_player_index]:
		_advance_to_next_active()
		return
	# Start a per-turn timeout for the current player
	_cancel_turn_timeout()
	_start_turn_timeout_for(current_player_index)
	if players[current_player_index].is_human:
		# Removed per issue: do not display "Your turn" message so only the timer shows.
		# status.emit("Your turn: tap your blue circle to play top card")
		# Cancel any previous AI schedule just in case
		_cancel_scheduled_ai()
	else:
		var profile := _get_ai_profile_for_index(current_player_index)
		var delay := profile.pick_play_delay(rng)
		if challenge.is_active():
			delay = clamp(delay * (1.0 - profile.face_focus_bias), ai_min_play_delay, 2.0)
		else:
			delay = max(delay, ai_min_play_delay)
		# Assisted first match: slow AI slightly
		delay *= _assist_multiplier_play
		# Create a new schedule token and record who this is for
		_schedule_id += 1
		_scheduled_for_index = current_player_index
		var local_id := _schedule_id
		play_timer.start(delay)
		await play_timer.timeout
		# Validate state and token before allowing AI to play
		if game_over or state == GameState.TAP_WINDOW or state == GameState.GAME_OVER:
			return
		if local_id != _schedule_id:
			return
		if _scheduled_for_index != current_player_index:
			return
		_ai_play_card(current_player_index)

## Legacy direct input handler for center area (kept for reference; InputRouter now handles taps).
func _on_center_input(_viewport, event, _shape_idx) -> void:
	if _focus_paused or game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE:
		return
	if event is InputEventMouseButton and event.pressed:
		# Center area is only for tap/slap attempts; never plays a card.
		if state == GameState.TAP_WINDOW and tap_system.tap_window_open and tap_system.tap_valid:
			if _is_player_active(0):
				tap_system.attempt_tap(0)
		return

## Handle a tap/slap attempt initiated by the human player.
func _on_human_tap() -> void:
	if _focus_paused or game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE:
		return
	# If a tap window is open, any tap is considered a slap attempt first
	if state == GameState.TAP_WINDOW and tap_system.tap_window_open and tap_system.tap_valid:
		if _is_player_active(0):
			tap_system.attempt_tap(0)
		return
	# Otherwise, center click during human turn should play a card (unchanged behavior)
	if players[current_player_index].is_human and (state == GameState.NORMAL_PLAY or state == GameState.CHALLENGE):
		_play_card(current_player_index)
	else:
		# Human tapping to slap out of turn (center clicks should not count as a tap attempt)
		return

## Legacy direct input handler for human play area (kept for reference; InputRouter now routes plays).
func _on_player0_input(_viewport, event, _shape_idx) -> void:
	if _focus_paused or game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE:
		return
	if event is InputEventMouseButton and event.pressed:
		# Tapping the human's blue circle should play a card only when it's the human's turn
		# and we are in a play-allowed state (not during a tap window).
		if players.size() > 0 and players[current_player_index].is_human and (state == GameState.NORMAL_PLAY or state == GameState.CHALLENGE):
			_play_card(current_player_index)
		return

## Legacy handler for on-screen TAP button; modern flow uses InputRouter.handle_ui_tap_action.
func _on_tap_button_pressed() -> void:
	# New: Tap button (and ui_tap action) should never play a card; they only attempt tap.
	if game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE:
		return
	if state == GameState.TAP_WINDOW and tap_system.tap_window_open and tap_system.tap_valid:
		if _is_player_active(0):
			tap_system.attempt_tap(0)
		return
	# Out of a valid tap window, treat as a false tap attempt (consumes challenge if available)
	if _is_player_active(0):
		tap_system.attempt_tap(0) # human index is 0

## Per-frame update: route keyboard actions and update any timers/overlays as needed.
func _process(delta: float) -> void:
	if _focus_paused or game_over or state == GameState.GAME_OVER:
		return
	# DDS expiry handled by DdsAssist component
	# Random false taps from AIs are disabled during the human player's turn.
	# Also never attempt false taps during a valid tap window (tap reactions are handled elsewhere),
	# or when gameplay is paused for a mis-tap animation or pile-clear pause.
	if state != GameState.TAP_WINDOW and state != GameState.MIS_TAP_PAUSE and state != GameState.PILE_CLEAR_PAUSE and not players[current_player_index].is_human:
		for i in range(1, NUM_PLAYERS):
			if _is_player_active(i):
				var profile := _get_ai_profile_for_index(i)
				if profile.false_tap_probability > 0 and rng.randf() < (profile.false_tap_probability * delta):
					tap_system.attempt_tap(i)

## Get the active AI profile used for player index i (humans ignored).
func _get_ai_profile_for_index(i: int) -> AIProfile:
	# Provide a safe default to avoid nil access in case of misconfiguration
	var default_profile := AIProfile.new()
	default_profile.name = "Default"
	default_profile.min_play_delay = 0.6
	default_profile.max_play_delay = 1.2
	default_profile.tap_reaction_min = 0.26
	default_profile.tap_reaction_max = 0.5
	default_profile.miss_tap_probability = 0.1
	default_profile.false_tap_probability = 0.02
	default_profile.face_focus_bias = 0.05
	
	if i == 0:
		# A balanced reference for timing (not actually used for human decisions)
		if ai_profiles.size() > 2 and ai_profiles[2] != null:
			return ai_profiles[2]
		elif not active_ai_profiles.is_empty() and active_ai_profiles[0] != null:
			return active_ai_profiles[0]
		else:
			return default_profile
	# Use the active set based on chosen difficulty
	if active_ai_profiles.is_empty():
		active_ai_profiles = _get_profiles_for_difficulty()
	var prof := active_ai_profiles[(i-1) % active_ai_profiles.size()]
	if prof == null:
		return default_profile
	return prof

## Make AI at index i play a card according to current state and challenge rules.
func _ai_play_card(i: int) -> void:
	if game_over:
		return
	# Disallow AI plays during tap window or if turn changed
	if state == GameState.TAP_WINDOW or state == GameState.GAME_OVER:
		return
	if i != current_player_index:
		return
	# Cancel turn timeout since AI is about to play
	_cancel_turn_timeout()
	_play_card(i)

## Core card play routine for player i; updates pile, emits signals, and advances state.
func _play_card(i: int) -> void:
	if game_over:
		return
	# Authoritative guard: only allow the current player to play, and never during a tap window
	if state == GameState.TAP_WINDOW or state == GameState.GAME_OVER:
		return
	if i != current_player_index:
		return
	# Stop any pending turn timeout since a play is occurring
	_cancel_turn_timeout()
	# Skip if eliminated
	if _eliminated.size() == NUM_PLAYERS and _eliminated[i]:
		_advance_to_next_active()
		return
	var p := players[i]
	if not p.has_cards():
		# No cards to play
		if challenge.is_active():
			var cont := challenge.on_player_empty(i, NUM_PLAYERS)
			if cont:
				status.emit("%s out of cards, challenge continues (%d left)" % [p.name, challenge.chances])
				_advance_turn()
			# if not cont, challenge_failed handler will schedule
			return
		_advance_turn()
		return
	var card := p.play_top()
	if card == null:
		_advance_turn()
		return
	center_pile.append(card)
	_update_center_label()
	status.emit("%s plays %s" % [p.name, card.label_text()])
	card_played.emit(i, card.label_text())
	# SFX: card flip
	if _audio != null:
		_audio.play_card_flip()
	# Scoring: award points based on card value
	var play_points := card.get_value()
	_award_score(i, play_points, "play")
	# Tap system evaluates windows
	tap_system.on_card_added()
	# Face card logic and state
	if card.is_face():
		challenge.start(card.face_chances(), i)
		state = GameState.CHALLENGE
		_advance_turn()
	else:
		if challenge.is_active():
			var cont2 := challenge.on_non_face_played(i, NUM_PLAYERS)
			if cont2:
				state = GameState.CHALLENGE
				# During a challenge, only the next player (who is currently taking their chances)
				# continues to play until a face appears or chances run out. Do not advance turn.
				_schedule_next_action()
			# else handled by signal (challenge failed -> pile awarded and next turn scheduled)
		else:
			state = GameState.NORMAL_PLAY
			_advance_turn()

## Advance turn to the next appropriate state/player after a card play or pile event.
func _advance_turn() -> void:
	if game_over:
		return
	# Cancel any pending AI action when turn is advanced
	_cancel_scheduled_ai()
	# Cancel any pending turn timeout when turn is advanced
	_cancel_turn_timeout()
	# Advance turn clockwise (reverse previous counter-clockwise order), skipping eliminated players
	var tries := 0
	while tries < NUM_PLAYERS:
		current_player_index = (current_player_index - 1 + NUM_PLAYERS) % NUM_PLAYERS
		if _eliminated.size() == NUM_PLAYERS and not _eliminated[current_player_index]:
			break
		tries += 1
	turn_changed.emit(players[current_player_index].name)
	turn_index_changed.emit(current_player_index)
	_schedule_next_action()

## Respond when TapSystem detects a valid tap window opening (visual cue, state set).
func _on_tap_window_opened() -> void:
	state = GameState.TAP_WINDOW
	# Cancel AI scheduled plays during a tap window
	_cancel_scheduled_ai()
	# Do not penalize turn timeouts while a tap window is open
	_cancel_turn_timeout()
	tap_window_opened_vis.emit()
	# Assisted first match: briefly highlight the window for the human
	if _assist_first_match and _visuals != null:
		var t := get_tree().create_timer(0.5)
		await t.timeout
		_visuals.end_tap_highlight()
	# If the human is eliminated, ensure their input can't fire attempt_tap; TapSystem will also guard.

## When a face-card challenge starts, update state and inform visuals about chances.
func _on_challenge_started(_from_player: int, _chances: int) -> void:
	state = GameState.CHALLENGE
	# Cancel any previously scheduled AI play when challenge state changes
	_cancel_scheduled_ai()
	challenge_chances_changed.emit(_chances)

## When a challenge phase ends without failure, revert to normal/tap states appropriately.
func _on_challenge_cleared() -> void:
	if not game_over:
		state = GameState.NORMAL_PLAY
		# When challenge ends, ensure any previous schedules are cleared and next action is scheduled by whoever's turn it is.
		_cancel_scheduled_ai()
	# Inform visuals to hide chances
	challenge_chances_changed.emit(0)

## When the challenge passes to the next player, update UI with remaining chances.
func _on_challenge_passed_to_next(_next_player: int, chances_left: int) -> void:
	challenge_chances_changed.emit(chances_left)

## Emit a user-facing status message for UI overlays and logs.
func _emit_status(msg: String) -> void:
	status.emit(msg)

## Handle a false tap event from TapSystem: animate penalty and adjust state.
func _on_false_tap(player_index: int) -> void:
	# Pause gameplay and animate mis-tap penalty before applying it.
	if game_over or state == GameState.GAME_OVER:
		return
	# Ignore false tap if a valid tap window is open (should not happen by design)
	if state == GameState.TAP_WINDOW:
		return
	var prev_state := state
	state = GameState.MIS_TAP_PAUSE
	# Cancel any scheduled AI plays
	_cancel_scheduled_ai()
	# Cancel any turn timeout during pause/animation
	_cancel_turn_timeout()
	# Announce for HUD refresh
	status.emit("%s false tap! +2 to center" % players[player_index].name)
	# SFX: error buzz for false tap (haptic handled inside AudioManager on mobile)
	if _audio != null:
		_audio.play_error_buzz()
	# Visual failure flash
	if _visuals != null and _visuals.has_method("flash_center"):
		_visuals.flash_center(Color(1,0.2,0.2,1), 0.25)
	# Play animation if visuals available, await completion
	if _visuals != null and _visuals.has_method("animate_false_tap"):
		await _visuals.animate_false_tap(player_index, min(2, players[player_index].hand.size()))
	# Apply the actual penalty to the model and update UI label
	var had_before := players[player_index].hand.size()
	players[player_index].penalty_two_to_center(center_pile)
	_update_center_label()
	# If they couldn't pay full penalty (had < 2) and are now out of cards, eliminate them per rule
	if had_before < 2 and players[player_index].hand.size() == 0 and _eliminated.size() == NUM_PLAYERS and not _eliminated[player_index]:
		_eliminate_player(player_index)
		# If elimination ended the game, stop here
		if game_over or state == GameState.GAME_OVER:
			return
		# If eliminated player held the turn, move to next active player
		if current_player_index == player_index:
			_advance_to_next_active()
			return
	# Restore state and resume scheduling
	if not game_over:
		state = prev_state
		# Resume any pending flow
		_schedule_next_action()

## When a pile is awarded to a player, handle visuals, scoring, and schedule next turn.
func _on_pile_awarded(player_index: int) -> void:
	# Clear any ongoing challenge and give next turn to winner
	challenge.reset()
	# Enter a brief pause state to allow all players to process the clear
	state = GameState.PILE_CLEAR_PAUSE
	# Ensure chances indicator is hidden
	challenge_chances_changed.emit(0)
	# Cancel any AI schedule since control changes immediately
	_cancel_scheduled_ai()
	# Also cancel any per-turn timeout while the pile is being awarded/paused
	_cancel_turn_timeout()
	current_player_index = player_index
	turn_changed.emit(players[current_player_index].name)
	turn_index_changed.emit(current_player_index)
	# Wait a short delay before allowing the next play
	var d: float = max(0.0, pile_clear_delay)
	if d > 0.0:
		var t: SceneTreeTimer = get_tree().create_timer(d)
		await t.timeout
	# After delay, resume normal play and schedule next action for the current player
	if not game_over:
		state = GameState.NORMAL_PLAY
		_schedule_next_action()

## Visual/UI hook when the pile is cleared (awarded); update center label and status.
func _on_pile_cleared(player_index: int, card_count: int, total_value: int, reason: String) -> void:
	# SFX: pile whoosh when cards are collected
	if _audio != null:
		_audio.play_pile_whoosh()
	# Scoring for clearing center pile; always award based on total value
	if card_count <= 0:
		return
	var clear_points := total_value
	_award_score(player_index, clear_points, "clear")
	# Additional bonus for winning a valid tap
	if reason == "tap":
		# SFX: tap success distinct blip (haptic handled inside AudioManager on mobile)
		if _audio != null:
			_audio.play_tap_success()
		_award_score(player_index, TAP_WIN_BONUS, "tap")
	# New end condition: if winner now holds all 52 cards, end the game and show scores
	if not game_over:
		var winner_hand := players[player_index].hand.size()
		if winner_hand >= 52:
			_trigger_game_over(player_index, "all_cards")

## When a challenge fails, award the pile to winner_index and schedule the next turn.
func _on_challenge_failed(winner_index: int) -> void:
	# Challenge failure normally awards pile to initiator. However, if the last card created a valid tap
	# event, give a short grace period to allow players to tap before clearing the pile.
	challenge_chances_changed.emit(0)
	# If a tap window is valid (and should already be open from on_card_added), delay awarding.
	if tap_system != null and tap_system.tap_valid:
		var d: float = max(0.0, challenge_tap_grace_delay)
		if d > 0.0:
			var t := get_tree().create_timer(d)
			await t.timeout
		# If, during the grace period, someone tapped and took the pile, do nothing.
		if game_over or center_pile.is_empty():
			return
		# Close any lingering tap window to prevent late taps, then award to challenge winner.
		tap_system.tap_window_open = false
		tap_system.tap_valid = false
		tap_system.award_pile_to(winner_index)
	else:
		tap_system.award_pile_to(winner_index)
	# Further flow (state reset, turn assignment, and immediate play) is handled by _on_pile_awarded

## Update the center label text to show the top card or blank when the pile is empty.
func _update_center_label() -> void:
	if center_pile.size() == 0:
		center_label.text = "Center"
		pile_changed.emit("")
	else:
		var top := center_pile[center_pile.size()-1]
		var label := "Pile %d\nTop: %s" % [center_pile.size(), top.label_text()]
		center_label.text = label
		pile_changed.emit(top.label_text())

# ===== Turn Timeout Helpers =====
## Stop any running per-turn timeout timer safely.
func _cancel_turn_timeout() -> void:
	_turn_timeout_token += 1
	if turn_timeout_timer != null:
		turn_timeout_timer.stop()

## Start the per-turn timeout timer for player i; on expiry they incur a penalty.
func _start_turn_timeout_for(i: int) -> void:
	# Do not start during tap window or if game paused
	if game_over or state == GameState.GAME_OVER or state == GameState.TAP_WINDOW or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE:
		return
	var timeout_s: float = max(0.0, turn_play_timeout)
	if timeout_s <= 0.0:
		return
	_turn_timeout_token += 1
	var local_token := _turn_timeout_token
	var idx := i
	turn_timeout_timer.start(timeout_s)
	await turn_timeout_timer.timeout
	# Validate that this timeout is still relevant
	if game_over or state == GameState.GAME_OVER or state == GameState.MIS_TAP_PAUSE or state == GameState.PILE_CLEAR_PAUSE or state == GameState.TAP_WINDOW:
		return
	if local_token != _turn_timeout_token:
		return
	if idx != current_player_index:
		return
	_on_turn_timeout(idx)

func _on_turn_timeout(i: int) -> void:
	# Guard and cancel any AI schedule
	_cancel_scheduled_ai()
	# Recheck state and ownership
	if game_over or state == GameState.GAME_OVER:
		return
	if i != current_player_index:
		return
	# Stop further timeout handling for this turn
	_cancel_turn_timeout()
	var p := players[i]
	# If player has no cards, defer to existing logic
	if not p.has_cards():
		if challenge.is_active():
			var cont := challenge.on_player_empty(i, NUM_PLAYERS)
			if cont:
				status.emit("%s out of cards, challenge continues (%d left)" % [p.name, challenge.chances])
				_advance_turn()
			return
		_advance_turn()
		return
	# Force one card to center as a penalty (no play score awarded)
	var card := p.play_top()
	if card == null:
		_advance_turn()
		return
	center_pile.append(card)
	_update_center_label()
	status.emit("%s timed out — forced %s to center" % [p.name, card.label_text()])
	card_played.emit(i, card.label_text())
	# SFX: use a subtle error buzz to indicate penalty
	if _audio != null:
		_audio.play_error_buzz()
	# Evaluate tap windows
	tap_system.on_card_added()
	# Apply face/challenge flow similar to normal play but without awarding points
	if card.is_face():
		challenge.start(card.face_chances(), i)
		state = GameState.CHALLENGE
		_advance_turn()
	else:
		if challenge.is_active():
			var cont2 := challenge.on_non_face_played(i, NUM_PLAYERS)
			if cont2:
				state = GameState.CHALLENGE
				_schedule_next_action()
			# else handled by _on_challenge_failed
		else:
			state = GameState.NORMAL_PLAY
			_advance_turn()

func _award_score(player_index: int, delta: int, reason: String) -> void:
	if delta == 0:
		return
	var p := players[player_index]
	p.add_score(delta)
	score_awarded.emit(player_index, delta, reason, p.score)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_fullscreen"):
		_toggle_fullscreen()
	elif event.is_action_pressed("ui_cancel"):
		_return_to_menu()
	elif event.is_action_pressed("ui_tap"):
		# Dedicated tap action (keyboard/controller). Route via InputRouter.
		if input_router != null:
			input_router.handle_ui_tap_action()

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _return_to_menu() -> void:
	# Teardown systems to prevent deferred callbacks into freed objects
	_teardown_systems()
	# Prefer engine-managed scene switch to avoid invalid instantiation or mid-frame issues
	var err := get_tree().change_scene_to_file("res://scenes/Menu.tscn")
	if err == OK:
		return
	# Fallback: manual instantiation if change_scene fails (e.g., during tool/testing context)
	var menu_packed: PackedScene = load("res://scenes/Menu.tscn")
	if menu_packed != null:
		var menu_scene: Node = menu_packed.instantiate()
		if menu_scene != null:
			get_tree().root.add_child(menu_scene)
			get_tree().current_scene = menu_scene
	# Free this game scene (safe if still active)
	queue_free()

# ===== Auto-pause on focus lost with resume countdown =====
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_focus_gained()

func _on_focus_lost() -> void:
	# Only auto-pause during active gameplay
	if game_over or state == GameState.GAME_OVER:
		return
	_focus_paused = true
	_cancel_scheduled_ai()
	status.emit("Paused — app lost focus")
	if _visuals != null and _visuals.has_method("show_pause_overlay"):
		_visuals.show_pause_overlay(true)

func _on_focus_gained() -> void:
	if not _focus_paused:
		return
	# Show countdown and resume
	if _visuals != null and _visuals.has_method("resume_countdown_and_wait"):
		await _visuals.resume_countdown_and_wait(3)
	_focus_paused = false
	# Resume normal scheduling if applicable
	if not game_over and state != GameState.GAME_OVER:
		_schedule_next_action()

func _on_leave_pressed() -> void:
	_return_to_menu()

# (FOCUS/DDS feature removed)

func _check_game_over() -> bool:
	# New human loss rule: if the human has no cards AND no remaining tap challenges, they lose immediately.
	if players.size() > 0:
		var human := players[0]
		if not human.has_cards() and human.tap_challenges_left <= 0:
			# Pick a winner to display: prefer any non-human with cards; otherwise highest-scoring non-human.
			var winner_idx := -1
			for i in range(1, min(NUM_PLAYERS, players.size())):
				if players[i].has_cards():
					winner_idx = i
					break
			if winner_idx == -1:
				var best_score := -2147483648
				for i in range(1, min(NUM_PLAYERS, players.size())):
					if players[i].score > best_score:
						best_score = players[i].score
						winner_idx = i
			_trigger_game_over(winner_idx, "human_exhausted")
			return true
	# Existing rule: if exactly one player has any cards left, they immediately win the game.
	var holders := 0
	var last_with_cards := -1
	for i in range(NUM_PLAYERS):
		if i < players.size() and players[i].has_cards():
			holders += 1
			last_with_cards = i
	if holders == 1:
		_trigger_game_over(last_with_cards, "last_with_cards")
		return true
	# Legacy rule: game also ends when only one non-eliminated player remains
	var active := 0
	var last_idx := -1
	for i in range(NUM_PLAYERS):
		if _eliminated.size() == NUM_PLAYERS and not _eliminated[i]:
			active += 1
			last_idx = i
	if active == 1:
		_trigger_game_over(last_idx, "elimination")
		return true
	return false

func _trigger_game_over(winner_index: int, _reason: String) -> void:
	if game_over:
		return
	var winner_name := players[winner_index].name if winner_index >= 0 and winner_index < players.size() else "Winner"
	status.emit("%s wins!" % winner_name)
	game_over = true
	state = GameState.GAME_OVER
	# Ask visuals to show the game over panel with scores
	if _visuals != null and _visuals.has_method("show_game_over_panel"):
		var scores: Array = []
		for i in range(players.size()):
			var p := players[i]
			scores.append({"name": p.name, "score": p.score})
		_visuals.show_game_over_panel(scores, winner_name)

# ===== Elimination helpers =====
func _is_player_active(i: int) -> bool:
	if i < 0 or i >= NUM_PLAYERS:
		return false
	if _eliminated.size() != NUM_PLAYERS:
		return true
	return not _eliminated[i]

func _advance_to_next_active() -> void:
	if game_over:
		return
	var tries := 0
	while tries < NUM_PLAYERS:
		current_player_index = (current_player_index - 1 + NUM_PLAYERS) % NUM_PLAYERS
		if _is_player_active(current_player_index):
			break
		tries += 1
	turn_changed.emit(players[current_player_index].name)
	turn_index_changed.emit(current_player_index)
	_schedule_next_action()

func _eliminate_player(i: int) -> void:
	if _eliminated.size() != NUM_PLAYERS:
		return
	if _eliminated[i]:
		return
	_eliminated[i] = true
	status.emit("%s is out of the game!" % players[i].name)
	# If only one active player remains after this elimination, end immediately
	var remain := 0
	var last := -1
	for idx in range(NUM_PLAYERS):
		if not _eliminated[idx]:
			remain += 1
			last = idx
	if remain == 1:
		_trigger_game_over(last, "elimination")

# ===== Teardown to avoid deferred callbacks hitting freed objects =====
func _teardown_systems() -> void:
	# Stop AI timers and invalidate schedules
	_cancel_scheduled_ai()
	# Tell TapSystem to stop and invalidate its Callables if supported
	if tap_system != null and tap_system.has_method("teardown"):
		tap_system.teardown()
	# Tell InputRouter to disconnect and invalidate callbacks
	if input_router != null and input_router.has_method("teardown"):
		input_router.teardown()

func _exit_tree() -> void:
	# Ensure teardown runs when the scene is removed/freed
	_teardown_systems()
