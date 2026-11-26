class_name ControlTower
extends Boss
## The Shipping Bay's boss: the air traffic control tower in the middle of the yard comes
## to life when players walk into its bay.
##
## 1. Radar: its dish sweeps a searchlight across the yard. Wherever the light finds a
##    player, it calls in trouble: a ship strafes the spot, a crane drops a container on
##    it, or a drop pod of security bots lands next to it. Shoot out the dish to blind it.
## 2. Antennas: blind, it still calls ships down on players now and then. Destroy the
##    three antennas so it can't call anything.
## 3. The cab: the control cab breaks off the tower and fights in the air like a giant
##    drone: it circles, fires bolt volleys and dives at players.
##
## Sits at the tower bay's centre. Built in code (greybox).

enum Stage { ASLEEP, RADAR, ANTENNAS, CAB, DEAD }

@export var section_path: NodePath = ^"../Section"
@export var pod_scene: PackedScene
@export var tower_height := 24.0

@export_group("Radar")
@export var dish_health := 900.0
@export var sweep_speed := 22.0 ## Degrees a second.
@export var spot_radius := 5.0
@export var spot_min := 8.0
@export var spot_max := 46.0
@export var call_cooldown := 5.0

@export_group("Trouble")
@export var strafe_blasts := 6
@export var strafe_spacing := 3.0
@export var strafe_damage := 30.0
@export var drop_damage := 50.0
@export var drop_warning := 1.5
@export var pod_count := 2

@export_group("Antennas")
@export var antenna_health := 350.0
@export var blind_call_interval := 7.0

@export_group("Cab")
@export var cab_health := 2200.0
@export var orbit_radius := 18.0
@export var orbit_height := 14.0
@export var orbit_speed := 0.35 ## Radians a second.
@export var volley_interval := 2.5
@export var volley_damage := 12.0
@export var dive_interval := 10.0
@export var dive_radius := 5.0
@export var dive_damage := 40.0

var stage := Stage.ASLEEP
var spot := Vector3.ZERO ## Searchlight spot, local to the tower.

var section: HallSection
var dish: BossPart
var antennas: Array[BossPart] = []
var cab: BossPart

var _sweep_angle := 0.0
var _call_left := 0.0
var _orbit := 0.0
var _volley_left := 0.0
var _dive_left := 0.0
var _dive_from := Vector3.ZERO
var _dive_to := Vector3.ZERO
var _dive_t := -1.0
var _light: MeshInstance3D
var _cab_home := Vector3.ZERO


func _ready() -> void:
	super._ready()
	section = get_node_or_null(section_path) as HallSection
	_build()
	_reset()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Net.is_session() and not multiplayer.is_server():
		return
	if not active and can_start() and section and not section.rooms.is_empty():
		for p: Player in get_tree().get_nodes_in_group("players"):
			if p.is_targetable() and section.room_at_position(p.global_position) == section.rooms[1]:
				start()
				break


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	var scale := health_scale()
	dish.reset(dish_health * scale)
	for a in antennas:
		a.reset(antenna_health * scale)
	cab.reset(cab_health * scale)
	_call_left = 3.0
	_set_stage(Stage.RADAR)


func _fight(delta: float) -> void:
	match stage:
		Stage.RADAR:
			_fight_radar(delta)
		Stage.ANTENNAS:
			_fight_antennas(delta)
		Stage.CAB:
			_fight_cab(delta)
	_update_bar()


func _end(_dropped: bool) -> void:
	_set_stage(Stage.DEAD)


func _reset() -> void:
	cab.position = _cab_home
	cab.rotation = Vector3.ZERO
	_dive_t = -1.0
	dish.reset()
	for a in antennas:
		a.reset()
	cab.reset()
	_set_stage(Stage.ASLEEP)


