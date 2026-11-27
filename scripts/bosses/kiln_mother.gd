class_name KilnMother
extends Boss
## The Crucible's boss, three phases in the middle of the dome.
##
## 1. The Ladle: a giant bucket of molten metal rides a rail under the roof and pours lava
##    lanes across the floor. Shoot its 3 pour valves and it tips its load into the big kiln.
## 2. The Kiln Mother: the kiln wakes and crawls after players. It can only be hurt through
##    its furnace door, which opens now and then, and whenever a feeder drone brings it
##    scrap to swallow (that heals it, so shoot the feeders down).
## 3. The Slag Golem: the kiln cracks and its molten core walks out. It can't be hurt while
##    hot. Shoot a coolant pipe while it's close to harden it, then crack it with gunfire.
##
## Sits at the dome's centre on the floor. Everything is built in code (greybox).

enum Stage { ASLEEP, LADLE, KILN, GOLEM, DEAD }

@export var feeder_scene: PackedScene
@export var scrap_scene: PackedScene

@export_group("Ladle")
@export var valve_health := 250.0
@export var ladle_height := 22.0
@export var rail_half_length := 40.0
@export var ladle_speed := 6.0
@export var pour_interval := 5.0
@export var pour_warning := 1.2
@export var lane_length := 24.0
@export var lane_width := 4.0
@export var lane_time := 7.0
@export var lane_damage := 30.0

@export_group("Kiln")
@export var kiln_health := 2000.0
@export var kiln_home := Vector3(0, 0, -10)
@export var kiln_speed := 1.8
@export var arena_radius := 11.0 ## The kiln and golem stay inside the landing zone.
@export var stomp_range := 5.5
@export var stomp_damage := 25.0
@export var stomp_windup := 0.9
@export var stomp_cooldown := 3.0
@export var fireball_damage := 14.0
@export var fireball_speed := 14.0
@export var fireball_interval := 4.5
@export var door_closed_time := 5.0
@export var door_open_time := 5.0
@export var feeder_interval := 10.0
@export var max_feeders := 2
@export var feed_heal := 0.03 ## Share of max health each delivery heals.

@export_group("Golem")
@export var golem_health := 2500.0
@export var golem_speed := 2.2
@export var golem_hard_speed := 1.0
@export var slam_range := 4.5
@export var slam_damage := 45.0
@export var slam_windup := 1.0
@export var slam_cooldown := 2.5
@export var pipe_health := 40.0
@export var pipe_radius := 12.5
@export var coolant_reach := 7.5
@export var hard_time := 8.0
@export var pipe_repair_time := 15.0

var stage := Stage.ASLEEP
var rail_angle := 0.0 ## Degrees. The rail turns 60 after each pass.
var ladle_t := -1.0 ## -1..1 along the rail.
var door_open := false
var golem_hard := false

var ladle: Node3D
var valves: Array[BossPart] = []
var kiln: CharacterBody3D
var kiln_core: BossPart
var golem: CharacterBody3D
var pipes: Array[BossPart] = []
var lever: StaticBody3D

var _rail: Node3D
var _ladle_dir := 1.0
var _pour_left := 0.0
var _kiln_hp := 0.0
var _kiln_max := 1.0
var _golem_hp := 0.0
var _golem_max := 1.0
var _door_left := 0.0
var _door_plate: CollisionShape3D
var _door_mesh: MeshInstance3D
var _feeder_left := 0.0
var _feeders: Array = [] ## FeederDrones; may hold freed ones until the next check.
var _attack_left := 0.0
var _windup_left := -1.0
var _fireball_left := 0.0
var _hard_left := 0.0
var _pipe_repair: Array[float] = []
var _golem_mat: StandardMaterial3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	super._ready()
	_build_ladle()
	_build_kiln()
	_build_golem()
	_build_pipes()
	_build_lever()
	_reset()


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	_set_stage(Stage.LADLE)
	var scale := health_scale()
	for valve in valves:
		valve.reset(valve_health * scale)
		valve.visible = true
	_kiln_max = kiln_health * scale
	_kiln_hp = _kiln_max
	_golem_max = golem_health * scale
	_golem_hp = _golem_max
	_pour_left = 2.0
	ladle_t = -1.0
	_ladle_dir = 1.0
	_update_bar()


