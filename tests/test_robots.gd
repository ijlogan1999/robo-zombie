extends Node

const LEVEL := preload("res://scenes/levels/test_room.tscn")
const SKITTER := preload("res://scenes/enemies/skitter.tscn")
const BOLTER := preload("res://scenes/enemies/bolter.tscn")
const SCRAPPER := preload("res://scenes/enemies/scrapper.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _ready() -> void:
	var level: Node3D = LEVEL.instantiate()
	var rounds: RoundManager = level.get_node("RoundManager")
	rounds.first_break_time = 9999.0
	add_child(level)
	await level.get_node("NavigationRegion3D").baked
	for d in level.get_node("Targets").get_children():
		d.queue_free()
	var player: Player = level.get_node("Player")
	player.global_position = Vector3(0, 0.1, 20)
	for i in 3:
		await get_tree().physics_frame

	# Spawn table
	var counts := {}
	for i in 600:
		var scene := rounds.pick_robot_scene(1)
		counts[scene.resource_path] = counts.get(scene.resource_path, 0) + 1
	check(counts.size() == 1 and counts.has(SCRAPPER.resource_path), "round 1: only Scrappers")
	counts.clear()
	for i in 600:
		var scene := rounds.pick_robot_scene(8)
		counts[scene.resource_path] = counts.get(scene.resource_path, 0) + 1
	check(counts.size() == 3 and counts[SCRAPPER.resource_path] > counts[SKITTER.resource_path] \
			and counts[SKITTER.resource_path] > counts[BOLTER.resource_path], "round 8: all three types, Scrappers most common (%s)" % [counts.values()])

	# Skitter stats
	var skitter: Robot = SKITTER.instantiate()
	skitter.configure(rounds.robot_health_for_round(5), rounds.robot_speed_for_round(5))
	var scrapper: Robot = SCRAPPER.instantiate()
	scrapper.configure(rounds.robot_health_for_round(5), rounds.robot_speed_for_round(5))
	check(skitter.get_node("HealthComponent").max_health < scrapper.get_node("HealthComponent").max_health * 0.5 \
			and skitter.move_speed > scrapper.move_speed * 1.4, "Skitter: under half the health, much faster")
	scrapper.free()

	# Skitter chases and bites
	rounds.add_child(skitter)
	skitter.global_position = Vector3(0, 0.2, 8)
	player.health.reset()
	var start_hp := player.health.health + player.health.shields
	await get_tree().create_timer(4.0).timeout
	check(player.health.health + player.health.shields < start_hp, "Skitter reaches the player and bites")
	skitter.queue_free()

	# Bolter: holds at range and shoots
	player.health.reset()
	player.global_position = Vector3(0, 0.1, 20)
	var bolter: RangedRobot = BOLTER.instantiate()
	bolter.configure(100.0, 3.0)
	rounds.add_child(bolter)
	bolter.global_position = Vector3(0, 0.2, -2)
	var saw_bolt := false
	var closest := INF
	var t := 0.0
	start_hp = player.health.health + player.health.shields
	while t < 7.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		closest = minf(closest, bolter.global_position.distance_to(player.global_position))
		if not saw_bolt:
			for n in get_tree().current_scene.get_children():
				if n is BoltProjectile:
					saw_bolt = true
			for n in level.get_children():
				if n is BoltProjectile:
					saw_bolt = true
	check(saw_bolt, "Bolter fires bolts")
	check(closest > 9.0, "Bolter keeps its distance (closest %.1f m)" % closest)
	check(player.health.health + player.health.shields < start_hp, "bolts hurt the player")

	# Line of sight: hide the player behind the wall-run wall.
	player.global_position = Vector3(-6, 0.1, -18)
	bolter.global_position = Vector3(6, 0.2, -18)
	bolter._repath_left = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not bolter.has_line_of_sight(), "a wall blocks the Bolter's line of sight")
	bolter.queue_free()

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
