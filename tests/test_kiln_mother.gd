extends Node
## The Kiln Mother: the bell starts it, the Ladle pours lava lanes, valves tip it, the kiln is
## only hurt through its open door, feeders heal it, the golem only takes damage when
## hardened by a coolant pipe, and the boss rule (no drop without the egg step, rematch later).

const LEVEL := preload("res://scenes/levels/heap.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 3
	level.get_node("CrucibleNav/Section").layout_seed = 104
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	var rounds: RoundManager = level.get_node("RoundManager")
	var boss: KilnMother = level.get_node("KilnMother")
	var player: Player = level.get_node("Player")
	var banners: Array[String] = []
	rounds.announced.connect(func(t: String) -> void: banners.append(t))
	await level.get_node("CrucibleNav").baked
	Arrival.send(player, &"crucible_landing")
	for i in 10:
		await get_tree().physics_frame

	check(boss.stage == KilnMother.Stage.ASLEEP and boss.lever.get_prompt(player) != "", "asleep, with a pour bell to ring")
	check(boss.lever.interact(player) and boss.active and rounds.is_held(), "ringing the bell starts the fight and holds the rounds")
	check(banners.has("THE KILN MOTHER AWAKENS"), "everyone gets a banner")
	var start_x := boss.ladle.position
	await get_tree().create_timer(3.6).timeout
	check(boss.ladle.position.distance_to(start_x) > 5.0, "the Ladle rides its rail")
	var lanes := boss.find_children("LavaLane", "", false, false)
	var has_zone := false
	for lane in lanes:
		has_zone = has_zone or not lane.find_children("*", "HazardZone", true, false).is_empty()
	check(has_zone, "it pours a lava lane after a warning")
	check(boss.bar_max > 0.0 and is_equal_approx(boss.bar_value, boss.bar_max), "the bar shows valve health (%.0f)" % boss.bar_max)

	for valve in boss.valves:
		valve.take_damage(10000.0, valve.global_position, player)
	check(boss.stage == KilnMother.Stage.KILN, "breaking all 3 valves tips the Ladle and wakes the kiln")

	var hp: float = boss._kiln_hp
	boss.kiln_core.take_damage(500.0, Vector3.ZERO, player)
	check(boss._kiln_hp == hp, "the kiln shrugs off hits while its door is shut")
	boss._set_door(true)
	boss.kiln_core.take_damage(500.0, Vector3.ZERO, player)
	check(boss._kiln_hp == hp - 500.0, "hits through the open door hurt it")
	boss._set_door(false)

	await get_tree().create_timer(2.3).timeout
	var drones := get_tree().get_nodes_in_group(&"boss_adds")
	check(not drones.is_empty(), "feeder drones fly in")
	if not drones.is_empty():
		var drone: FeederDrone = drones[0]
		hp = boss._kiln_hp
		drone.global_position = boss.kiln.get_node("Mouth").global_position + Vector3(0, 0, -1.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(boss._kiln_hp > hp and boss.door_open, "a feeder that gets through heals the kiln and it opens up to swallow")

	# Kiln stomp: stand next to it.
	player.global_position = boss.kiln.global_position + Vector3(0, 0.2, -3.5)
	var before: float = player.health.health + player.health.shields
	await get_tree().create_timer(2.5).timeout
	var after: float = player.health.health + player.health.shields
	check(after < before, "the kiln stomps players next to it (%.0f -> %.0f)" % [before, after])
	player.health.reset()

	boss._set_door(true)
	boss.kiln_core.take_damage(100000.0, Vector3.ZERO, player)
	check(boss.stage == KilnMother.Stage.GOLEM and boss.golem.visible, "killing the kiln cracks it open: the Slag Golem walks out")
	var golem_body := boss.golem
	var ghp: float = boss._golem_hp
	golem_body.take_damage(300.0, Vector3.ZERO, player)
	check(boss._golem_hp == ghp, "the golem can't be hurt while hot")
	player.global_position = boss.global_position + Vector3(0, 0.3, 30)
	var pipe: BossPart = boss.pipes[0]
	boss.golem.global_position = pipe.global_position + Vector3(0, -1.5, 0) - pipe.position.normalized() * 3.0
	pipe.take_damage(100.0, pipe.global_position, player)
	check(boss.golem_hard, "bursting a coolant pipe next to it hardens it")
	golem_body.take_damage(300.0, Vector3.ZERO, player)
	check(boss._golem_hp == ghp - 300.0, "a hardened golem takes damage")
	golem_body.take_damage(1000000.0, Vector3.ZERO, player)
	check(not boss.active and not rounds.is_held() and boss.rematch_in == 2 and not Egg.has(&"kiln_heart_left"),
		"without the egg step it dies, drops nothing and rounds go on")
	check(not boss.can_start() and banners.has("THE KILN MOTHER FELL, BUT DROPPED NOTHING. IT WILL BE BACK"), "no rematch straight away")
	rounds.round_ended.emit(1)
	rounds.round_ended.emit(2)
	check(boss.can_start() and boss.stage == KilnMother.Stage.ASLEEP, "2 rounds later it's back for a rematch")

	Egg.set_flag(&"grab_magnet")
	boss.start()
	for valve in boss.valves:
		valve.take_damage(100000.0, valve.global_position, player)
	boss._set_door(true)
	boss.kiln_core.take_damage(1000000.0, Vector3.ZERO, player)
	boss._set_hard(true)
	boss.golem.take_damage(1000000.0, Vector3.ZERO, player)
	check(boss.beaten and Egg.has(&"kiln_heart_left") and not boss.can_start(), "with the egg step done it drops the Kiln Heart and stays down")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
