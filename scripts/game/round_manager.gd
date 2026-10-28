class_name RoundManager
extends Node
## Runs Zombies-style rounds: spawns a wave of robots, waits for all of them to die,
## then holds a break until someone presses the next-round button. Scaling never stops.
##
## Break -> (button pressed) -> 10-second countdown -> next round.
## Stall too long in a break and the Warden comes down to press the button himself.
## The run ends when no player is up and nobody can hack back in (see check_team).
##
## Co-op: only the host's round manager runs rounds. It tells the other players' round
## managers what happened so their HUDs, buttons and respawns follow along.

enum Phase { BREAK, COUNTDOWN, ROUND, OVER }

signal run_over(round_number: int)
signal round_started(round_number: int)
signal round_ended(round_number: int)
signal remaining_changed(remaining: int)
signal countdown_started(seconds: float)
signal warden_summoned(warden: Warden)

@export var robot_scene: PackedScene ## Used when the spawn table is empty.
@export var spawn_table: Array[SpawnEntry] = [] ## Robot types and when they start appearing.
@export var warden_scene: PackedScene
@export var spawn_group := "robot_spawns" ## Marker3D nodes in this group are robot spawn points.
@export var warden_spawn_group := "warden_spawn" ## The Warden drops in at the first marker in this group.
@export var first_break_time := 4.0 ## Round 1 starts on its own after this long.
@export var countdown_time := 10.0 ## From button press to the next round.
@export var warden_delay := 45.0 ## Seconds of break before the Warden comes for the button.

@export_group("Wave size")
@export var first_round_robots := 6
@export var robots_added_per_round := 3
@export var max_alive := 20 ## The rest wait in a queue so the game stays readable.
@export var spawn_interval := 1.0
@export var min_spawn_distance := 8.0 ## Don't spawn right next to a player.

@export_group("Robot scaling")
@export var base_robot_health := 60.0
@export var health_growth_per_round := 1.12 ## Health multiplier each round, forever.
@export var base_robot_speed := 2.8
@export var speed_added_per_round := 0.25
@export var max_robot_speed := 7.0

@export_group("Rewards")
@export var round_end_heal_fraction := 0.25 ## Share of max health restored when a round ends.

var round_number := 0
var phase := Phase.BREAK
var countdown_left := 0.0
var break_time := 0.0 ## How long the current break has lasted.
var warden: Warden

var _first_break_left := 0.0
var _to_spawn := 0
var _alive := 0
var _spawn_left := 0.0
var _client_remaining := 0 ## What the host last said, on other players' games.


func _ready() -> void:
	add_to_group("round_manager")
	_first_break_left = first_break_time


func remaining() -> int:
	return _to_spawn + _alive if multiplayer.is_server() else _client_remaining


func robots_for_round(number: int) -> int:
	return first_round_robots + (number - 1) * robots_added_per_round


func robot_health_for_round(number: int) -> float:
	return base_robot_health * pow(health_growth_per_round, number - 1)


func robot_speed_for_round(number: int) -> float:
	return minf(base_robot_speed + (number - 1) * speed_added_per_round, max_robot_speed)


## A random robot type for this round, weighted by the spawn table.
func pick_robot_scene(number: int) -> PackedScene:
	var total := 0.0
	for entry in spawn_table:
		total += entry.weight_for_round(number)
	if total <= 0.0:
		return robot_scene
	var roll := randf() * total
	for entry in spawn_table:
		roll -= entry.weight_for_round(number)
		if roll <= 0.0:
			return entry.scene
	return spawn_table[-1].scene


## True while a break is waiting for someone to press the button.
func can_start_countdown() -> bool:
	return phase == Phase.BREAK and round_number > 0


## Called by the next-round button (by a player or the Warden). Returns false if it did nothing.
func start_countdown(_pressed_by: Node) -> bool:
	if not can_start_countdown():
		return false
	if not multiplayer.is_server():
		_net_request_countdown.rpc_id(1)
		return true
	phase = Phase.COUNTDOWN
	countdown_left = countdown_time
	countdown_started.emit(countdown_time)
	_to_clients(&"_net_countdown", [countdown_time])
	return true


