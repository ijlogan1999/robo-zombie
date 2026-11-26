class_name BackupBody
extends Boss
## Cold Storage's boss (Easter egg half 2): QUOTA's spare body, frozen in the cryo chamber
## in the middle of the hall.
##
## It only wakes once the Thaw Coil and its board are installed in the chamber's sockets.
## Then the thaw switch starts the fight:
## 1. The thaw-out: QUOTA heats the chamber and sends waves of stock robots. The body can
##    be chipped through the ice (half damage). Shoot the coolant valves on the pipes to
##    vent coolant and slow the thaw, buying more time to chip it.
## 2. Free: the ice shatters and the body walks. A stripped-down preview of the Head Office
##    fight: an audit beam it aims down a line, a stomp up close, and stock it calls off
##    the shelves.
##
## Sits at the cryo chamber's centre. Everything is built in code (greybox).

enum Stage { ASLEEP, THAW, FREE, DEAD }

const COIL_FLAG := &"coil_installed"
const BOARD_FLAG := &"board_installed"
const PIPE_HEIGHT := 9.5

@export var wave_scenes: Array[PackedScene] = []

@export_group("Thaw")
@export var body_health := 4000.0
@export var thaw_time := 70.0
@export var vent_slow := 0.35 ## Thaw speed while any valve is venting.
@export var vent_time := 10.0
@export var valve_health := 60.0
@export var valve_radius := 7.0
@export var ice_damage_scale := 0.5
@export var wave_interval := 12.0
@export var wave_size := 3
@export var wave_radius := 13.0

@export_group("Free")
@export var walk_speed := 2.0
@export var arena_radius := 14.0
@export var stomp_range := 4.5
@export var stomp_damage := 40.0
@export var stomp_windup := 0.9
@export var stomp_cooldown := 3.0
@export var beam_interval := 6.0
@export var beam_warning := 1.0
@export var beam_length := 30.0
@export var beam_width := 1.2
@export var beam_damage := 30.0
@export var call_interval := 16.0
@export var call_count := 2

var stage := Stage.ASLEEP
var thaw := 0.0 ## 0..1
var venting := false

var tank: BossPart
var body: CharacterBody3D
var valves: Array[BossPart] = []
var lever: StaticBody3D

var _hp := 0.0
var _max := 1.0
var _vent_left: Array[float] = []
var _wave_left := 0.0
var _attack_left := 0.0
var _windup_left := -1.0
var _beam_left := 0.0
var _beam_aim := Vector3.ZERO
var _beam_charge := -1.0
var _call_left := 0.0
var _tank_mesh: MeshInstance3D


func _ready() -> void:
	super._ready()
	_build_tank()
	_build_body()
	_build_valves()
	_build_lever()
	_reset()


func can_start() -> bool:
	return super.can_start() and Egg.has(COIL_FLAG) and Egg.has(BOARD_FLAG)


func lever_prompt(prompt: String) -> String:
	if active or beaten or rematch_in >= 0:
		return ""
	if not Egg.has(COIL_FLAG) or not Egg.has(BOARD_FLAG):
		return "Thaw switch  -  no power (the coil and its board are missing)"
	return prompt


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	_max = body_health * health_scale()
	_hp = _max
	thaw = 0.0
	_wave_left = 3.0
	for i in valves.size():
		valves[i].reset(valve_health)
		_vent_left[i] = 0.0
	_set_stage(Stage.THAW)


func _fight(delta: float) -> void:
	match stage:
		Stage.THAW:
			_fight_thaw(delta)
		Stage.FREE:
			_fight_free(delta)
	bar_max = _max
	bar_value = _hp
	if stage == Stage.THAW:
		phase_name = "THAWING %d%%" % roundi(thaw * 100.0)


func _end(_dropped: bool) -> void:
	_set_stage(Stage.DEAD)


func _reset() -> void:
	thaw = 0.0
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	_set_stage(Stage.ASLEEP)


