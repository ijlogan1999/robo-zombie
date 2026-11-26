extends Node
## The Heap's ring layout: slots, gates, prices, room lookup, the stairwell and the navmesh.

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
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var orders := {}
	var valid := true
	var lookups := true
	for s in range(1, 13):
		var level := make_level(s)
		var section: RingSection = level.get_node("NavigationRegion3D/Section")
		var names := []
		for room in section.rooms:
			names.append(room.display_name)
		valid = valid and section.rooms.size() == 13 and section.gates.size() == 14
		valid = valid and names.has("Trade Post") and names[4] == "Stairwell" and names[10] == "Crane Control"
		for i in 13:
			valid = valid and level.has_node("NavigationRegion3D/Section/Room%d" % i)
			lookups = lookups and section.room_at_position(section.slot_center(i)) == section.rooms[i]
		for i in 14:
			valid = valid and section.gates[i].name == "Gate%d" % i
		orders[str(names)] = true
		level.free()
	check(valid, "12 layouts: 13 rooms in fixed slots, 14 gates, Trade Post in, rooms named Room0-12")
	check(lookups, "every slot centre maps back to its own room, on both floors")
	check(orders.size() >= 8, "layouts vary (%d orders)" % orders.size())

	var level := make_level(7)
	var section: RingSection = level.get_node("NavigationRegion3D/Section")
	var costs := {}
	for gate in section.gates:
		costs[gate.cost] = true
	check(costs.has(100) and costs.has(250) and costs.has(400) and not costs.has(450), "gate prices climb 100 to 400 with depth")
	check(section.depth[4] == 4 and section.depth[10] == 7, "stairwell is 4 doors in, crane control 7")

	await level.get_node("NavigationRegion3D").baked
	for i in 3:
		await get_tree().physics_frame
	var nav := (level.get_node("NavigationRegion3D") as NavigationRegion3D)
	check(nav.navigation_mesh.get_polygon_count() > 50, "navmesh baked (%d polygons)" % nav.navigation_mesh.get_polygon_count())
	var map := nav.get_navigation_map()
	await get_tree().physics_frame
	var from := section.slot_center(0) + Vector3.UP * 0.2
	var to := section.slot_center(10) + Vector3.UP * 0.2
	for i in 10:
		await get_tree().physics_frame
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reaches := path.size() > 1 and path[path.size() - 1].distance_to(to) < 3.0
	var climbs := false
	for p in path:
		if p.y > 3.0 and p.y < 7.0:
			climbs = true
	check(reaches and climbs, "robots can path from the spawn yard up the stairwell ramp to crane control (%d points)" % path.size())

	var active := get_tree().get_nodes_in_group(Room.SPAWN_GROUP).size()
	check(active == section.rooms[0].spawn_points().size(), "only the spawn yard spawns robots at first (%d)" % active)

	var player: Player = level.get_node("Player")
	var first: Gate
	for gate in section.gates:
		if gate.cost == 100:
			first = gate
			break
	player.add_scrap(100)
	check(first.interact(player) and first.is_open, "a first door opens for 100 scrap")
	await get_tree().create_timer(0.7).timeout
	check(get_tree().get_nodes_in_group(Room.SPAWN_GROUP).size() > active, "opening it adds the next room's spawns")

	# Open one whole side of the ground floor; the far gate into the stairwell on the
	# other side stays shut until that room is open too.
	for gate in section.gates:
		var pair: Array = section._gate_rooms[gate]
		if pair[0] in [0, 1, 2, 3] and pair[1] in [1, 2, 3, 4]:
			gate.open()
	await get_tree().process_frame
	var east_into_stairs: Gate
	for gate in section.gates:
		var pair: Array = section._gate_rooms[gate]
		if (pair[0] == 5 and pair[1] == 4) or (pair[0] == 4 and pair[1] == 5):
			east_into_stairs = gate
	check(section.rooms[4].is_open and not east_into_stairs.is_open, "west side open to the stairwell; east stairwell gate still shut")
	for gate in section.gates:
		var pair: Array = section._gate_rooms[gate]
		if pair[1] in [7, 6, 5]:
			gate.open()
	await get_tree().process_frame
	check(east_into_stairs.is_open, "once both sides are open, the leftover gate clears itself")

	player.global_position = section.slot_center(10) + Vector3.UP * 0.5
	await get_tree().physics_frame
	check(section.room_at_position(player.global_position) == section.rooms[10], "a player in crane control is found in crane control")

	# Mystery crate
	var box: MysteryBox = level.get_node("MysteryBox")
	check(box.spots().size() >= 6 and box.global_position.distance_to(box.spots()[box.spot_index].global_position) < 0.01, "mystery crate sits on one of %d box spots" % box.spots().size())
	player.add_scrap(950 * 10)
	var guns_before := player.weapon_holder.slots.size()
	var start_spot := box.spot_index
	var rolls := box.rolls_left
	for i in rolls:
		box.interact(player)
	check(box.rolls_left == 0 and player.weapon_holder.slots.size() >= guns_before, "rolling hands out guns (%d rolls)" % rolls)
	var scrap_before := player.scrap
	box.interact(player)
	check(player.scrap == scrap_before and box.recalled, "QUOTA recalls the crate: that roll is refunded")
	await get_tree().create_timer(2.3).timeout
	check(box.spot_index != start_spot and not box.recalled and box.rolls_left >= 4, "the crate turns up at another spot")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
