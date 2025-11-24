# ChallengeSystem.gd — Tracks face-card challenge flow and outcomes
#
# When a face card is played, the next player has N chances (J=1, Q=2, K=3, A=4) to respond with another face.
# This Resource keeps that state machine small and testable, emitting signals on transitions.
extends Resource
class_name ChallengeSystem

## Signals for challenge flow
## - challenge_started(from_player, chances)
## - challenge_passed_to_next(next_player, chances_left)
## - challenge_failed(winner_index)
## - challenge_cleared()

signal challenge_started(from_player: int, chances: int)
signal challenge_passed_to_next(next_player: int, chances_left: int)
signal challenge_failed(winner_index: int)
signal challenge_cleared()

var awaiting: bool = false
var chances: int = 0
var from_player: int = -1

func reset() -> void:
	awaiting = false
	chances = 0
	from_player = -1
	challenge_cleared.emit()

func is_active() -> bool:
	return awaiting

## Begin a new challenge from initiator_index with a number of chances derived from the face card.
func start(face_chances: int, initiator_index: int) -> void:
	awaiting = true
	chances = face_chances
	from_player = initiator_index
	challenge_started.emit(initiator_index, chances)

# Called when the current player played a non-face card during an active challenge.
# Returns true if the same player must continue playing (chances remain), false if challenge ended (failure emitted).
## Handle a non-face card played during an active challenge.
## Returns: true if the same player must continue (chances remain), false if the initiator wins.
func on_non_face_played(current_player_index: int, _num_players: int) -> bool:
	if not awaiting:
		return false
	chances -= 1
	if chances <= 0:
		# Challenge failed; initiator takes pile.
		var winner := from_player
		reset()
		challenge_failed.emit(winner)
		return false
	else:
		# Still active; the same next-player continues (no turn rotation during challenge)
		# (Keeping signal for compatibility though it's not used to rotate)
		challenge_passed_to_next.emit(current_player_index, chances)
		return true

# Called when the current player has no cards to play during an active challenge.
# Returns true if challenge continues; false if challenge ended (failure emitted or no active).
## The current challenged player has no cards; pass chances to the next player.
## Returns: true if challenge continues, false if there was no active challenge.
func on_player_empty(current_player_index: int, num_players: int) -> bool:
	if not awaiting:
		return false
	# If the current challenged player has no cards, pass the remaining chances to the next player in turn order
	# instead of immediately awarding the pile to the initiator. This keeps the challenge flowing correctly.
	# Do not change 'chances' or 'from_player'; simply notify and allow Game to advance the turn.
	var next_index := (current_player_index - 1 + num_players) % num_players
	challenge_passed_to_next.emit(next_index, chances)
	return true
