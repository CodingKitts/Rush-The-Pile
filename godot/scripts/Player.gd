# Player.gd — Data model for a player (human or AI)
#
# Responsibilities
# - Store hand, score, pile takes, and remaining tap challenges
# - Provide helpers for playing, receiving, shuffling, and penalty operations
#
extends Resource
class_name Player

## Display name shown in UI and status text
@export var name: String = "Player"
## True if this player is controlled by the human
@export var is_human: bool = false
## Current hand as a queue (front is top)
var hand: Array[Card] = []
## Running count of cards received from pile awards
var pile_take_count: int = 0
## Current score (tap bonuses etc.)
var score: int = 0
## Number of remaining tap challenges a player has this game. Decrements on false taps.
var tap_challenges_left: int = 3

## Returns true if the player has at least one card to play.
func has_cards() -> bool:
	return hand.size() > 0

## Remove and return the top card from the hand, or null if empty.
func play_top() -> Card:
	if hand.is_empty():
		return null
	return hand.pop_front()

## Append the given pile to the bottom of this hand (preserves order).
func give_pile_to_bottom(pile: Array[Card]) -> void:
	for c in pile:
		hand.append(c)

## Apply the standard false-tap penalty: move up to two top cards under the center pile (bottom insert).
## Parameters: center — the center pile array to receive penalty cards at the bottom.
func penalty_two_to_center(center: Array[Card]) -> void:
	# Move up to two cards from the player's hand to the BOTTOM of the center pile.
	# Preserve the original discard order so the first discarded ends up deeper in the pile.
	var to_move: Array[Card] = []
	var count: int = min(2, hand.size())
	for _i in range(count):
		var c := play_top()
		if c != null:
			to_move.append(c)
	# Insert in reverse to keep original order at the bottom
	for i in range(to_move.size() - 1, -1, -1):
		center.insert(0, to_move[i])

## Receive a batch of cards at the bottom and increment pile_take_count.
func receive_cards(cards_in: Array[Card]) -> void:
	for c in cards_in:
		hand.append(c)
	pile_take_count += cards_in.size()

## Shuffle the player's hand in place. Uses provided RNG if present for deterministic results.
func shuffle_hand(rng: RandomNumberGenerator = null) -> void:
	# Shuffle the player's hand. Use provided RNG for determinism if available.
	if hand.size() <= 1:
		return
	if rng == null:
		hand.shuffle()
		return
	for i in range(hand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = hand[i]
		hand[i] = hand[j]
		hand[j] = tmp

## Increase score by delta (can be negative if needed).
func add_score(delta: int) -> void:
	score += delta
