extends CharacterBody3D
## A boss body that weapons hit directly (the Slag Golem, the Scrap King). Passes hits to its boss,
## which decides whether they hurt. Other players' hits go to the host.

var boss: Node ## Has _body_take_damage(amount) -> bool.


func take_damage(amount: float, _at: Vector3, _attacker: Node = null) -> bool:
	if Net.is_session() and not multiplayer.is_server():
		_net_damage.rpc_id(1, amount)
		return false
	return boss._body_take_damage(amount)


@rpc("any_peer", "reliable")
func _net_damage(amount: float) -> void:
	take_damage(amount, Vector3.ZERO)