func _fight(delta: float) -> void:
	match stage:
		Stage.LADLE:
			_fight_ladle(delta)
		Stage.KILN:
			_fight_kiln(delta)
		Stage.GOLEM:
			_fight_golem(delta)
	_update_bar()


func _end(_dropped: bool) -> void:
	_set_stage(Stage.DEAD)
	for drone in _feeders:
		if is_instance_valid(drone):
			drone.queue_free()
	_feeders.clear()


func _reset() -> void:
	_set_stage(Stage.ASLEEP)
	kiln.position = kiln_home
	kiln.rotation = Vector3.ZERO
	golem.position = kiln_home
	ladle_t = -1.0
	rail_angle = 0.0
	_place_ladle()
	for valve in valves:
		valve.reset(valve_health)
		valve.visible = true


func _set_stage(new_stage: Stage) -> void:
	stage = new_stage
	phase_name = ["", "THE LADLE", "AWAKE", "THE SLAG GOLEM", ""][stage]
	var kiln_awake := stage == Stage.KILN
	kiln.visible = stage != Stage.GOLEM
	(kiln.get_node("Shape") as CollisionShape3D).disabled = not kiln.visible
	golem.visible = stage == Stage.GOLEM
	(golem.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.GOLEM
	for pipe in pipes:
		pipe.visible = stage == Stage.GOLEM
		(pipe.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.GOLEM
	_set_door(false)
	kiln_core.armored = true
	ladle.visible = stage == Stage.LADLE or stage == Stage.ASLEEP
	lever.visible = stage == Stage.ASLEEP
	(lever.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.ASLEEP
	if stage == Stage.GOLEM:
		_set_hard(false)
	if kiln_awake:
		_door_left = door_closed_time
		_feeder_left = 2.0
		_fireball_left = fireball_interval
		_attack_left = 1.0


func _update_bar() -> void:
	match stage:
		Stage.LADLE:
			bar_max = 0.0
			bar_value = 0.0
			for valve in valves:
				bar_max += valve.max_health
				bar_value += maxf(valve.health, 0.0)
		Stage.KILN:
			bar_max = _kiln_max
			bar_value = _kiln_hp
		Stage.GOLEM:
			bar_max = _golem_max
			bar_value = _golem_hp


# --- Phase 1: the Ladle -------------------------------------------------------------------

func _fight_ladle(delta: float) -> void:
	ladle_t += _ladle_dir * ladle_speed * delta / rail_half_length
	if absf(ladle_t) >= 1.0:
		ladle_t = clampf(ladle_t, -1.0, 1.0)
		_ladle_dir = -_ladle_dir
		rail_angle = fmod(rail_angle + 60.0, 360.0)
	_place_ladle()
	_pour_left -= delta
	if _pour_left <= 0.0:
		_pour_left = pour_interval
		var at := Vector3(ladle.position.x, 0.0, ladle.position.z)
		_pour(at, deg_to_rad(rail_angle))
		if Net.is_session():
			_net_pour.rpc(at, deg_to_rad(rail_angle))


func _place_ladle() -> void:
	var dir := Vector3(cos(deg_to_rad(rail_angle)), 0.0, sin(deg_to_rad(rail_angle)))
	ladle.position = dir * ladle_t * rail_half_length + Vector3.UP * ladle_height
	ladle.rotation.y = -deg_to_rad(rail_angle)
	_rail.rotation.y = -deg_to_rad(rail_angle)


## A lane of lava along the rail under the ladle: a warning strip first, then the lava.
func _pour(at: Vector3, yaw: float) -> void:
	var lane := Node3D.new()
	lane.name = "LavaLane"
	add_child(lane)
	lane.position = at
	lane.rotation.y = -yaw
	var warn := _box(lane, Vector3(lane_length, 0.06, lane_width), Color(1, 0.3, 0.05, 0.35), true)
	warn.position.y = 0.05
	(warn.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	Sfx.play_at(&"bolt_fire", global_position + at + Vector3.UP * ladle_height, 2.0)
	var timer := get_tree().create_timer(pour_warning, false)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(lane):
			return
		warn.queue_free()
		var lava := _box(lane, Vector3(lane_length, 0.25, lane_width), Color(1.0, 0.45, 0.1), true)
		lava.position.y = 0.12
		var zone := HazardZone.new()
		zone.damage_per_second = lane_damage
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(lane_length, 1.5, lane_width)
		shape.shape = box
		shape.position.y = 0.75
		zone.add_child(shape)
		lane.add_child(zone)
		get_tree().create_timer(lane_time, false).timeout.connect(lane.queue_free))


func _on_valve_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.LADLE:
		return
	part.health -= amount
	if part.health > 0.0:
		return
	part.broken = true
	part.visible = false
	Sfx.broadcast_at(&"gate_open", part.global_position, 4.0)
	_sync_valves()
	for valve in valves:
		if not valve.broken:
			return
	_tip_ladle()


func _sync_valves() -> void:
	if Net.is_session() and multiplayer.is_server():
		var broken: Array[bool] = []
		for valve in valves:
			broken.append(valve.broken)
		_net_valves.rpc(broken)


## All valves gone: the ladle swings over the kiln and dumps everything in. The kiln wakes.
func _tip_ladle() -> void:
	_rounds_announce("THE LADLE TIPS INTO THE BIG KILN")
	_set_stage(Stage.KILN)
	if Net.is_session():
		_net_stage.rpc(Stage.KILN)


# --- Phase 2: the Kiln Mother -------------------------------------------------------------

func _fight_kiln(delta: float) -> void:
	var target := _nearest_player(kiln.global_position)
	_walk(kiln, target, kiln_speed, delta)

	_door_left -= delta
	if _door_left <= 0.0:
		_set_door(not door_open)
		_door_left = door_open_time if door_open else door_closed_time
		if Net.is_session():
			_net_door.rpc(door_open)

	_feeder_left -= delta
	var alive: Array = []
	for drone in _feeders:
		if is_instance_valid(drone) and not drone.dead:
			alive.append(drone)
	_feeders = alive
	if _feeder_left <= 0.0 and _feeders.size() < max_feeders and feeder_scene:
		_feeder_left = feeder_interval
		_spawn_feeder()

	_attack_left -= delta
	_fireball_left -= delta
	if target == null:
		return
	var distance := kiln.global_position.distance_to(target.global_position)
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left < 0.0:
			_stomp(kiln.global_position, stomp_range + 0.5, stomp_damage)
	elif distance <= stomp_range and _attack_left <= 0.0:
		_windup_left = stomp_windup
		_attack_left = stomp_cooldown
	elif _fireball_left <= 0.0:
		_fireball_left = fireball_interval
		var mouth := kiln.to_global(Vector3(0, 2.0, -3.2))
		var aim := (target.global_position + Vector3.UP - mouth).normalized() * fireball_speed
		_fireball(mouth, aim, true)
		if Net.is_session():
			_net_fireball.rpc(mouth, aim)


func _spawn_feeder() -> void:
	var a := randf() * TAU
	var drone: FeederDrone = feeder_scene.instantiate()
	drone.position = global_position + Vector3(cos(a) * 48.0, 14.0, sin(a) * 48.0)
	var root := get_tree().get_first_node_in_group("spawn_root")
	(root if root else self).add_child(drone, true)
	drone.target = kiln.get_node("Mouth")
	drone.arrived.connect(_on_feeder_arrived)
	_feeders.append(drone)


func _on_feeder_arrived(_drone: FeederDrone) -> void:
	if stage != Stage.KILN:
		return
	_kiln_hp = minf(_kiln_hp + _kiln_max * feed_heal, _kiln_max)
	_set_door(true)
	_door_left = door_open_time
	if Net.is_session():
		_net_door.rpc(true)


func _set_door(open: bool) -> void:
	door_open = open
	kiln_core.armored = not open
	_door_plate.disabled = open
	_door_mesh.rotation.x = -1.4 if open else 0.0
	_door_mesh.position = Vector3(0, 2.75, -2.35) if open else Vector3(0, 1.9, -2.15)


func _on_core_hit(_part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.KILN or not door_open:
		return
	_kiln_hp -= amount
	if _kiln_hp <= 0.0:
		_crack_kiln()


## The kiln's shell cracks and the molten core walks out.
func _crack_kiln() -> void:
	golem.position = kiln.position
	_rounds_announce("THE KILN CRACKS OPEN")
	for drone in _feeders:
		if is_instance_valid(drone):
			drone.queue_free()
	_feeders.clear()
	_set_stage(Stage.GOLEM)
	_attack_left = 2.0
	_windup_left = -1.0
	if Net.is_session():
		_net_stage.rpc(Stage.GOLEM)


# --- Phase 3: the Slag Golem --------------------------------------------------------------

func _fight_golem(delta: float) -> void:
	var target := _nearest_player(golem.global_position)
	_walk(golem, target, golem_hard_speed if golem_hard else golem_speed, delta)
	if golem_hard:
		_hard_left -= delta
		if _hard_left <= 0.0:
			_set_hard(false)
			if Net.is_session():
				_net_hard.rpc(false)
	for i in pipes.size():
		if pipes[i].broken:
			_pipe_repair[i] -= delta
			if _pipe_repair[i] <= 0.0:
				_set_pipe(i, false)
				if Net.is_session():
					_net_pipe.rpc(i, false)
	_attack_left -= delta
	if target == null:
		return
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left < 0.0:
			_stomp(golem.global_position, slam_range + 0.5, slam_damage)
	elif golem.global_position.distance_to(target.global_position) <= slam_range and _attack_left <= 0.0:
		_windup_left = slam_windup
		_attack_left = slam_cooldown


func _on_pipe_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.GOLEM or part.broken:
		return
	part.health -= amount
	if part.health > 0.0:
		return
	var i := pipes.find(part)
	_set_pipe(i, true)
	if Net.is_session():
		_net_pipe.rpc(i, true)
	if golem.global_position.distance_to(part.global_position) <= coolant_reach:
		_set_hard(true)
		if Net.is_session():
			_net_hard.rpc(true)


func _set_pipe(i: int, burst: bool) -> void:
	var pipe := pipes[i]
	if burst:
		pipe.broken = true
		_pipe_repair[i] = pipe_repair_time
		var cloud := _sphere(self, coolant_reach * 0.8, Color(0.8, 0.95, 1.0, 0.35))
		cloud.global_position = pipe.global_position
		get_tree().create_timer(1.5, false).timeout.connect(cloud.queue_free)
		Sfx.play_at(&"gate_open", pipe.global_position, 2.0)
	else:
		pipe.reset(pipe_health)
	(pipe.get_node("Mesh") as MeshInstance3D).scale = Vector3(1, 0.4, 1) if burst else Vector3.ONE


func _set_hard(hard: bool) -> void:
	golem_hard = hard
	_hard_left = hard_time
	_golem_mat.albedo_color = Color(0.25, 0.24, 0.24) if hard else Color(1.0, 0.45, 0.1)
	_golem_mat.emission_energy_multiplier = 0.0 if hard else 2.5


## Weapons hit the golem's body directly.
func _body_take_damage(amount: float) -> bool:
	if stage != Stage.GOLEM or not golem_hard:
		return false
	_golem_hp -= amount
	if _golem_hp <= 0.0:
		_golem_hp = 0.0
		finish()
		return true
	return false


# --- Shared -------------------------------------------------------------------------------

## Walks straight at the target, kept inside the landing arena.
func _walk(body: CharacterBody3D, target: Node3D, speed: float, delta: float) -> void:
	var move := Vector3.ZERO
	if target and _windup_left < 0.0:
		move = target.global_position - body.global_position
		move.y = 0.0
		if move.length() > 2.0:
			move = move.normalized() * speed
		else:
			move = Vector3.ZERO
		if target.global_position.distance_to(body.global_position) > 0.5:
			var flat := target.global_position - body.global_position
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-flat.x, -flat.z), 3.0 * delta)
	body.velocity.x = move.x
	body.velocity.z = move.z
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - _gravity * delta
	body.move_and_slide()
	var flat_pos := Vector2(body.position.x, body.position.z)
	if flat_pos.length() > arena_radius:
		flat_pos = flat_pos.normalized() * arena_radius
		body.position.x = flat_pos.x
		body.position.z = flat_pos.y


func _fireball(from: Vector3, aim: Vector3, real: bool) -> void:
	var bolt: BoltProjectile = preload("res://scenes/enemies/bolt_projectile.tscn").instantiate()
	bolt.harmless = not real
	bolt.scale = Vector3.ONE * 3.0
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.launch(aim, fireball_damage if real else 0.0, self)


func _pack() -> Array:
	return [bar_max, bar_value, phase_name, ladle_t, rail_angle, kiln.position, kiln.rotation.y,
		golem.position, golem.rotation.y]


func _unpack(state: Array) -> void:
	super._unpack(state)
	ladle_t = state[3]
	rail_angle = state[4]
	_place_ladle()
	kiln.position = state[5]
	kiln.rotation.y = state[6]
	golem.position = state[7]
	golem.rotation.y = state[8]


# --- Network events -----------------------------------------------------------------------

@rpc("authority", "reliable")
func _net_pour(at: Vector3, yaw: float) -> void:
	_pour(at, yaw)


@rpc("authority", "reliable")
func _net_valves(broken: Array[bool]) -> void:
	for i in valves.size():
		valves[i].broken = broken[i]
		valves[i].visible = not broken[i]


@rpc("authority", "reliable")
func _net_stage(new_stage: Stage) -> void:
	_set_stage(new_stage)


@rpc("authority", "reliable")
func _net_door(open: bool) -> void:
	_set_door(open)


@rpc("authority", "reliable")
func _net_pipe(i: int, burst: bool) -> void:
	_set_pipe(i, burst)


@rpc("authority", "reliable")
func _net_hard(hard: bool) -> void:
	_set_hard(hard)


@rpc("authority", "unreliable")
func _net_fireball(from: Vector3, aim: Vector3) -> void:
	_fireball(from, aim, false)


# --- Building -----------------------------------------------------------------------------

func _build_ladle() -> void:
	_rail = Node3D.new()
	_rail.name = "Rail"
	add_child(_rail)
	var beam := _box(_rail, Vector3(rail_half_length * 2.0 + 10.0, 0.6, 0.8), Color(0.2, 0.18, 0.17))
	beam.position.y = ladle_height + 4.0
	ladle = Node3D.new()
	ladle.name = "Ladle"
	add_child(ladle)
	var bucket := _box(ladle, Vector3(6, 4, 6), Color(0.3, 0.26, 0.24))
	bucket.position.y = 0.0
	var melt := _box(ladle, Vector3(5.2, 0.3, 5.2), Color(1.0, 0.5, 0.1), true)
	melt.position.y = 2.0
	var hanger := _box(ladle, Vector3(0.5, 4, 0.5), Color(0.2, 0.18, 0.17))
	hanger.position.y = 4.0
	for i in 3:
		var a := TAU * i / 3.0
		var valve := _part(ladle, Vector3(1.4, 1.4, 1.4), Color(0.9, 0.75, 0.2), valve_health)
		valve.name = "Valve%d" % i
		valve.position = Vector3(cos(a) * 3.4, -1.6, sin(a) * 3.4)
		valve.hit.connect(_on_valve_hit)
		valves.append(valve)


func _build_kiln() -> void:
	kiln = CharacterBody3D.new()
	kiln.name = "Kiln"
	kiln.add_to_group(&"boss_body")
	add_child(kiln)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 4.5, 4.2)
	shape.shape = box
	shape.position.y = 2.25
	kiln.add_child(shape)
	var shell := _box(kiln, Vector3(4.2, 4.5, 4.2), Color(0.4, 0.22, 0.16))
	shell.position.y = 2.25
	var chimney := _box(kiln, Vector3(1.2, 3.0, 1.2), Color(0.3, 0.18, 0.14))
	chimney.position = Vector3(0, 6.0, 0.8)
	for x in [-1.6, 1.6]:
		for z in [-1.6, 1.6]:
			var leg := _box(kiln, Vector3(0.5, 1.2, 0.5), Color(0.3, 0.27, 0.25))
			leg.position = Vector3(x, 0.3, z)
	kiln_core = _part(kiln, Vector3(1.8, 1.4, 0.3), Color(1.0, 0.55, 0.1), 1.0, true)
	kiln_core.name = "Core"
	kiln_core.position = Vector3(0, 1.9, -2.0)
	kiln_core.hit.connect(_on_core_hit)
	var plate := StaticBody3D.new()
	plate.name = "DoorPlate"
	kiln.add_child(plate)
	_door_plate = CollisionShape3D.new()
	var plate_box := BoxShape3D.new()
	plate_box.size = Vector3(2.2, 1.8, 0.2)
	_door_plate.shape = plate_box
	_door_plate.position = Vector3(0, 1.9, -2.25)
	plate.add_child(_door_plate)
	_door_mesh = _box(kiln, Vector3(2.2, 1.8, 0.2), Color(0.22, 0.2, 0.2))
	var mouth := Marker3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0, 1.9, -3.0)
	kiln.add_child(mouth)