func _set_stage(new_stage: Stage) -> void:
	stage = new_stage
	phase_name = ["", "RADAR", "ANTENNAS", "THE CAB", ""][stage]
	dish.visible = stage <= Stage.RADAR
	_enable(dish, stage == Stage.RADAR)
	for a in antennas:
		a.visible = stage <= Stage.ANTENNAS and not a.broken
		_enable(a, stage == Stage.ANTENNAS and not a.broken)
	cab.visible = stage != Stage.DEAD
	_enable(cab, stage == Stage.CAB)
	_light.visible = stage == Stage.RADAR
	if stage == Stage.CAB:
		_volley_left = volley_interval
		_dive_left = dive_interval
		_dive_t = -1.0


func _enable(part: BossPart, on: bool) -> void:
	(part.get_node("Shape") as CollisionShape3D).disabled = not on


func _update_bar() -> void:
	match stage:
		Stage.RADAR:
			bar_max = dish.max_health
			bar_value = maxf(dish.health, 0.0)
		Stage.ANTENNAS:
			bar_max = 0.0
			bar_value = 0.0
			for a in antennas:
				bar_max += a.max_health
				bar_value += 0.0 if a.broken else maxf(a.health, 0.0)
		Stage.CAB:
			bar_max = cab.max_health
			bar_value = maxf(cab.health, 0.0)


func _on_part_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if part.broken:
		return
	if (part == dish and stage != Stage.RADAR) or (antennas.has(part) and stage != Stage.ANTENNAS) or (part == cab and stage != Stage.CAB):
		return
	part.health -= amount
	if part.health > 0.0:
		return
	part.broken = true
	if part == dish:
		_advance(Stage.ANTENNAS, "THE RADAR IS DOWN. IT'S BLIND")
	elif part == cab:
		finish()
	else:
		part.visible = false
		_enable(part, false)
		Sfx.play_at(&"gate_open", part.global_position, 4.0)
		var i := antennas.find(part)
		if Net.is_session():
			_net_antenna.rpc(i)
		for a in antennas:
			if not a.broken:
				return
		_advance(Stage.CAB, "THE CONTROL CAB BREAKS LOOSE")


func _advance(new_stage: Stage, text: String) -> void:
	_rounds_announce(text)
	_set_stage(new_stage)
	if Net.is_session():
		_net_stage.rpc(new_stage)


# --- Phase 1: radar -----------------------------------------------------------------------

func _fight_radar(delta: float) -> void:
	_sweep_angle += deg_to_rad(sweep_speed) * delta
	var r := lerpf(spot_min, spot_max, 0.5 + 0.5 * sin(_sweep_angle * 0.37))
	spot = Vector3(cos(_sweep_angle) * r, 0.0, sin(_sweep_angle) * r)
	_show_spot()
	_call_left -= delta
	if _call_left > 0.0:
		return
	var at := to_global(spot)
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_targetable() and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() <= spot_radius:
			_call_left = call_cooldown
			_call_trouble(p, randi() % 3)
			return


func _show_spot() -> void:
	_light.position = Vector3(spot.x, 0.05, spot.z)


## Something nasty lands on the player: 0 ship strafe, 1 crane drop, 2 drop pod.
func _call_trouble(player: Player, kind: int) -> void:
	var at := player.global_position
	match kind:
		0:
			var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			_strafe(at, dir)
		1:
			_crane_drop(at)
		_:
			_drop_pod(at)


func _strafe(at: Vector3, dir: Vector3) -> void:
	_rounds_announce("A SHIP STRAFES THE YARD")
	for i in strafe_blasts:
		var point := at + dir * strafe_spacing * (i - strafe_blasts / 2.0)
		var delay := 1.0 + i * 0.18
		_warn_circle(point, 2.0, delay)
		get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if active:
				_stomp(point, 2.5, strafe_damage))
		if Net.is_session():
			_net_warn.rpc(point, 2.0, delay)


