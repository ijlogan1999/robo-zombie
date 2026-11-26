extends Node
## Servo Works: three tiers of clearings with shuffled links, the door in from the Crucible,
## a walkable path up to the canopy, Bug swarms and cable whips, and the conveyor home.

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
	level.get_node("ChassisNav/Section").layout_seed = seed_value + 202
	level.get_node("ServoNav/Section").layout_seed = seed_value + 303
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var valid := true
	var link_sets := {}
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var servo: TierSection = level.get_node("ServoNav/Section")
		var names := []
		for room in servo.rooms:
			names.append(room.display_name)
		valid = valid and servo.rooms.size() == 10 and names[0] == "Crucible Lift" and names[9] == "Canopy Crown"
		valid = valid and names.has("Acid Swamp") and servo.gates.size() == servo.links.size()
		for i in 10:
			valid = valid and servo.depth[i] >= 0 and servo.room_at_position(servo.slot_center(i) + Vector3.UP) == servo.rooms[i]
		link_sets[str(servo.links)] = true
		orders[str(names)] = true
		level.free()
	check(valid, "12 layouts: 10 clearings from the Crucible Lift up to the Canopy Crown, Acid Swamp always in, all reachable")
	check(link_sets.size() >= 8 and orders.size() >= 8, "links and clearings vary (%d link sets, %d orders)" % [link_sets.size(), orders.size()])

	var level := make_level(6)
	var servo: TierSection = level.get_node("ServoNav/Section")
	var dome: DomeSection = level.get_node("CrucibleNav/Section")
	var heap: Section = level.get_node("NavigationRegion3D/Section")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("ServoNav").baked
	var map := player.get_world_3d().navigation_map
	var path := PackedVector3Array()
	for i in 300:
		path = NavigationServer3D.map_get_path(map, servo.slot_center(0) + Vector3.UP * 0.3, servo.slot_center(9) + Vector3.UP * 0.3, true)
		if not path.is_empty() and path[-1].distance_to(servo.slot_center(9)) < 2.0:
			break
		await get_tree().physics_frame
	check(not path.is_empty() and path[-1].distance_to(servo.slot_center(9)) < 2.0, "robots and players can walk from the lift up the ramps to the canopy (%d points)" % path.size())

	var door: SectionDoor
	for d in dome.exit_doors:
		if d.arrival_id == &"servo_from_crucible":
			door = d
	player.add_scrap(door.cost)
	door.interact(player)
	check(door.interact(player) and servo.room_at_position(player.global_position) == servo.rooms[0], "the Crucible's Servo Works door lands you at the Crucible Lift")

	# Bugs come in swarms. (Wait out a spawn-point update so only Servo's points are live.)
	for i in 60:
		await get_tree().physics_frame
	rounds.spawn_table = []
	rounds.round_number = 5
	rounds._to_spawn = 20
	var before := get_tree().get_nodes_in_group("robots").size()
	rounds._spawn_robot()
	var bugs := 0
	for robot in get_tree().get_nodes_in_group("robots"):
		if robot is Bug:
			bugs += 1
	check(bugs == 5 and rounds._to_spawn == 15, "a Bug spawn is a swarm of 5, all counted (%d bugs, %d left)" % [bugs, rounds._to_spawn])
	for robot in get_tree().get_nodes_in_group("robots"):
		robot.queue_free()
	var _unused := before

	# Cable whips.
	var whips := servo.find_children("*", "CableWhip", true, false)
	check(not whips.is_empty(), "cable whips hang in the jungle (%d)" % whips.size())
	var whip: CableWhip = whips[0]
	player.global_position = whip.global_position + Vector3(0.5, -4.6, 0)
	player.velocity = Vector3.ZERO
	var hp: float = player.health.health + player.health.shields
	await get_tree().create_timer(1.2).timeout
	check(whip.state == CableWhip.State.HOLD and player.health.health + player.health.shields < hp, "walk under a whip and it grabs and burns you")
	whip.take_damage(10.0, whip.global_position, player)
	check(whip.state == CableWhip.State.BROKEN, "shooting it snaps it and lets go")

	var chute: Passage = servo.rooms[9].get_node("ConveyorHome")
	player.global_position = chute.global_position
	for i in 6:
		await get_tree().physics_frame
	check(heap.room_at_position(player.global_position) != null, "the Canopy Crown conveyor drops you back into the Heap")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
