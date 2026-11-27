class_name Packer
extends Robot
## One of the Shipping Bay's unique robots: a loader that carries a crate lid as a shield.
## Shots from the front mostly glance off; flank it or shoot its back.

@export var front_scale := 0.2 ## Damage taken from in front.


func take_damage(amount: float, hit_position: Vector3, attacker: Node = null) -> bool:
	var to_hit := hit_position - global_position
	to_hit.y = 0.0
	if to_hit.length() > 0.05 and (-global_basis.z).dot(to_hit.normalized()) > 0.45:
		amount *= front_scale
	return super.take_damage(amount, hit_position, attacker)
