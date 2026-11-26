extends Node
## Chassis Yard: shuffled bays of dip tanks, the door in from the Crucible, tanks that hurt
## and sometimes burn, floating parts, Drippers' burning oil, and the conveyor home.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const DRIPPER := preload("res://scenes/enemies/dripper.tscn")

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
	level.get_node("ChassisNav/Section").layout_seed = seed_value + 202
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var valid := true
	var orders := {}
	for s in range(1, 11):
		var level := make_level(s)
		var yard: Section = level.get_node("ChassisNav/Section")
		var names := []
		for room in yard.rooms:
			names.append(room.display_name)
		valid = valid and yard.rooms.size() == 10 and yard.gates.size() == 9
		valid = valid and names[0] == "Intake Dock" and names[-1] == "Outflow"
		for room in yard.rooms:
			valid = valid and yard.room_at_position(room.global_position + Vector3.UP) == room
		orders[str(names)] = true
		level.free()
	check(valid, "10 yards: 10 bays from Intake Dock to Outflow, 9 gates, lookups work 400 m out")
	check(orders.size() >= 8, "bay order varies (%d orders)" % orders.size())

	var level := make_level(4)
	var heap: Section = level.get_node("NavigationRegion3D/Section")
	var dome: DomeSection = level.get_node("CrucibleNav/Section")
	var yard: Section = level.get_node("ChassisNav/Section")
	var player: Player = level.get_node("Player")
	await level.get_node("ChassisNav").baked
	for i in 5:
		await get_tree().physics_frame

	var map := player.get_world_3d().navigation_map
	var floor_point := Vector3.ZERO
	for i in 300:
		floor_point = NavigationServer3D.map_get_closest_point(map, Vector3(-396, 1, 3))
		if floor_point.x < -350.0:
			break
		await get_tree().physics_frame
	check(floor_point.x < -350.0 and absf(floor_point.y) < 0.8, "the yard has its own navmesh on its floor (%s)" % floor_point)

	# The Crucible's door leads here.
	var door: SectionDoor
	for d in dome.exit_doors:
		if d.arrival_id == &"chassis_from_crucible":
			door = d
	player.add_scrap(door.cost)
	door.interact(player)
	check(door.interact(player) and yard.room_at_position(player.global_position) == yard.rooms[0], "the Crucible's Chassis Yard door lands you in the Intake Dock")
	for i in 40:
		await get_tree().physics_frame
	var active := get_tree().get_nodes_in_group(Room.SPAWN_GROUP)
	var all_here := not active.is_empty()
	for marker: Node3D in active:
		all_here = all_here and marker.global_position.x < -300.0
	check(all_here, "with players in the yard, only yard spawns are live (%d)" % active.size())

	# Tanks.
	var tanks := yard.find_children("*", "DipTank", true, false)
	check(tanks.size() >= 6, "the yard has dip tanks (%d)" % tanks.size())
	var calm: DipTank
	var hot: DipTank
	for t: DipTank in tanks:
		if t.burns and hot == null:
			hot = t
		elif not t.burns and calm == null:
			calm = t
	player.global_position = calm.global_position + Vector3.UP * 0.2
	var before: float = player.health.health + player.health.shields
	await get_tree().create_timer(1.0).timeout
	var after: float = player.health.health + player.health.shields
	check(after < before and before - after < 25.0, "a dip hurts a little (%.0f)" % (before - after))
	if hot:
		hot._set_burning(true)
		player.health.reset()
		player.global_position = hot.global_position + Vector3.UP * 0.2
		before = player.health.health + player.health.shields
		await get_tree().create_timer(1.0).timeout
		after = player.health.health + player.health.shields
		check(before - after > 35.0, "a burning tank hurts a lot (%.0f)" % (before - after))
	else:
		check(true, "(no burning tank in this layout)")
	player.health.reset()

	var floaters := yard.find_children("*", "FloatingPart", true, false)
	if floaters.is_empty():
		check(true, "(no floating parts in this layout)")
	else:
		var part: FloatingPart = floaters[0]
		var p0 := part.global_position
		await get_tree().create_timer(1.0).timeout
		check(part.global_position.distance_to(p0) > 0.3, "floating parts drift across their tanks")

	# Drippers leave oil that catches fire.
	player.global_position = yard.rooms[0].global_position + Vector3(0, 0.3, 10)
	var dripper: Dripper = DRIPPER.instantiate()
	dripper.configure(500.0, 3.0)
	dripper.position = yard.rooms[0].global_position + Vector3(-10, 0.3, -8)
	level.get_node("Spawned").add_child(dripper, true)
	await get_tree().create_timer(3.0).timeout
	var patches := get_tree().get_nodes_in_group(&"oil_patches")
	check(not patches.is_empty(), "Drippers leave a trail of oil (%d patches)" % patches.size())
	var lit := false
	for patch: HazardZone in patches:
		lit = lit or patch.damage_per_second > 0.0
	check(lit, "and the trail catches fire")
	dripper.queue_free()

	# The conveyor home.
	var chute: Passage = yard.rooms[-1].get_node("ConveyorHome")
	player.global_position = chute.global_position
	for i in 6:
		await get_tree().physics_frame
	check(heap.room_at_position(player.global_position) != null, "the Outflow conveyor drops you back into the Heap")
	var cold_door: SectionDoor = yard.rooms[-1].get_node("ColdStorageDoor")
	check(not cold_door.locked and cold_door.arrival_id == &"cold_from_chassis", "the way on to Cold Storage is there")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
