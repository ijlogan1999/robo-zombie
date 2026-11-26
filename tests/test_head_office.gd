extends Node
## Head Office and QUOTA: the lift from Accounting, the doors locking behind you, three
## shield layers broken by arena tasks, damage only while exposed, and the run ending in a
## win (plain, or true with the upload line cut).

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


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var level := make_level(3)
	var office: HallSection = level.get_node("AccountingNav/Section")
	var arena: Section = level.get_node("HeadOfficeNav/Section")
	var quota: Quota = level.get_node("HeadOfficeNav/Quota")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("HeadOfficeNav").baked
	check(arena.rooms.size() == 1 and arena.rooms[0].display_name == "Head Office", "Head Office is one big arena")
	var lift: SectionDoor = office.rooms[7].get_node("HeadOfficeDoor")
	Egg.set_flag(&"staff_bot_cleared")
	Egg.set_flag(&"landing_beacon")
	await frames(1)
	check(not lift.locked, "with the Staff Bot cleared, the lift opens")
	check(lift.interact(player) and lift.interact(player) and arena.room_at_position(player.global_position) != null, "the lift takes you up into Head Office")
	await frames(3)
	var exit: SectionDoor = arena.rooms[0].get_node("AccountingDoor")
	check(quota.active and quota.stage == Quota.Stage.SHIELDED and rounds.is_held(), "walking in starts QUOTA")
	check(exit.locked, "and the doors lock behind you")

	# Shielded: shooting the core does nothing.
	var hp := quota.core.health
	quota.core.take_damage(500.0, quota.core.global_position, player)
	check(quota.core.health == hp, "the shield stops every shot at the core")
	await get_tree().create_timer(5.0).timeout
	var adds := get_tree().get_nodes_in_group("robots").size()
	check(adds > 0, "QUOTA ships robots in the whole time (%d)" % adds)
	for r in get_tree().get_nodes_in_group("robots"):
		r.queue_free()

	# Layer 1: power.
	check(quota.task == Quota.Task.POWER and quota._slag[0].monitoring, "layer 1: reroute power, with slag on the floor")
	for t in quota.terminals:
		player.global_position = t.global_position + Vector3(1.0, 0.3, 1.0)
		await get_tree().create_timer(quota.terminal_time + 0.4).timeout
	check(quota.stage == Quota.Stage.EXPOSED and not quota._slag[0].monitoring, "stand on all three terminals and the first layer falls")
	quota.core.take_damage(500.0, quota.core.global_position, player)
	check(quota.core.health < hp, "while it's exposed, shots hurt the core")
	quota._exposed_left = 0.0
	await frames(2)
	check(quota.stage == Quota.Stage.SHIELDED and quota.task == Quota.Task.CHUTES and quota._belts[0].monitoring, "the window closes and layer 2 comes up: chutes and conveyor floors")

	# Layer 2: chutes.
	for c in quota.chutes:
		c.take_damage(1e6, c.global_position, player)
	await frames(2)
	check(quota.stage == Quota.Stage.EXPOSED, "jam both chutes and the second layer falls")
	quota._exposed_left = 0.0
	await frames(2)
	check(quota.task == Quota.Task.COOLING, "layer 3: the cooling tower")

	# Layer 3: cooling.
	player.global_position = quota.cooling_pad.global_position + Vector3(0, 0.3, 1)
	quota._flicker_left = 0.0
	await frames(3)
	check(quota._walls_up and quota._walls[0].visible, "hard-light walls flicker up across the floor")
	quota.cooling_progress = quota.cooling_time - 1.0
	await get_tree().create_timer(1.3).timeout
	check(quota.stage == Quota.Stage.EXPOSED and not quota._walls_up, "hold the pad until the tower overloads and the last layer falls")
	quota._exposed_left = 0.0
	await frames(2)
	check(quota.task == Quota.Task.POWER and quota.stage == Quota.Stage.SHIELDED, "if the core's still alive, the shield starts over")

	# Finish it.
	quota._break_layer()
	quota.core.take_damage(1e8, quota.core.global_position, player)
	await frames(2)
	check(not quota.active and rounds.phase == RoundManager.Phase.OVER and rounds.ending == quota.plain_ending, "destroy the core and the run ends in the plain win (the beacon calls the ship)")
	level.free()
	await frames(2)

	# True ending: the upload line.
	Egg.clear()
	get_tree().paused = false
	level = make_level(5)
	arena = level.get_node("HeadOfficeNav/Section")
	quota = level.get_node("HeadOfficeNav/Quota")
	rounds = level.get_node("RoundManager")
	player = level.get_node("Player")
	await level.get_node("HeadOfficeNav").baked
	Egg.set_flag(&"kill_code")
	Egg.set_flag(&"override_chip")
	player.global_position = arena.rooms[0].global_position + Vector3(0, 0.3, 28)
	await frames(3)
	check(quota.active and quota.upload_console.visible, "with the kill code, the upload line console is there")
	check(quota.upload_console.interact(player) and Egg.has(&"upload_cut"), "the chip cuts QUOTA's upload line")
	quota._break_layer()
	quota.core.take_damage(1e8, quota.core.global_position, player)
	await frames(2)
	check(rounds.ending == quota.true_ending, "destroy the core now and QUOTA is gone for good")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().paused = false
	get_tree().quit(1 if fails else 0)
