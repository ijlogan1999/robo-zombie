extends Node
## The Proving Grounds: the long course, checkpoint holds instead of scrap gates, the
## gauntlet pausing the rounds, turrets and mines, and the grapple at the far end.

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
	level.get_node("ProvingNav/Section").layout_seed = seed_value + 606
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
	var valid := true
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var course: ProvingSection = level.get_node("ProvingNav/Section")
		var names := []
		for room in course.rooms:
			names.append(room.display_name)
		valid = valid and course.rooms.size() == 6 and names[0] == "Proving Entry" and names[5] == "Proving Exit" and course.gates.size() == 5
		for g in course.gates:
			valid = valid and g is CheckpointGate
		for i in 6:
			valid = valid and course.room_at_position(course.yard_center(i) + Vector3.UP) == course.rooms[i]
		orders[str(names)] = true
		level.free()
	check(valid, "12 courses: entry, 4 trial yards, exit, a checkpoint between each")
	check(orders.size() >= 8, "the trial yards shuffle (%d orders)" % orders.size())

	var level := make_level(2)
	var course: ProvingSection = level.get_node("ProvingNav/Section")
	var line: LineSection = level.get_node("LineNav/Section")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("ProvingNav").baked
	var map := player.get_world_3d().navigation_map
	var path := PackedVector3Array()
	var end := course.yard_center(5) + Vector3.UP * 0.3
	for i in 300:
		path = NavigationServer3D.map_get_path(map, course.yard_center(0) + Vector3.UP * 0.3, end, true)
		if not path.is_empty() and path[-1].distance_to(end) < 2.0:
			break
		await get_tree().physics_frame
	check(not path.is_empty() and path[-1].distance_to(end) < 2.0, "the course runs end to end (%d points)" % path.size())

	check(course.gauntlet == ProvingSection.Gauntlet.WAITING, "the gauntlet waits for players")
	var door: SectionDoor = line.rooms[7].get_node("ProvingDoor")
	door.unlock()
	player.add_scrap(door.cost)
	check(door.interact(player) and door.interact(player) and course.room_at_position(player.global_position) == course.rooms[0], "the Line's blown door leads into the Proving Entry")
	await frames(3)
	check(course.gauntlet == ProvingSection.Gauntlet.RUNNING and rounds.is_held(), "walking in starts the gauntlet and the rounds pause")
	course._spawn_left = 0.0
	await frames(3)
	check(course.robots.size() == 1, "robots pour in around the players")
	for r in course.robots:
		r.queue_free()
	course.robots.clear()

	var first: CheckpointGate = course.gates[0]
	var second: CheckpointGate = course.gates[1]
	player.add_scrap(100000)
	check(not first.interact(player) and not first.is_open, "a checkpoint can't be bought open")
	check(first.armed and not second.armed, "only the next checkpoint counts a hold")
	player.global_position = course.yard_center(0) + Vector3(0, 0.3, 8)
	await frames(30)
	check(first.progress == 0.0, "away from the pad, nothing happens")
	player.global_position = first.pad_at + Vector3.UP * 0.3
	await frames(60)
	check(first.progress > 0.03 and first.progress < 0.2, "on the pad, the hold counts up (%.2f)" % first.progress)
	first.progress = 0.999
	await frames(3)
	check(first.is_open and second.armed and course.gauntlet == ProvingSection.Gauntlet.RUNNING, "hold it and the checkpoint opens; the next one arms")
	check(second.hold_time > first.hold_time, "later checkpoints hold longer")
	for g in course.gates:
		g.open()
	await frames(3)
	check(course.gauntlet == ProvingSection.Gauntlet.DONE and not rounds.is_held(), "past the last checkpoint the gauntlet ends and the rounds resume")

	# Turrets.
	var turrets := course.find_children("*", "SentryTurret", true, false)
	if turrets.is_empty():
		check(false, "no turrets in this course")
	else:
		var turret: SentryTurret = turrets[0]
		var away := turret.global_position - Vector3(0, turret.global_position.y - course.global_position.y, 0)
		player.global_position = away + Vector3(6, 0.3, 6)
		player.health.health = player.health.max_health
		var before := hp(player)
		await get_tree().create_timer(2.6).timeout
		check(hp(player) < before, "a turret paints you and fires (%.0f -> %.0f)" % [before, hp(player)])
		turret.take_damage(turret.max_health + 1.0, turret.global_position)
		check(turret.down, "shoot it enough and it sparks out")
	player.global_position = course.yard_center(0) + Vector3(0, 0.3, 8)

	# Mines.
	var mines := course.find_children("*", "LandMine", true, false)
	if mines.is_empty():
		check(false, "no mines in this course")
	else:
		var mine: LandMine = mines[0]
		player.health.health = player.health.max_health
		var before := hp(player)
		player.global_position = mine.global_position + Vector3.UP * 0.2
		await get_tree().create_timer(1.0).timeout
		check(not mine.armed and hp(player) < before, "step on a mine and it blows (%.0f -> %.0f)" % [before, hp(player)])

	# The grapple at the end.
	var rack: GrapplePickup = course.rooms[5].get_node("GrappleRack")
	check(not player.has_grapple() and rack.interact(player) and player.has_grapple(), "the grapple rack at the end gives you a grapple")
	var anchor: Node3D = course.rooms[5].get_node("TowerAnchor")
	player.global_position = anchor.global_position + Vector3(0, -8.2, 14)
	await frames(3)
	player.look_at(Vector3(anchor.global_position.x, player.global_position.y, anchor.global_position.z))
	var cam := player.get_viewport().get_camera_3d()
	cam.look_at(anchor.global_position)
	await frames(2)
	check(player.grapple.aimed_anchor() == anchor, "aim at a yellow anchor and the grapple locks on")
	check(player.grapple.fire(), "fire it")
	await frames(70)
	check(player.global_position.distance_to(anchor.global_position) < 4.0, "and it zips you up to the anchor (%.1f m off)" % player.global_position.distance_to(anchor.global_position))
	check(not player.grapple.fire(), "then it has to cool down")
	check((course.rooms[5].get_node("ShippingDoor") as SectionDoor).arrival_id == &"shipping_from_proving", "the way on to the Shipping Bay is at the end")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
