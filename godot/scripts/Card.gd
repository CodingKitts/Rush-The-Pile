# Card.gd — Typed Resource representing a playing card (rank + suit)
#
# Responsibilities
# - Provide typed fields for rank/suit and helpers used across systems.
#
extends Resource
class_name Card

## Card rank: "A", "2".."10", "J", "Q", "K"
@export var rank: String
## Card suit: "♠", "♥", "♦", "♣"
@export var suit: String

## Convert rank to comparable numeric value (A high).
## Returns: 2..14 where A=14, K=13, Q=12, J=11
func get_value() -> int:
	# Map ranks to comparable values (A high)
	match rank:
		"A":
			return 14
		"K":
			return 13
		"Q":
			return 12
		"J":
			return 11
		_:
			return int(rank)

## Returns true if this card is a face card (A/K/Q/J)
func is_face() -> bool:
	return rank in ["A", "K", "Q", "J"]

## Get the number of challenge chances this face card confers (J=1, Q=2, K=3, A=4).
## Returns 0 for non-face ranks.
func face_chances() -> int:
	match rank:
		"J":
			return 1
		"Q":
			return 2
		"K":
			return 3
		"A":
			return 4
		_:
			return 0

## Compact label like "Q♠" used in HUD/visual tokens.
func label_text() -> String:
	return "%s%s" % [rank, suit]
