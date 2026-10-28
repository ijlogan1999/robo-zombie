extends Node

const LEVEL := preload("res://scenes/levels/junkyard.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
const ROBOT := preload("res://scenes/enemies/scrapper.tscn")

var fails := 0
var checks := 0
var level: Node3D
var a: Player
var rounds: RoundManager
var run_over_count := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame


func kill(p: Player) -> void:
	p._grace_left = 0.0
	p.health.shields = 0.0
	p.take_damage(9999, Vector3.ZERO)


## Plays the hack perfectly: press whenever the cursor is in the window.
func play_hack(p: Player, perfect: bool) -> void:
	var hack: HackMinigame = p.get_node("HUD/HackMinigame")
	hack.read_input = false
	var guard := 0
	while hack.running and guard < 2000:
		guard += 1
		await get_tree().process_frame
		if perfect and hack.cursor_in_window():
			hack.press()
		elif not perfect and not hack.cursor_in_window():
			hack.press()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 4242
	rounds = level.get_node("RoundManager")
	rounds.first_break_time = 9999.0 # No waves during the test.
	add_child(level)
	rounds.run_over.connect(func(_n: int) -> void: run_over_count += 1)
	a = level.get_node("Player")
	await level.get_node("NavigationRegion3D").baked
	await frames()

	check(a.hack_charges == 2 and a.get_node("HUD/HackCharges").text == "HACK CHARGES  2", "start with 2 hack charges, shown on the HUD")

	# --- Going down
	kill(a)
	await frames()
	check(a.life == Player.Life.DOWNED, "losing all health downs the player instead of respawning")
	check(not a.weapon_holder.visible, "gun is put away while downed")
	check(not a.take_damage(50, Vector3.ZERO) and a.life == Player.Life.DOWNED, "downed body takes no more damage")
	check(a.get_node("HUD/DownedInfo").visible and "[E] Hack" in a.get_node("HUD/DownedInfo").text, "downed screen offers the hack")
	check(run_over_count == 0, "solo with a hack charge left: the run isn't over")

	var robot: Robot = ROBOT.instantiate()
	rounds.add_child(robot)
	robot.global_position = a.global_position + Vector3(3, 0.2, 0)
	await get_tree().create_timer(0.4).timeout
	check(robot.target == null, "robots ignore a downed player")

	# --- Successful hack
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	check(a.life == Player.Life.HACKING and a.hack_charges == 1, "E starts the hack and uses a charge")
	await play_hack(a, true)
	await frames()
	check(a.life == Player.Life.ALIVE and is_equal_approx(a.health.health, a.health.max_health * 0.5), "winning the hack: back up with half health")
	check(a.weapon_holder.visible, "gun comes back")
	check(not a.take_damage(30, Vector3.ZERO) and a.health.health == 50.0, "2 s of grace after getting up")
	await get_tree().create_timer(0.5).timeout
	check(robot.target == a, "robots chase the player again")
	robot.queue_free()

	# --- Hack minigame rules
	var hack: HackMinigame = a.get_node("HUD/HackMinigame")
	hack.read_input = false
	hack.start()
	var w := hack.window_width
	while not hack.cursor_in_window():
		await get_tree().process_frame
	hack.press()
	check(hack.locked == 1 and hack.window_width < w and hack._speed > hack.start_speed, "each lock shrinks the window and speeds the cursor")
	hack.time_left = 0.05
	var timed_out := [false]
	hack.finished.connect(func(ok: bool) -> void: timed_out[0] = not ok, CONNECT_ONE_SHOT)
	await get_tree().create_timer(0.2).timeout
	check(timed_out[0] and not hack.running, "running out of time fails the hack")

	# --- Co-op: a second player
	var b: Player = PLAYER.instantiate()
	level.add_child(b)
	b.global_position = a.global_position + Vector3(0, 0, -1.6)
	a.rotation = Vector3.ZERO
	a.get_node("Head").rotation.x = -0.6
	await frames()
	b.hack_charges = 0 # So the test's E press only revives.
	kill(b)
	await frames(10)
	check(b.life == Player.Life.DOWNED and run_over_count == 0, "co-op: one player down, one up - run continues")
	check(a.get_node("Head/Camera3D/Interactor").prompt() == "[Hold E] Revive teammate", "looking at a downed teammate shows the revive prompt")
	Input.action_press("interact")
	await get_tree().create_timer(1.5).timeout
	var halfway: bool = b.life == Player.Life.DOWNED and a.get_node("Head/Camera3D/Interactor").hold_progress > 0.3
	await get_tree().create_timer(1.8).timeout
	Input.action_release("interact")
	check(halfway and b.life == Player.Life.ALIVE, "holding E for 3 s revives the teammate")

	# Bleed out -> out until next round -> respawn by a teammate.
	b.bleed_out_time = 0.5
	kill(b)
	await get_tree().create_timer(0.9).timeout
	check(b.life == Player.Life.OUT and not b.visible and run_over_count == 0, "co-op: bleeding out loses the signal, run continues")
	rounds._start_next_round()
	await frames()
	check(b.life == Player.Life.ALIVE and b.visible and b.global_position.distance_to(a.global_position) < 3.0 \
			and b.health.health == b.health.max_health, "next round starts: back in a fresh body next to the teammate")
	for r in get_tree().get_nodes_in_group("robots"):
		if r is Robot:
			r.queue_free()
	rounds.phase = RoundManager.Phase.BREAK
	b.queue_free()
	await frames()

	# --- Hack uplink
	var uplink: HackUplink = level.find_children("HackUplink", "", true, false)[0]
	a.scrap = 0
	check(not uplink.interact(a), "can't buy a hack charge while broke")
	a.add_scrap(1000)
	var before := a.hack_charges
	check(uplink.interact(a) and a.hack_charges == before + 1 and a.scrap == 800, "Hack Uplink sells a charge for 200 scrap")
	a.hack_charges = a.max_hack_charges
	check(not uplink.interact(a) and a.scrap == 800, "can't go over the max of 5 charges")

	# --- Solo: failed hack ends the run
	a.hack_charges = 1
	await get_tree().create_timer(2.1).timeout # Grace from respawn checks.
	kill(a)
	await frames()
	a.start_hack()
	await play_hack(a, false)
	await frames()
	check(a.life == Player.Life.DOWNED and a.hack_tried and run_over_count == 1 and rounds.phase == RoundManager.Phase.OVER,
			"solo: a failed hack ends the run")
	await get_tree().create_timer(2.3).timeout
	var screen: Control = rounds.get_node("RunOverScreen/Panel") as Control
	check(get_tree().paused and screen.visible, "run-over screen appears and pauses the game")
	check(screen.get_node("Summary").text == "You made it to round 1", "summary shows the round reached")
	get_tree().paused = false

	# --- Solo: no charges ends the run immediately (fresh level)
	level.queue_free()
	await frames()
	level = LEVEL.instantiate()
	rounds = level.get_node("RoundManager")
	rounds.first_break_time = 9999.0
	add_child(level)
	run_over_count = 0
	rounds.run_over.connect(func(_n: int) -> void: run_over_count += 1)
	a = level.get_node("Player")
	await frames(5)
	a.hack_charges = 0
	kill(a)
	await frames()
	check(run_over_count == 1, "solo: going down with no hack charges ends the run")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