func _crane_drop(at: Vector3) -> void:
	_warn_circle(at, 3.0, drop_warning)
	if Net.is_session():
		_net_warn.rpc(at, 3.0, drop_warning)
	get_tree().create_timer(drop_warning, false).timeout.connect(func() -> void:
		if not active:
			return
		_stomp(at, 3.0, drop_damage)
		_drop_crate(at)
		if Net.is_session():
			_net_crate.rpc(at))


## The dropped container stays a while as cover (or a wall in the way).
func _drop_crate(at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 2.6, 2.6)
	shape.shape = box
	shape.position.y = 1.3
	body.add_child(shape)
	var mesh := _box(body, Vector3(6, 2.6, 2.6), Color(0.7, 0.25, 0.15))
	mesh.position.y = 1.3
	get_tree().current_scene.add_child(body)
	body.global_position = Vector3(at.x, global_position.y, at.z)
	body.rotation.y = randf() * PI
	get_tree().create_timer(10.0, false).timeout.connect(body.queue_free)


func _drop_pod(at: Vector3) -> void:
	_rounds_announce("A DROP POD COMES DOWN")
	var rounds := _rounds()
	var land := at + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	_warn_circle(land, 2.5, 1.0)
	if Net.is_session():
		_net_warn.rpc(land, 2.5, 1.0)
	get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
		if not active or rounds == null or pod_scene == null:
			return
		_stomp(land, 2.5, 20.0)
		for i in pod_count:
			rounds.spawn_add(pod_scene, land + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-1.5, 1.5))))


func _warn_circle(at: Vector3, radius: float, time: float) -> void:
	var ring := _box(self, Vector3(radius * 2.0, 0.08, radius * 2.0), Color(1, 0.2, 0.1, 0.35), true)
	(ring.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.global_position = Vector3(at.x, global_position.y + 0.06, at.z)
	get_tree().create_timer(time, false).timeout.connect(ring.queue_free)


# --- Phase 2: antennas --------------------------------------------------------------------

func _fight_antennas(delta: float) -> void:
	_call_left -= delta
	if _call_left > 0.0:
		return
	_call_left = blind_call_interval
	var target := _random_player()
	if target:
		_strafe(target.global_position, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized())


func _random_player() -> Player:
	var choices: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_targetable() and section and section.room_at_position(p.global_position) != null:
			choices.append(p)
	return choices.pick_random() if not choices.is_empty() else null


# --- Phase 3: the cab ---------------------------------------------------------------------

func _fight_cab(delta: float) -> void:
	if _dive_t >= 0.0:
		var before := _dive_t
		_dive_t += delta / 1.6
		var t := minf(_dive_t, 1.0)
		var k := t * 2.0 if t < 0.5 else (1.0 - t) * 2.0
		var flat := _dive_from.lerp(_dive_to, k)
		cab.global_position = Vector3(flat.x, global_position.y + orbit_height * (1.0 - 0.8 * sin(t * PI)), flat.z)
		if before < 0.5 and t >= 0.5:
			_stomp(Vector3(_dive_to.x, global_position.y, _dive_to.z), dive_radius, dive_damage)
		if _dive_t >= 1.0:
			_dive_t = -1.0
		return
	_orbit += orbit_speed * delta
	cab.position = Vector3(cos(_orbit) * orbit_radius, orbit_height, sin(_orbit) * orbit_radius)
	cab.rotation.y = -_orbit
	_volley_left -= delta
	_dive_left -= delta
	var target := _nearest_player(cab.global_position)
	if target == null:
		return
	if _volley_left <= 0.0:
		_volley_left = volley_interval
		for i in 3:
			var aim := (target.global_position + Vector3.UP + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)) - cab.global_position).normalized() * 18.0
			_bolt(cab.global_position + aim.normalized() * 4.5, aim, true)
			if Net.is_session():
				_net_bolt.rpc(cab.global_position + aim.normalized() * 4.5, aim)
	if _dive_left <= 0.0:
		_dive_left = dive_interval
		_dive_from = cab.global_position
		_dive_to = Vector3(target.global_position.x, cab.global_position.y, target.global_position.z)
		_dive_t = 0.0
		_warn_circle(target.global_position, dive_radius, 0.8)
		if Net.is_session():
			_net_warn.rpc(target.global_position, dive_radius, 0.8)