func _build_golem() -> void:
	golem = CharacterBody3D.new()
	golem.name = "Golem"
	golem.add_to_group(&"boss_body")
	golem.set_script(preload("res://scripts/bosses/boss_body.gd"))
	golem.set("boss", self)
	add_child(golem)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.4
	capsule.height = 6.0
	shape.shape = capsule
	shape.position.y = 3.0
	golem.add_child(shape)
	var body := _box(golem, Vector3(2.8, 3.2, 2.0), Color(1.0, 0.45, 0.1), true)
	body.position.y = 3.4
	_golem_mat = body.material_override as StandardMaterial3D
	var head := _box(golem, Vector3(1.4, 1.2, 1.4), Color(1.0, 0.45, 0.1), true)
	head.position.y = 5.6
	head.material_override = _golem_mat
	for side in [-1.0, 1.0]:
		var arm := _box(golem, Vector3(0.9, 3.0, 0.9), Color(1.0, 0.45, 0.1), true)
		arm.position = Vector3(side * 1.9, 3.2, 0)
		arm.material_override = _golem_mat
		var leg := _box(golem, Vector3(1.0, 1.8, 1.0), Color(1.0, 0.45, 0.1), true)
		leg.position = Vector3(side * 0.8, 0.9, 0)
		leg.material_override = _golem_mat


func _build_pipes() -> void:
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var pipe := _part(self, Vector3(1.0, 3.0, 1.0), Color(0.55, 0.8, 0.95), pipe_health)
		pipe.name = "Pipe%d" % i
		pipe.position = Vector3(cos(a) * pipe_radius, 1.5, sin(a) * pipe_radius)
		pipe.hit.connect(_on_pipe_hit)
		pipes.append(pipe)
		_pipe_repair.append(0.0)


func _build_lever() -> void:
	lever = StaticBody3D.new()
	lever.name = "PourBell"
	lever.set_script(preload("res://scripts/bosses/boss_lever.gd"))
	lever.set("boss", self)
	lever.set("prompt", "[E] Ring the pour bell (starts the Kiln Mother fight)")
	add_child(lever)
	lever.position = kiln_home + Vector3(3.5, 0, 1.5)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.4, 0.8)
	shape.shape = box
	shape.position.y = 1.2
	lever.add_child(shape)
	var post := _box(lever, Vector3(0.3, 2.2, 0.3), Color(0.3, 0.27, 0.25))
	post.position.y = 1.1
	var bell := _box(lever, Vector3(0.8, 0.7, 0.8), Color(0.85, 0.65, 0.2))
	bell.position.y = 2.3


