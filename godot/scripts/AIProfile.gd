# AIProfile.gd — Resource describing one AI's timing/behavior profile
#
# Responsibilities
# - Hold tunable parameters for AI card play timing and tap reaction timing
# - Provide helpers to pick randomized delays using an optional RNG for determinism
#
extends Resource
class_name AIProfile

## Display name for this AI profile (used in UI/debug)
@export var name: String = "AI"
## Minimum seconds AI waits before playing a card on its turn
@export var min_play_delay: float = 0.4
## Maximum seconds AI waits before playing a card on its turn
@export var max_play_delay: float = 1.2
## Minimum seconds for AI reaction to a valid tap window
@export var tap_reaction_min: float = 0.18
## Maximum seconds for AI reaction to a valid tap window
@export var tap_reaction_max: float = 0.45
## Chance [0..1] the AI will miss a valid tap window entirely
@export var miss_tap_probability: float = 0.0 # chance to miss a valid tap
## Chance [0..1] per second to attempt an invalid tap during normal play
@export var false_tap_probability: float = 0.0 # chance to tap when invalid per second in normal play
## Bias to speed AI up under face-card pressure (>0 faster, <0 slower)
@export var face_focus_bias: float = 0.0 # negative makes slower to play under face pressure, positive faster

## Pick a random play delay in seconds between min_play_delay..max_play_delay.
## Parameters:
##  - rng: Optional RandomNumberGenerator to ensure deterministic tests.
## Returns: float seconds.
func pick_play_delay(rng: RandomNumberGenerator = null) -> float:
	if rng != null:
		return rng.randf_range(min_play_delay, max_play_delay)
	return randf_range(min_play_delay, max_play_delay)

## Pick a random tap reaction delay in seconds between tap_reaction_min..tap_reaction_max.
## Parameters:
##  - rng: Optional RandomNumberGenerator for deterministic sampling.
## Returns: float seconds.
func pick_tap_reaction(rng: RandomNumberGenerator = null) -> float:
	if rng != null:
		return rng.randf_range(tap_reaction_min, tap_reaction_max)
	return randf_range(tap_reaction_min, tap_reaction_max)