func _bolt(from: Vector3, aim: Vector3, real: bool) -> void:
	var bolt: BoltProjectile = preload("res://scenes/enemies/bolt_projectile.tscn").instantiate()
	bolt.harmless = not real
	bolt.scale = Vector3.ONE * 2.0
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.launch(aim, volley_damage if real else 0.0, self)


# --- Network ------------------------------------------------------------------------------

func _pack() -> Array:
	return [bar_max, bar_value, phase_name, spot, cab.position, cab.rotation.y]


func _unpack(state: Array) -> void:
	super._unpack(state)
	spot = state[3]
	_show_spot()
	cab.position = state[4]
	cab.rotation.y = state[5]


@rpc("authority", "reliable")
func _net_stage(new_stage: Stage) -> void:
	_set_stage(new_stage)


@rpc("authority", "reliable")
func _net_antenna(i: int) -> void:
	antennas[i].broken = true
	antennas[i].visible = false
	_enable(antennas[i], false)


@rpc("authority", "unreliable")
func _net_warn(at: Vector3, radius: float, time: float) -> void:
	_warn_circle(at, radius, time)


@rpc("authority", "reliable")
func _net_crate(at: Vector3) -> void:
	_drop_crate(at)


@rpc("authority", "unreliable")
func _net_bolt(from: Vector3, aim: Vector3) -> void:
	_bolt(from, aim, false)


# --- Building -----------------------------------------------------------------------------

func _build() -> void:
	var concrete := Color(0.6, 0.6, 0.58)
	var shaft := StaticBody3D.new()
	shaft.name = "Shaft"
	add_child(shaft)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, tower_height, 5)
	shape.shape = box
	shape.position.y = tower_height / 2.0
	shaft.add_child(shape)
	var mesh := _box(shaft, Vector3(5, tower_height, 5), concrete)
	mesh.position.y = tower_height / 2.0
	var base := _box(self, Vector3(9, 1.2, 9), Color(0.45, 0.45, 0.44))
	base.position.y = 0.6
	var base_body := StaticBody3D.new()
	base_body.name = "Base"
	add_child(base_body)
	var base_shape := CollisionShape3D.new()
	var base_box := BoxShape3D.new()
	base_box.size = Vector3(9, 1.2, 9)
	base_shape.shape = base_box
	base_shape.position.y = 0.6
	base_body.add_child(base_shape)
	_cab_home = Vector3(0, tower_height + 2.0, 0)
	cab = _part(self, Vector3(9, 4, 9), Color(0.3, 0.35, 0.42), cab_health)
	cab.name = "Cab"
	cab.position = _cab_home
	cab.hit.connect(_on_part_hit)
	var glass := _box(cab, Vector3(9.2, 1.4, 9.2), Color(0.5, 0.85, 1.0), true)
	glass.position.y = 0.6
	dish = _part(self, Vector3(4, 0.6, 4), Color(0.85, 0.85, 0.9), dish_health)
	dish.name = "Dish"
	dish.position = Vector3(0, tower_height + 5.5, 0)
	dish.rotation.x = 0.4
	dish.hit.connect(_on_part_hit)
	for i in 3:
		var a := TAU * i / 3.0
		var antenna := _part(self, Vector3(0.6, 4.0, 0.6), Color(0.9, 0.3, 0.2), antenna_health, true)
		antenna.name = "Antenna%d" % i
		antenna.position = Vector3(cos(a) * 3.6, tower_height + 6.0, sin(a) * 3.6)
		antenna.hit.connect(_on_part_hit)
		antennas.append(antenna)
	_light = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = spot_radius
	disc.bottom_radius = spot_radius
	disc.height = 0.1
	_light.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0.8, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light.material_override = mat
	add_child(_light)
