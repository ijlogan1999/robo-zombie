extends Node
## Automated co-op check. Run two copies of the game (see tests/run_net_test.sh):
##   host:   -- --host --autostart=2 --net-test=host
##   client: -- --join=127.0.0.1 --net-test=client
## Each copy prints PASS/FAIL lines for what it can see, then quits.

var role := "host"
var fails := 0
var checks := 0
var level: Node
var rounds: RoundManager
var me: Player


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print("[%s] %s %s" % [role, "PASS" if ok else "FAIL", what])


## Waits until condition() is true or the timeout runs out. Returns whether it came true.
func wait_for(condition: Callable, timeout := 10.0) -> bool:
	var left := timeout
	while left > 0.0:
		if condition.call():
			return true
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	return condition.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var in_game := await wait_for(func() -> bool:
		return get_tree().current_scene != null and get_tree().current_scene.is_in_group("game_level"), 20.0)
	check(in_game, "reached the game scene")
	if not in_game:
		_finish()
		return
	await get_tree().physics_frame
	level = get_tree().current_scene
	rounds = level.get_node("RoundManager")
	var names := PackedStringArray()
	for room in (level.get_node("NavigationRegion3D/Section") as Section).rooms:
		names.append(room.display_name)
	print("[%s] LAYOUT %d %s" % [role, Net.layout_seed, ",".join(names)])
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority():
			me = player
	check(get_tree().get_nodes_in_group("players").size() == 2 and me != null, "two player bodies, one of them mine")
	if role == "host":
		await _host()
	else:
		await _client()
	_finish()


func _physics_process(_delta: float) -> void:
	# Host: robots can't hurt anyone during the test, so downs only happen on purpose.
	if role == "host" and is_instance_valid(level):
		for robot: Robot in get_tree().get_nodes_in_group("robots"):
			robot.attack_damage = 0.0


func _host() -> void:
	var friend: Player = level.get_node("Player_%d" % Net.peers[1])
	check(await wait_for(func() -> bool: return friend.global_position.distance_to(Vector3(6, 0.1, 6)) < 1.0, 10.0),
			"host sees the client's player move")
	check(await wait_for(func() -> bool: return rounds.round_number == 1, 10.0), "round 1 starts")
	check(await wait_for(func() -> bool: return rounds.remaining() < rounds.robots_for_round(1), 20.0),
			"the client's shot destroyed a robot on the host")
	check(await wait_for(func() -> bool: return me.scrap > 0, 10.0), "client picked up scrap and the host got paid too")
	var gate: Gate = level.get_node("NavigationRegion3D/Section/Gate0")
	check(await wait_for(func() -> bool: return gate.is_open, 10.0), "client opened a gate: open on the host")

	await get_tree().create_timer(1.0).timeout
	friend.take_damage(99999.0, Vector3.ZERO)
	check(await wait_for(func() -> bool: return friend.life == Player.Life.DOWNED, 5.0), "host's hit downs the client; host sees it")
	await get_tree().create_timer(0.5).timeout
	friend.interact(me)
	check(await wait_for(func() -> bool: return friend.life == Player.Life.ALIVE, 5.0), "host revives the client")

	# Clear the round so the client can press the button.
	var cleared := await wait_for(func() -> bool:
		for robot: Robot in get_tree().get_nodes_in_group("robots"):
			robot.take_damage(99999.0, robot.global_position, me)
		return rounds.phase == RoundManager.Phase.BREAK, 30.0)
	check(cleared, "round 1 cleared")
	check(await wait_for(func() -> bool: return rounds.phase == RoundManager.Phase.COUNTDOWN, 10.0),
			"client pressed the next-round button: countdown on the host")
	await get_tree().create_timer(2.0).timeout # Let the client finish first.


func _client() -> void:
	check(me.name != "Player" and me.get_node("Head/Camera3D").current, "my body is Player_<id> with the active camera")
	await get_tree().create_timer(1.0).timeout
	me.global_position = Vector3(6, 0.1, 6)
	check(await wait_for(func() -> bool: return rounds.round_number == 1, 12.0), "client hears round 1 start")
	check(await wait_for(func() -> bool: return not get_tree().get_nodes_in_group("robots").is_empty(), 10.0),
			"host's robots show up in the client's game")
	var robot: Robot = get_tree().get_nodes_in_group("robots")[0]
	var start := robot.global_position
	await get_tree().create_timer(1.5).timeout
	check(is_instance_valid(robot) and robot.global_position.distance_to(start) > 0.3, "robots move in the client's game")

	var robot_id := robot.get_instance_id()
	robot.take_damage(99999.0, robot.global_position, me)
	check(await wait_for(func() -> bool: return not is_instance_id_valid(robot_id), 4.0), "client shoots a robot: it's destroyed")
	check(await wait_for(func() -> bool: return not get_tree().get_nodes_in_group("scrap_piles").is_empty(), 4.0),
			"its scrap shows up for the client")
	var pile: Node3D = get_tree().get_nodes_in_group("scrap_piles")[0]
	me.global_position = pile.global_position
	check(await wait_for(func() -> bool: return me.scrap > 0, 6.0), "walking over scrap pays the client")

	me.scrap = 1000
	var gate: Gate = level.get_node("NavigationRegion3D/Section/Gate0")
	check(gate.interact(me) and gate.is_open, "client opens the first gate")

	check(await wait_for(func() -> bool: return me.life == Player.Life.DOWNED, 15.0), "client goes down from the host's hit")
	check(await wait_for(func() -> bool: return me.life == Player.Life.ALIVE, 10.0), "client gets revived by the host")

	check(await wait_for(func() -> bool: return rounds.phase == RoundManager.Phase.BREAK, 35.0), "client sees the round end")
	var button: NextRoundButton = get_tree().get_first_node_in_group("round_button")
	button.interact(me)
	check(await wait_for(func() -> bool: return rounds.phase == RoundManager.Phase.COUNTDOWN, 5.0),
			"client sees the countdown start")


func _finish() -> void:
	print("[%s] DONE %d/%d checks passed" % [role, checks - fails, checks])
	get_tree().quit(1 if fails else 0)
