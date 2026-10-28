class_name Room
extends Node3D
## One room of a section. The Section places it on its grid, may turn it, builds the walls
## and gates around it, and switches its robot spawns on when players are close by.
##
## Rooms have a floor and props but no outer walls: a doorway can end up on any side,
## so keep a 6 m lane clear in the middle of each edge.
## Robot spawn points are Marker3D children of a "Spawns" node.

const SPAWN_GROUP := &"robot_spawns" ## Must match RoundManager.spawn_group.

@export var display_name := "Room"
@export var can_rotate := true ## Turn by a random quarter-turn each run for extra variety.

var index := -1 ## Place along the section's path (0 = start room).
var is_open := false


func spawn_points() -> Array[Node]:
	var spawns := get_node_or_null("Spawns")
	return spawns.get_children() if spawns else ([] as Array[Node])


## Active spawn points are the ones the RoundManager picks from.
func set_spawns_active(active: bool) -> void:
	for marker in spawn_points():
		if active:
			marker.add_to_group(SPAWN_GROUP)
		elif marker.is_in_group(SPAWN_GROUP):
			marker.remove_from_group(SPAWN_GROUP)