func _set_stage(new_stage: Stage) -> void:
	stage = new_stage
	phase_name = ["", "THAWING", "FREE", ""][stage]
	var frozen := stage == Stage.ASLEEP or stage == Stage.THAW
	tank.visible = frozen
	(tank.get_node("Shape") as CollisionShape3D).disabled = not frozen
	body.visible = stage != Stage.DEAD
	(body.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.FREE
	for valve in valves:
		valve.visible = stage == Stage.THAW
		(valve.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.THAW
	lever.visible = stage == Stage.ASLEEP
	(lever.get_node("Shape") as CollisionShape3D).disabled = stage != Stage.ASLEEP
	if stage == Stage.FREE:
		_attack_left = 2.0
		_windup_left = -1.0
		_beam_left = beam_interval
		_beam_charge = -1.0
		_call_left = call_interval / 2.0


# --- Phase 1: the thaw-out ----------------------------------------------------------------

func _fight_thaw(delta: float) -> void:
	venting = false
	for i in valves.size():
		if _vent_left[i] > 0.0:
			_vent_left[i] -= delta
			venting = true
			if _vent_left[i] <= 0.0:
				_set_valve(i, false)
				if Net.is_session():
					_net_valve.rpc(i, false)
	thaw += delta / thaw_time * (vent_slow if venting else 1.0)
	_wave_left -= delta
	if _wave_left <= 0.0:
		_wave_left = wave_interval
		_send_wave(wave_size, wave_radius)
	if thaw >= 1.0:
		thaw = 1.0
		_break_free()


func _send_wave(count: int, radius: float) -> void:
	var rounds := _rounds()
	if rounds == null or wave_scenes.is_empty():
		return
	for i in count:
		var a := randf() * TAU
		var at := global_position + Vector3(cos(a) * radius, 0.3, sin(a) * radius)
		rounds.spawn_add(wave_scenes.pick_random(), at)


func _on_tank_hit(_part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.THAW:
		return
	_hurt(amount * ice_damage_scale)


func _on_valve_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.THAW or part.broken:
		return
	part.health -= amount
	if part.health > 0.0:
		return
	var i := valves.find(part)
	_set_valve(i, true)
	if Net.is_session():
		_net_valve.rpc(i, true)


func _set_valve(i: int, vent: bool) -> void:
	var valve := valves[i]
	if vent:
		valve.broken = true
		_vent_left[i] = vent_time
		var cloud := _sphere(self, 2.5, Color(0.8, 0.95, 1.0, 0.35))
		cloud.global_position = valve.global_position
		get_tree().create_timer(vent_time, false).timeout.connect(cloud.queue_free)
		Sfx.play_at(&"gate_open", valve.global_position, 2.0)
	else:
		valve.reset(valve_health)
	(valve.get_node("Mesh") as MeshInstance3D).scale = Vector3(1, 0.4, 1) if vent else Vector3.ONE


func _break_free() -> void:
	_rounds_announce("THE ICE SHATTERS")
	_set_stage(Stage.FREE)
	if Net.is_session():
		_net_stage.rpc(Stage.FREE)


# --- Phase 2: free ------------------------------------------------------------------------

func _fight_free(delta: float) -> void:
	var target := _nearest_player(body.global_position)
	_walk(target, delta)
	_attack_left -= delta
	_beam_left -= delta
	_call_left -= delta
	if _call_left <= 0.0:
		_call_left = call_interval
		_send_wave(call_count, 6.0)
	if _beam_charge >= 0.0:
		_beam_charge -= delta
		if _beam_charge < 0.0:
			_fire_beam()
		return
	if target == null:
		return
	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left < 0.0:
			_stomp(body.global_position, stomp_range + 0.5, stomp_damage)
	elif body.global_position.distance_to(target.global_position) <= stomp_range and _attack_left <= 0.0:
		_windup_left = stomp_windup
		_attack_left = stomp_cooldown
	elif _beam_left <= 0.0:
		_beam_left = beam_interval
		_beam_charge = beam_warning
		var aim := target.global_position - body.global_position
		aim.y = 0.0
		_beam_aim = aim.normalized() if aim.length() > 0.1 else -body.global_basis.z
		_beam_flash(body.global_position, _beam_aim, false)
		if Net.is_session():
			_net_beam.rpc(body.global_position, _beam_aim, false)


func _walk(target: Node3D, delta: float) -> void:
	var move := Vector3.ZERO
	if target and _windup_left < 0.0 and _beam_charge < 0.0:
		move = target.global_position - body.global_position
		move.y = 0.0
		if move.length() > 1.0:
			body.rotation.y = lerp_angle(body.rotation.y, atan2(-move.x, -move.z), 3.0 * delta)
		move = move.normalized() * walk_speed if move.length() > 2.5 else Vector3.ZERO
	body.velocity.x = move.x
	body.velocity.z = move.z
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - 9.8 * delta
	body.move_and_slide()
	var flat := Vector2(body.position.x, body.position.z)
	if flat.length() > arena_radius:
		flat = flat.normalized() * arena_radius
		body.position.x = flat.x
		body.position.z = flat.y


## The audit beam: a red line on the floor first, then a burning line that hits anyone on it.
func _fire_beam() -> void:
	var from := body.global_position
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.is_targetable():
			continue
		var to := player.global_position - from
		to.y = 0.0
		var along := to.dot(_beam_aim)
		if along < 0.0 or along > beam_length:
			continue
		if (to - _beam_aim * along).length() <= beam_width:
			player.take_damage(beam_damage, from, self)
	_beam_flash(from, _beam_aim, true)
	if Net.is_session():
		_net_beam.rpc(from, _beam_aim, true)


func _beam_flash(from: Vector3, aim: Vector3, real: bool) -> void:
	var beam := _box(self, Vector3(beam_width * (2.0 if real else 0.6), 0.08 if not real else 1.6, beam_length),
		Color(1.0, 0.15, 0.1, 0.4) if not real else Color(1.0, 0.3, 0.2), true)
	if not real:
		(beam.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.global_position = from + aim * beam_length / 2.0 + Vector3.UP * (0.05 if not real else 1.2)
	beam.global_rotation.y = atan2(aim.x, aim.z)
	get_tree().create_timer(beam_warning if not real else 0.25, false).timeout.connect(beam.queue_free)
	if real:
		Sfx.play_at(&"bolt_fire", from + Vector3.UP * 3.0, 4.0)


## Weapons hit the body directly once it's free.
func _body_take_damage(amount: float) -> bool:
	if stage != Stage.FREE:
		return false
	return _hurt(amount)


func _hurt(amount: float) -> bool:
	if not active:
		return false
	_hp -= amount
	if _hp <= 0.0:
		_hp = 0.0
		finish()
		return true
	return false


# --- Network ------------------------------------------------------------------------------

func _pack() -> Array:
	return [bar_max, bar_value, phase_name, thaw, body.position, body.rotation.y]


func _unpack(state: Array) -> void:
	super._unpack(state)
	thaw = state[3]
	body.position = state[4]
	body.rotation.y = state[5]


@rpc("authority", "reliable")
func _net_stage(new_stage: Stage) -> void:
	_set_stage(new_stage)


@rpc("authority", "reliable")
func _net_valve(i: int, vent: bool) -> void:
	_set_valve(i, vent)


@rpc("authority", "unreliable")
func _net_beam(from: Vector3, aim: Vector3, real: bool) -> void:
	_beam_flash(from, aim, real)


# --- Building -----------------------------------------------------------------------------

func _build_tank() -> void:
	tank = BossPart.new()
	tank.name = "Tank"
	add_child(tank)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.0
	cyl.height = 7.0
	shape.shape = cyl
	shape.position.y = 3.5
	tank.add_child(shape)
	_tank_mesh = MeshInstance3D.new()
	_tank_mesh.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 3.0
	mesh.bottom_radius = 3.0
	mesh.height = 7.0
	_tank_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	_tank_mesh.material_override = mat
	_tank_mesh.position.y = 3.5
	tank.add_child(_tank_mesh)
	tank.hit.connect(_on_tank_hit)
	var base := _box(self, Vector3(7.5, 0.6, 7.5), Color(0.25, 0.28, 0.32))
	base.position.y = 0.3
	var cap := _box(self, Vector3(7.5, 0.8, 7.5), Color(0.25, 0.28, 0.32))
	cap.position.y = 7.4


func _build_body() -> void:
	body = CharacterBody3D.new()
	body.name = "Body"
	body.add_to_group(&"boss_body")
	body.set_script(preload("res://scripts/bosses/boss_body.gd"))
	body.set("boss", self)
	add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.2
	capsule.height = 5.0
	shape.shape = capsule
	shape.position.y = 2.6
	body.add_child(shape)
	var dark := Color(0.16, 0.16, 0.2)
	var torso := _box(body, Vector3(2.2, 2.2, 1.3), dark)
	torso.position.y = 3.2
	var head := _box(body, Vector3(1.2, 1.0, 1.1), dark)
	head.position.y = 4.9
	var eye := _box(body, Vector3(0.8, 0.18, 0.1), Color(1.0, 0.2, 0.15), true)
	eye.position = Vector3(0, 5.0, -0.58)
	for side in [-1.0, 1.0]:
		var arm := _box(body, Vector3(0.6, 2.4, 0.6), dark)
		arm.position = Vector3(side * 1.5, 3.0, 0)
		var leg := _box(body, Vector3(0.7, 2.0, 0.7), dark)
		leg.position = Vector3(side * 0.6, 1.0, 0)
	var badge := _box(body, Vector3(0.5, 0.3, 0.05), Color(0.9, 0.8, 0.3), true)
	badge.position = Vector3(0.5, 3.8, -0.68)


func _build_valves() -> void:
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var pipe := _box(self, Vector3(0.6, PIPE_HEIGHT, 0.6), Color(0.55, 0.8, 0.95))
		pipe.position = Vector3(cos(a) * valve_radius, PIPE_HEIGHT / 2.0, sin(a) * valve_radius)
		var valve := _part(self, Vector3(1.2, 1.2, 1.2), Color(0.3, 0.6, 0.9), valve_health)
		valve.name = "Valve%d" % i
		valve.position = Vector3(cos(a) * valve_radius, 1.6, sin(a) * valve_radius)
		valve.hit.connect(_on_valve_hit)
		valves.append(valve)
		_vent_left.append(0.0)


func _build_lever() -> void:
	lever = StaticBody3D.new()
	lever.name = "ThawSwitch"
	lever.set_script(preload("res://scripts/bosses/boss_lever.gd"))
	lever.set("boss", self)
	lever.set("prompt", "[E] Throw the thaw switch (wakes QUOTA's backup body)")
	add_child(lever)
	lever.position = Vector3(0, 0, 5.0)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.6, 0.6)
	shape.shape = box
	shape.position.y = 0.8
	lever.add_child(shape)
	var panel := _box(lever, Vector3(1.2, 1.4, 0.4), Color(0.3, 0.32, 0.36))
	panel.position.y = 0.7
	var handle := _box(lever, Vector3(0.15, 0.6, 0.15), Color(0.9, 0.3, 0.2), true)
	handle.position = Vector3(0, 1.6, 0)
