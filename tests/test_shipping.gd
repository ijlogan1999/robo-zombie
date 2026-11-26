extends Node
## The Shipping Bay: container yard bays, crane-lifted shortcuts, ship pads, Packers and
## Security Bots, and the control tower boss.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const PACKER := preload("res://scenes/enemies/packer.tscn")
const BOLT := preload("res://scenes/enemies/bolt_projectile.tscn")

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
	level.get_node("ShippingNav/Section").layout_seed = seed_value + 707
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func hp(player: Player) -> float:
	return player.health.health + player.health.shields


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var valid := true
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var yard: HallSection = level.get_node("ShippingNav/Section")
		var names := []
		for room in yard.rooms:
			names.append(room.display_name)
		valid = valid and yard.rooms.size() == 9 and names[0] == "Shipping Gate" and names[1] == "Tower Bay" and names[7] == "Accounting Gate"
		valid = valid and yard.shifters.size() == 3 and yard.gates.size() == yard.links.size()
		for i in 9:
			valid = valid and yard.depth[i] >= 0 and yard.room_at_position(yard.bay_center(i) + Vector3.UP) == yard.rooms[i]
		orders[str(names)] = true
		level.free()
	check(valid, "12 yards: gate in the south, tower in the middle, Accounting in the north, 3 crane shortcuts")
	check(orders.size() >= 8, "the yards shuffle (%d orders)" % orders.size())

	var level := make_level(5)
	var yard: HallSection = level.get_node("ShippingNav/Section")
	var course: ProvingSection = level.get_node("ProvingNav/Section")
	var tower: ControlTower = level.get_node("ShippingNav/ControlTower")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("ShippingNav").baked
	var door: SectionDoor = course.rooms[5].get_node("ShippingDoor")
	player.add_scrap(door.cost)
	check(not door.locked and door.interact(player) and door.interact(player) and yard.room_at_position(player.global_position) == yard.rooms[0], "the Proving Exit's door leads to the Shipping Gate")
	check((yard.rooms[7].get_node("AccountingDoor") as SectionDoor).arrival_id == &"accounting_from_shipping", "the way on to Accounting is across the yard")
	await frames(3)
	check(not tower.active, "the tower sleeps while you're outside its bay")

	# Crane shortcuts.
	var shifter: ShiftingContainer = yard.shifters[0]
	var low := shifter.position.y
	shifter._left = 0.0
	await get_tree().create_timer(3.5).timeout
	check(shifter.state == ShiftingContainer.State.UP and shifter.position.y > low + 5.0, "a crane lifts a container out of a row, opening a shortcut")
	var robot: Robot = rounds.spawn_add(PACKER, shifter.global_position - Vector3(0, shifter.position.y - low, 0) + Vector3.UP * 0.3)
	robot.freeze(30.0)
	shifter._left = 0.0
	await get_tree().create_timer(4.0).timeout
	check(shifter.position.y > low + 1.0, "it won't come down on anyone standing in the gap")
	robot.queue_free()
	await get_tree().create_timer(4.0).timeout
	check(shifter.state == ShiftingContainer.State.DOWN and is_equal_approx(shifter.position.y, low), "once the gap clears it's set back down")

	# Packers and Security Bots.
	var packer: Packer = rounds.spawn_add(PACKER, yard.bay_center(0) + Vector3(5, 0.3, -5))
	await frames(2)
	packer.rotation.y = 0.0
	var front := packer.global_position + Vector3(0, 1, -2)
	var back := packer.global_position + Vector3(0, 1, 2)
	var start: float = packer.health.health
	packer.take_damage(10.0, front, player)
	var front_loss: float = start - packer.health.health
	packer.take_damage(10.0, back, player)
	var back_loss: float = start - front_loss - packer.health.health
	check(front_loss < back_loss * 0.5, "a Packer's crate lid stops most shots from the front (%.1f vs %.1f)" % [front_loss, back_loss])
	packer.queue_free()
	var bolt: BoltProjectile = BOLT.instantiate()
	bolt.slow_scale = 0.5
	add_child(bolt)
	bolt.global_position = player.global_position + Vector3(0, 1, -3)
	bolt.launch(Vector3(0, 0, 12), 5.0, null)
	await get_tree().create_timer(0.5).timeout
	check(player.speed_scale() < 1.0, "a Security Bot's taser bolt slows you down")

	# Ship pads.
	var pads := yard.find_children("*", "ShipPad", true, false)
	check(not pads.is_empty(), "ships land on pads in the yard (%d)" % pads.size())
	if not pads.is_empty():
		var ship_pad: ShipPad = pads[0]
		player.global_position = ship_pad.global_position + Vector3.UP * 0.3
		player.health.health = player.health.max_health
		var before := hp(player)
		ship_pad.set_state(ShipPad.State.LANDING)
		await get_tree().create_timer(1.0).timeout
		check(hp(player) < before, "rocket exhaust from a landing ship burns (%.0f -> %.0f)" % [before, hp(player)])
		ship_pad.set_state(ShipPad.State.IDLE)

	# The tower.
	for g in yard.gates:
		g.open()
	player.health.health = player.health.max_health
	player.global_position = yard.bay_center(1) + Vector3(10, 0.3, 10)
	await frames(3)
	check(tower.active and tower.stage == ControlTower.Stage.RADAR and rounds.is_held(), "walk into its bay and the tower comes to life")
	tower._call_trouble(player, 2)
	await get_tree().create_timer(1.3).timeout
	var guards := 0
	for r in get_tree().get_nodes_in_group("robots"):
		if r is SecurityBot:
			guards += 1
	check(guards == tower.pod_count, "spotted: a drop pod of Security Bots lands by you (%d)" % guards)
	player.health.health = player.health.max_health
	var before_drop := hp(player)
	tower._call_trouble(player, 1)
	await get_tree().create_timer(1.7).timeout
	check(hp(player) < before_drop, "or a crane drops a container on you")
	tower.dish.take_damage(1e6, tower.dish.global_position, player)
	await frames(2)
	check(tower.stage == ControlTower.Stage.ANTENNAS, "shoot out the dish and it's blind")
	for a in tower.antennas:
		a.take_damage(1e6, a.global_position, player)
	await frames(2)
	check(tower.stage == ControlTower.Stage.CAB, "break the antennas and the cab breaks loose")
	var cab_at := tower.cab.global_position
	await frames(30)
	check(tower.cab.global_position.distance_to(cab_at) > 0.5, "the cab flies around the yard")
	tower.cab.take_damage(1e7, tower.cab.global_position, player)
	await frames(2)
	check(not tower.active and not Egg.has(&"landing_beacon") and tower.rematch_in == 2 and not rounds.is_held(), "beaten without the container on its base, it drops nothing and comes back later")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
