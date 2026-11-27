extends Node
## The Crucible dome: zones, shuffled mound gaps, exits, the drop from the Heap, molten metal.

const LEVEL := preload("res://scenes/levels/heap.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func make_level(seed_value: int) -> Node3D:
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = seed_value
	level.get_node("CrucibleNav/Section").layout_seed = seed_value + 101
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var valid := true
	var reachable := true
	var lookups := true
	var link_sets := {}
	var exit_sets := {}
	for s in range(1, 13):
		var level := make_level(s)
		var dome: DomeSection = level.get_node("CrucibleNav/Section")
		valid = valid and dome.rooms.size() == 10 and dome.gates.size() == dome.links.size()
		valid = valid and dome.exit_zones.size() == 2 and dome.exit_zones[0] != dome.exit_zones[1]
		valid = valid and dome.exit_zones[0] >= 4 and dome.exit_zones[1] >= 4 and dome.exit_doors.size() == 2
		for d in dome.depth:
			reachable = reachable and d >= 0
		for i in 10:
			lookups = lookups and dome.room_at_position(dome.zone_center(i) + Vector3.UP) == dome.rooms[i]
		link_sets[str(dome.links)] = true
		exit_sets[str(dome.exit_zones)] = true
		level.free()
	check(valid, "12 domes: 10 zones, one gate per mound gap, 2 exits in different outer zones")
	check(reachable, "every zone can be reached from the landing in every layout")
	check(lookups, "zone centres map back to their own zone")
	check(link_sets.size() >= 10 and exit_sets.size() >= 5, "mound gaps and exits vary (%d gap sets, %d exit sets)" % [link_sets.size(), exit_sets.size()])

	var level := make_level(5)
	var heap: RingSection = level.get_node("NavigationRegion3D/Section")
	var dome: DomeSection = level.get_node("CrucibleNav/Section")
	var player: Player = level.get_node("Player")
	await level.get_node("CrucibleNav").baked
	for i in 5:
		await get_tree().physics_frame
	var map := player.get_world_3d().navigation_map
	var floor_point := Vector3.ZERO
	for i in 300: # The map takes a few frames to pick up a fresh bake.
		floor_point = NavigationServer3D.map_get_closest_point(map, Vector3(20, -197, 5))
		if floor_point.y < -150.0:
			break
		await get_tree().physics_frame
	check(absf(floor_point.y + 200.0) < 1.0, "the Crucible's navmesh sits on its floor, not the roof (y %.1f)" % floor_point.y)
	var heap_spawns := heap.rooms[0].spawn_points().size()
	check(get_tree().get_nodes_in_group(Room.SPAWN_GROUP).size() == heap_spawns, "at the start only the Heap's spawn yard spawns robots")

	# Fall into the pit (it opens once the Scrap King is beaten; see test_scrap_king).
	level.get_node("PitDrop").enabled = true
	player.global_position = Vector3(0, -19, 0)
	for i in 6:
		await get_tree().physics_frame
	check(dome.room_at_position(player.global_position) == dome.rooms[0], "falling into the Heap pit lands you in the Crucible's centre (y %.1f)" % player.global_position.y)
	for i in 90:
		await get_tree().physics_frame
	check(player.is_on_floor() and player.global_position.y < -198.0, "and you land on the heap floor")
	await get_tree().create_timer(0.7).timeout
	var active := get_tree().get_nodes_in_group(Room.SPAWN_GROUP)
	var all_in_crucible := not active.is_empty()
	for marker: Node3D in active:
		all_in_crucible = all_in_crucible and marker.global_position.y < -150.0
	check(all_in_crucible, "with the player in the Crucible, only Crucible spawns are live (%d)" % active.size())

	# Molten metal hurts.
	var hazards := dome.find_children("*", "HazardZone", true, false)
	check(not hazards.is_empty(), "the dome has molten metal (%d pools)" % hazards.size())
	if not hazards.is_empty():
		var pool: HazardZone = hazards[0]
		player.global_position = pool.global_position + Vector3.UP * 0.2
		var before: float = player.health.health + player.health.shields
		await get_tree().create_timer(0.8).timeout
		var after: float = player.health.health + player.health.shields
		check(after < before, "standing in molten metal hurts (%.0f -> %.0f)" % [before, after])

	# A way out is a big door in the dome wall.
	var door := dome.exit_doors[0]
	player.add_scrap(dome.exit_cost)
	check(door.interact(player) and door.is_open, "an exit door opens for %d scrap" % dome.exit_cost)

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
