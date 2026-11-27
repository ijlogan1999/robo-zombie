extends Node
## Cold Storage: the shelved hall's shuffled bays, the doors in from Servo Works and the
## Chassis Yard, frozen stock on the shelves, ice, coolant leaks, and QUOTA's backup body.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const THAWED := preload("res://scenes/enemies/thawed.tscn")
const SCRAPPER := preload("res://scenes/enemies/scrapper.tscn")

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
	var link_sets := {}
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var hall: HallSection = level.get_node("ColdNav/Section")
		var names := []
		for room in hall.rooms:
			names.append(room.display_name)
		valid = valid and hall.rooms.size() == 9 and names[0] == "Loading Bay" and names[1] == "Cryo Chamber"
		valid = valid and hall.gates.size() == hall.links.size() and not hall.shelf_spots.is_empty()
		for i in 9:
			valid = valid and hall.depth[i] >= 0 and hall.room_at_position(hall.bay_center(i) + Vector3.UP) == hall.rooms[i]
		link_sets[str(hall.links)] = true
		orders[str(names)] = true
		level.free()
	check(valid, "12 halls: 9 bays, Loading Bay in the south, Cryo Chamber in the middle, all reachable")
	check(link_sets.size() >= 8 and orders.size() >= 8, "shelf gaps and bays vary (%d gap sets, %d orders)" % [link_sets.size(), orders.size()])

	var level := make_level(4)
	var hall: HallSection = level.get_node("ColdNav/Section")
	var servo: TierSection = level.get_node("ServoNav/Section")
	var chassis: Section = level.get_node("ChassisNav/Section")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	var boss: BackupBody = level.get_node("ColdNav/BackupBody")
	await level.get_node("ColdNav").baked
	var map := player.get_world_3d().navigation_map
	var floor_point := Vector3.ZERO
	var probe := hall.bay_center(0) + Vector3(5, 0.5, -6)
	for i in 300:
		floor_point = NavigationServer3D.map_get_closest_point(map, probe)
		if floor_point.distance_to(probe) < 2.0:
			break
		await get_tree().physics_frame
	check(absf(floor_point.y) < 0.6 and floor_point.distance_to(probe) < 2.0, "Cold Storage's navmesh lies on its floor, not the roof (y %.1f)" % floor_point.y)

	# In from Servo Works and the Chassis Yard.
	var servo_door: SectionDoor = servo.rooms[9].get_node("ColdStorageDoor")
	player.add_scrap(servo_door.cost)
	check(not servo_door.locked and servo_door.interact(player) and servo_door.interact(player), "the Canopy Crown's Cold Storage door opens")
	check(hall.room_at_position(player.global_position) == hall.rooms[0], "and lands you in the Loading Bay")
	var chassis_door: SectionDoor = chassis.rooms[chassis.rooms.size() - 1].get_node("ColdStorageDoor")
	player.add_scrap(chassis_door.cost)
	check(chassis_door.interact(player) and chassis_door.interact(player) and hall.room_at_position(player.global_position) == hall.rooms[0], "so does the Outflow's, from the Chassis Yard")
	var back: SectionDoor = hall.rooms[0].get_node("ServoDoor")
	player.add_scrap(back.cost)
	check(back.interact(player) and back.interact(player) and servo.room_at_position(player.global_position) == servo.rooms[9], "the Loading Bay's door back takes you to the Canopy Crown")

	# Frozen stock on the shelves.
	player.global_position = hall.bay_center(0) + Vector3(0, 0.3, 8)
	await frames(10)
	var spot: Marker3D = null
	for s in hall.shelf_spots:
		if hall.room_at_position(s.global_position) == hall.rooms[0]:
			spot = s
			break
	var robot: Thawed = rounds.spawn_add(THAWED, spot.global_position + spot.global_basis.z * -2.0 + Vector3.UP * 0.3)
	await frames(5)
	check(robot.asleep and robot.global_position.distance_to(spot.global_position) < 0.5, "a Thawed robot takes a shelf spot in an open bay and sleeps in ice")
	await frames(30)
	check(robot.asleep, "it stays put while nobody's near")
	player.global_position = spot.global_position + (-spot.global_basis.z) * 5.0 + Vector3.DOWN * 1.0
	await frames(5)
	check(not robot.asleep, "walk up to it and it cracks free")
	await frames(90)
	check(robot.global_position.y < hall.global_position.y + 0.5 and robot.is_on_floor(), "and hops down off the shelf (y %.2f)" % (robot.global_position.y - hall.global_position.y))
	robot.queue_free()

	# Ice.
	var ice: IcePatch = hall.find_children("*", "IcePatch", true, false)[0]
	player.global_position = ice.global_position + Vector3.DOWN * 0.4
	await frames(8)
	check(player.traction() < 0.5, "frost on the floor: you can barely grip (%.2f)" % player.traction())

	# Coolant leaks.
	var leaks := hall.find_children("*", "CoolantLeak", true, false)
	check(not leaks.is_empty(), "coolant leaks in the hall (%d)" % leaks.size())
	var leak: CoolantLeak = leaks[0]
	var victim: Robot = rounds.spawn_add(SCRAPPER, leak.global_position + Vector3(2, 0.3, 0))
	player.global_position = leak.global_position + Vector3(-2, 0.3, 0)
	await frames(3)
	var hp: float = player.health.health + player.health.shields
	leak.take_damage(5.0, leak.global_position, player)
	await get_tree().create_timer(0.6).timeout
	check(leak.bursting and victim.is_frozen(), "shoot a leak and robots in the cloud freeze solid")
	check(player.health.health + player.health.shields < hp, "and players in it get frostbite")
	victim.queue_free()
	player.global_position = hall.bay_center(0) + Vector3(0, 0.3, 8)

	# QUOTA's backup body.
	var lever: Node = boss.get_node("ThawSwitch")
	check(not boss.can_start() and "no power" in lever.get_prompt(player), "the thaw switch is dead until the coil and its board are in")
	var cryo := hall.rooms[1]
	var coil: EggSocket = cryo.get_node("CoilSocket")
	var board: EggSocket = cryo.get_node("BoardSocket")
	check(not coil.interact(player), "you can't install a coil you don't have")
	Egg.set_flag(&"thaw_coil")
	Egg.set_flag(&"thaw_board")
	check(coil.interact(player) and board.interact(player) and boss.can_start(), "install the Thaw Coil and its board and the switch has power")
	check(lever.interact(player) and boss.stage == BackupBody.Stage.THAW and rounds.is_held(), "throw it: the thaw-out starts and the rounds hold")
	await frames(60)
	var thaw_a := boss.thaw
	var max_hp := boss.bar_max
	boss.tank.take_damage(100.0, boss.tank.global_position, player)
	await frames(1)
	check(boss.bar_value == max_hp - 50.0, "shooting through the ice chips the body at half damage")
	boss.valves[0].take_damage(1000.0, boss.valves[0].global_position, player)
	var before_vent := boss.thaw
	await frames(60)
	var vent_rate := boss.thaw - before_vent
	check(boss.venting and vent_rate < thaw_a * 0.6, "a burst coolant valve slows the thaw (%.4f vs %.4f a second)" % [vent_rate, thaw_a])
	boss._wave_left = 0.0
	await frames(3)
	var adds := 0
	for r in get_tree().get_nodes_in_group("robots"):
		if r is Robot and r.global_position.distance_to(boss.global_position) < 20.0:
			adds += 1
	check(adds > 0, "QUOTA sends waves while it thaws (%d)" % adds)
	boss.thaw = 0.999
	boss._vent_left.fill(0.0)
	await frames(5)
	check(boss.stage == BackupBody.Stage.FREE and boss.body.visible, "the ice shatters and the body walks free")
	(boss.body as Node).take_damage(boss.bar_value + 1.0, boss.body.global_position, player)
	await frames(2)
	check(boss.stage == BackupBody.Stage.DEAD and Egg.has(&"admin_badge") and not rounds.is_held(), "beat it and it drops the Admin Badge; rounds go on")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
