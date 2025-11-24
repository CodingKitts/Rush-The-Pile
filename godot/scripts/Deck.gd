# Deck.gd — Standard 52-card deck utilities (reset, shuffle, deal)
#
# Responsibilities
# - Maintain a 52-card list and provide shuffle/deal functionality
# - Support deterministic shuffles when an RNG is supplied
#
extends Resource
class_name Deck

const RANKS := ["A","2","3","4","5","6","7","8","9","10","J","Q","K"]
const SUITS := ["♠","♥","♦","♣"]

## Current deck contents
var cards: Array[Card] = []

func _init():
	reset()

## Rebuild the deck to exactly one standard 52-card set.
func reset() -> void:
	cards.clear()
	for s in SUITS:
		for r in RANKS:
			var c := Card.new()
			c.rank = r
			c.suit = s
			cards.append(c)

## Shuffle in-place. If rng is provided, uses Fisher–Yates with rng for determinism.
## Parameters: rng (optional RandomNumberGenerator)
func shuffle(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		cards.shuffle()
		return
	# Fisher-Yates using provided RNG for determinism
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp

## Deal cards evenly into num_players hands (round-robin).
## Returns: Array of Array[Card] of length num_players.
func deal(num_players: int) -> Array:
	var hands: Array = []
	for _i in range(num_players):
		hands.append([] as Array[Card])
	var i := 0
	for c in cards:
		hands[i].append(c)
		i = (i + 1) % num_players
	return hands
