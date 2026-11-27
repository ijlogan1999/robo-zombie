class_name Arrival
extends Marker3D
## Where players land when they travel to another section (a door, a conveyor, the pit).
## Passages and section doors look arrivals up by id.

const GROUP := &"arrival"

@export var arrival_id: StringName


func _enter_tree() -> void:
	add_to_group(GROUP)


static func find(tree: SceneTree, id: StringName) -> Arrival:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as Arrival).arrival_id == id:
			return node
	return null


## Moves a player here. Players spread out a little so co-op teams don't stack.
static func send(player: Player, id: StringName) -> bool:
	var arrival := find(player.get_tree(), id)
	if arrival == null:
		push_warning("No arrival called %s" % id)
		return false
	var offset := Vector3.ZERO
	var count := player.get_tree().get_nodes_in_group("players").find(player)
	if count > 0:
		offset = arrival.global_basis.x * 1.5 * count
	player.global_position = arrival.global_position + offset
	player.velocity = Vector3.ZERO
	player.rotation.y = arrival.global_rotation.y
	return true