## Players call this whenever they go down or get up. Ends the run when every player
## is down or out and none of them can still hack back in. Solo, that means a down
## with no hack charge, or a failed hack, ends the run.
func check_team() -> void:
	if phase == Phase.OVER or not multiplayer.is_server():
		return
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	for player: Player in players:
		if player.is_queued_for_deletion():
			continue # Left the session.
		if player.life == Player.Life.ALIVE or player.can_self_revive():
			return
	phase = Phase.OVER
	run_over.emit(round_number)
	_to_clients(&"_net_run_over", [round_number])


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		if phase == Phase.COUNTDOWN:
			countdown_left = maxf(countdown_left - delta, 0.0) # Just for the HUD.
		return
	match phase:
		Phase.BREAK:
			if round_number == 0:
				_first_break_left -= delta
				if _first_break_left <= 0.0:
					_start_next_round()
				return
			break_time += delta
			if break_time >= warden_delay and warden == null:
				_summon_warden()
		Phase.COUNTDOWN:
			countdown_left -= delta
			if countdown_left <= 0.0:
				_start_next_round()
		Phase.ROUND:
			if _to_spawn > 0 and _alive < max_alive:
				_spawn_left -= delta
				if _spawn_left <= 0.0:
					_spawn_left = spawn_interval
					_spawn_robot()


func _start_next_round() -> void:
	if warden:
		warden.leave()
		warden = null
	round_number += 1
	phase = Phase.ROUND
	_to_spawn = robots_for_round(round_number)
	_spawn_left = 0.0
	round_started.emit(round_number)
	remaining_changed.emit(remaining())
	_to_clients(&"_net_round_started", [round_number, remaining()])


func _summon_warden() -> void:
	var button := get_tree().get_first_node_in_group("round_button") as Node3D
	var spawn := get_tree().get_first_node_in_group(warden_spawn_group) as Node3D
	if warden_scene == null or button == null or spawn == null:
		push_warning("RoundManager: can't summon the Warden (needs warden_scene, a round_button and a warden_spawn)")
		break_time = -INF # Don't retry every frame.
		return
	warden = warden_scene.instantiate()
	warden.button = button
	warden.spawn_point = spawn
	_spawn_parent().add_child(warden, true)
	warden.drop_in()
	warden_summoned.emit(warden)


func _spawn_robot() -> void:
	var point := _pick_spawn_point()
	if point == null:
		push_warning("RoundManager: no spawn points in group '%s'" % spawn_group)
		return
	var robot: Robot = pick_robot_scene(round_number).instantiate()
	robot.configure(robot_health_for_round(round_number), robot_speed_for_round(round_number))
	robot.position = point.global_position # Set before adding so co-op copies spawn in the right place.
	_spawn_parent().add_child(robot, true)
	robot.died.connect(_on_robot_died)
	_to_spawn -= 1
	_alive += 1


## A random spawn point that isn't too close to any player, if one exists.
func _pick_spawn_point() -> Node3D:
	var points := get_tree().get_nodes_in_group(spawn_group)
	if points.is_empty():
		return null
	var players := get_tree().get_nodes_in_group("players")
	var safe: Array[Node3D] = []
	for point: Node3D in points:
		var far_enough := true
		for player: Node3D in players:
			if point.global_position.distance_to(player.global_position) < min_spawn_distance:
				far_enough = false
				break
		if far_enough:
			safe.append(point)
	return safe.pick_random() if not safe.is_empty() else points.pick_random()


func _on_robot_died(_robot: Robot) -> void:
	_alive -= 1
	remaining_changed.emit(remaining())
	_to_clients(&"_net_remaining", [remaining()])
	if _to_spawn == 0 and _alive == 0:
		_end_round()


func _end_round() -> void:
	phase = Phase.BREAK
	break_time = 0.0
	for player: Player in get_tree().get_nodes_in_group("players"):
		player.restore_health(player.health.max_health * round_end_heal_fraction)
	round_ended.emit(round_number)
	_to_clients(&"_net_round_ended", [round_number])


## Robots and the Warden go in the level's "spawn_root" node when it has one: in co-op,
## a MultiplayerSpawner there copies them to everyone's game.
func _spawn_parent() -> Node:
	var root := get_tree().get_first_node_in_group("spawn_root")
	return root if root else self


func _to_clients(method: StringName, args: Array = []) -> void:
	if Net.is_session():
		rpc.callv([method] + args)


@rpc("any_peer", "reliable")
func _net_request_countdown() -> void:
	start_countdown(null)


@rpc("authority", "reliable")
func _net_countdown(seconds: float) -> void:
	phase = Phase.COUNTDOWN
	countdown_left = seconds
	countdown_started.emit(seconds)


@rpc("authority", "reliable")
func _net_round_started(number: int, robots_left: int) -> void:
	round_number = number
	phase = Phase.ROUND
	_client_remaining = robots_left
	round_started.emit(number)
	remaining_changed.emit(robots_left)


@rpc("authority", "reliable")
func _net_remaining(robots_left: int) -> void:
	_client_remaining = robots_left
	remaining_changed.emit(robots_left)


@rpc("authority", "reliable")
func _net_round_ended(number: int) -> void:
	phase = Phase.BREAK
	round_ended.emit(number)


@rpc("authority", "reliable")
func _net_run_over(number: int) -> void:
	phase = Phase.OVER
	run_over.emit(number)
