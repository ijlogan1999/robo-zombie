class_name SpawnEntry
extends Resource
## One robot type in the round manager's spawn table: when it starts showing up and how common it is.

@export var scene: PackedScene
@export var first_round := 1
@export var weight := 10.0 ## Chance relative to the other types.
@export var weight_per_round := 0.0 ## Added to the weight for each round after first_round.


func weight_for_round(round_number: int) -> float:
	if round_number < first_round:
		return 0.0
	return weight + weight_per_round * (round_number - first_round)
