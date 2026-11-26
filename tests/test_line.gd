extends Node
## The Line: four storeys around the giant's atrium, the doors in from Servo Works and the
## Chassis Yard, the giant built as areas open, Amalgams, belts, and the way on.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const AMALGAM := preload("res://scenes/enemies/amalgam.tscn")

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
	level.get_node("ServoNav/Section").layout_seed = seed_value + 303
	level.get_node("ColdNav/Section").layout_seed = seed_value + 404
	level.get_node("LineNav/Section").layout_seed = seed_value + 505
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var valid := true
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var line: LineSection = level.get_node("LineNav/Section")
		var names := []
		for room in line.rooms:
			names.append(room.display_name)
		valid = valid and line.rooms.size() == 8 and names[0] == "Line Intake" and names[7] == "Assembly Floor" and line.gates.size() == 7
		for i in 8:
			valid = valid and line.depth[i] == i and line.room_at_position(line.area_center(i) + Vector3.UP) == line.rooms[i]
		orders[str(names)] = true
		level.free()
	check(valid, "12 Lines: 8 areas up 4 storeys, Line Intake to Assembly Floor, a gate between each")
	check(orders.size() >= 8, "the work areas shuffle (%d orders)" % orders.size())

	var level := make_level(3)
	var line: LineSection = level.get_node("LineNav/Section")
	var giant: LineGiant = level.get_node("LineNav/LineGiant")
	var servo: TierSection = level.get_node("ServoNav/Section")
	var heap: Section = level.get_node("NavigationRegion3D/Section")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("LineNav").baked
	var map := player.get_world_3d().navigation_map
	var path := PackedVector3Array()
	var top := line.area_center(7) + Vector3.UP * 0.3
	for i in 300:
		path = NavigationServer3D.map_get_path(map, line.area_center(0) + Vector3.UP * 0.3, top, true)
		if not path.is_empty() and path[-1].distance_to(top) < 2.0:
			break
		await get_tree().physics_frame
	check(not path.is_empty() and path[-1].distance_to(top) < 2.0, "a walkable way from the Intake up the ramps to the Assembly Floor (%d points)" % path.size())

	check(not giant.active, "the giant waits while nobody's in the Line")
	var door: SectionDoor = servo.rooms[9].get_node("LineDoor")
	player.add_scrap(door.cost)
	check(door.interact(player) and door.interact(player) and line.room_at_position(player.global_position) == line.rooms[0], "Servo Works' Line door lands you in the Line Intake")
	await frames(3)
	check(giant.active and giant.stage == LineGiant.Stage.BUILDING and rounds.is_held(), "walking in starts the fight: the giant starts building")
	var core: BossPart = giant.core
	core.take_damage(500.0, core.global_position, player)
	check(core.health == core.max_health, "it can't be hurt while it's being built")

	# It bolts robots together near players.
	giant._build_left = 0.0
	await frames(3)
	check(giant._robots.size() == 1 and line.room_at_position(giant._robots[0].global_position) == line.rooms[0], "it bolts a robot together in the player's area")
	for r in giant._robots:
		r.queue_free()

	var amalgam: Amalgam = rounds.spawn_add(AMALGAM, line.area_center(0) + Vector3(5, 0.3, 0))
	var bits := 0
	for t in Amalgam.TRAITS:
		if amalgam.traits & t:
			bits += 1
	check(bits == 2, "an Amalgam gets two traits from other sections' robots (%d)" % amalgam.traits)
	amalgam.queue_free()

	# Each area opened builds more.
	line.gates[0].open()
	await frames(3)
	check(giant.built == 1 and giant.stage == LineGiant.Stage.BUILDING, "opening an area builds the legs")
	var proving: SectionDoor = line.rooms[7].get_node("ProvingDoor")
	check(proving.locked, "the way to the Proving Grounds is behind the giant")
	for g in line.gates:
		g.open()
	for i in 12:
		await get_tree().physics_frame
	check(giant.stage == LineGiant.Stage.COMPLETE and giant.built == 7, "open everything and the giant is complete (%d)" % giant.built)
	check(not proving.locked, "and it smashes the Proving Grounds door open")

	# Its arms sweep the storey edges.
	player.global_position = line.to_global(Vector3(-10, 0.3, 3))
	await frames(2)
	var hp: float = player.health.health + player.health.shields
	giant._sweep(0, true)
	check(player.health.health + player.health.shields < hp, "an arm sweep along the atrium edge hits players there")
	player.global_position = line.area_center(0) + Vector3.UP * 0.3

	# Shoulders, then core, then head.
	core.take_damage(500.0, core.global_position, player)
	check(core.health == core.max_health, "the core is plated until both shoulders break")
	for s in giant.shoulders:
		s.take_damage(s.max_health + 1.0, s.global_position, player)
	core.take_damage(core.max_health + 1.0, core.global_position, player)
	check(core.broken and not giant.head.armored, "break the shoulders and the core opens, then the head")
	giant.head.take_damage(giant.head.max_health + 1.0, giant.head.global_position, player)
	await frames(2)
	check(not giant.active and not Egg.has(&"staff_bot_awake") and giant.rematch_in == 2 and not rounds.is_held(), "beaten without the Staff Bot on the line, it drops nothing and comes back later")

	# Belts.
	var belt: Conveyor = line.find_children("*", "Conveyor", true, false)[0]
	player.global_position = belt.global_position + Vector3.DOWN * 0.4
	await frames(5)
	var at := player.global_position
	await frames(30)
	check(player.global_position.distance_to(at) > 0.8, "a running belt carries you along (%.1f m)" % player.global_position.distance_to(at))

	var chute: Passage = line.rooms[7].get_node("ConveyorHome")
	player.global_position = chute.global_position
	await frames(6)
	check(heap.room_at_position(player.global_position) != null, "the Assembly Floor conveyor drops you back into the Heap")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
