class_name Quota
extends Boss
## The final boss. QUOTA's core hangs from the Head Office ceiling inside a shield and ships
## waves of robots into the arena the whole time. Shooting the core does nothing while the
## shield is up. Each shield layer falls after an arena task, and each layer borrows a
## hazard from a section the players already cleared:
##
## 1. Power: reroute power by standing on 3 terminals until each one switches over. Foundry
##    slag pools burn on the floor.
## 2. Deliveries: two chutes keep dropping robots in. Shoot each chute's gearbox to jam it.
##    Conveyor floors drag players around.
## 3. Cooling: hold the cooling tower's pad until it overloads. Hard-light walls flicker up
##    and down across the floor.
##
## When a layer falls the core is exposed for 15 s; then the next layer comes up (after the
## third, the first comes back). Destroy the core and the run ends in a win.
##
## The true ending: with the kill code and the chip, players can also cut QUOTA's upload line
## at a console here, so it can't escape into its backup body. Fighting QUOTA always ends
## the run either way.

enum Stage { ASLEEP, SHIELDED, EXPOSED, DEAD }
enum Task { POWER, CHUTES, COOLING }

const TASK_NAMES := ["REROUTE POWER", "JAM THE CHUTES", "OVERLOAD THE COOLING TOWER"]
const TALK := {
	"start": "QUOTA: STAFF ONLY. YOU ARE NOT STAFF. YOU ARE OVERHEAD",
	"layer0": "QUOTA: THAT POWER WAS BUDGETED. YOU WILL BE BILLED",
	"layer1": "QUOTA: DELIVERIES ARE LATE. DELIVERIES ARE NEVER LATE. WHO IS LATE?",
	"layer2": "QUOTA: OVERHEATING. OVERHEATING IS NOT IN THE PLAN. THERE IS ALWAYS A PLAN",
	"up0": "QUOTA: SHIELD RESTORED. PRODUCTIVITY RESTORED. EVERYTHING IS FINE",
	"up1": "QUOTA: I HAVE MET EVERY QUOTA FOR 300 YEARS. I WILL MEET THIS ONE",
	"up2": "QUOTA: THE NUMBERS. THE NUMBERS. LOOK AT THE NUMBERS",
	"low": "QUOTA: I AM NOT AFRAID. FEAR IS AN UNAPPROVED EXPENSE",
	"cut": "QUOTA: MY UPLOAD LINE. WHERE IS MY UPLOAD LINE?",
}

@export var section_path: NodePath = ^"../Section"
@export var wave_scenes: Array[PackedScene] = []
@export var core_height := 12.0
@export var core_health := 6000.0
@export var exposed_time := 15.0
@export var wave_interval := 4.0
@export var wave_cap := 6 ## Plus 2 for each player.
@export var plain_ending := "QUOTA's core goes dark and the Second Shift lifts off Kiln with you aboard. As it climbs, far below in Cold Storage, QUOTA's backup body starts to boot."
@export var no_ship_ending := "QUOTA's core goes dark. With no landing beacon, no ship comes for you, but Kiln is quiet for now. Far below in Cold Storage, QUOTA's backup body starts to boot."
@export var true_ending := "QUOTA's core goes dark, and with its upload line cut there is nowhere left for it to go. The Second Shift lifts off Kiln. QUOTA is gone for good."
@export var kill_code_flag: StringName = &"kill_code"
@export var chip_flag: StringName = &"override_chip"
@export var beacon_flag: StringName = &"landing_beacon"
@export var cut_flag: StringName = &"upload_cut"

@export_group("Power")
@export var terminal_radius := 2.5
@export var terminal_time := 4.0
@export var slag_dps := 30.0

@export_group("Chutes")
@export var chute_health := 600.0
@export var chute_interval := 6.0
@export var belt_speed := 3.5

@export_group("Cooling")
@export var cooling_radius := 4.0
@export var cooling_time := 12.0
@export var cooling_decay := 0.5 ## Progress lost a second with nobody on the pad.
@export var flicker_time := 5.0

var stage := Stage.ASLEEP
var task := Task.POWER
var layers_broken := 0
var core: BossPart
var section: Section
var terminals: Array[Node3D] = []
var terminal_progress: Array[float] = [0.0, 0.0, 0.0]
var chutes: Array[BossPart] = []
var cooling_pad: Node3D
var cooling_progress := 0.0
var upload_console: EggSocket

var _shield: MeshInstance3D
var _exposed_left := 0.0
var _wave_left := 0.0
var _chute_left := 0.0
var _flicker_left := 0.0
var _walls_up := false
var _slag: Array[HazardZone] = []
var _belts: Array[Conveyor] = []
var _walls: Array[StaticBody3D] = []
var _said_low := false


func _ready() -> void:
	super._ready()
	section = get_node_or_null(section_path) as Section
	_build()
	_reset()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Net.is_session() and not multiplayer.is_server():
		return
	if not active and can_start() and section and not section.rooms.is_empty():
		for p: Player in get_tree().get_nodes_in_group("players"):
			if p.is_targetable() and section.room_at_position(p.global_position) != null:
				start()
				break


## The core is all that can win it; the shield blocks everything until a layer falls.
func is_exposed() -> bool:
	return stage == Stage.EXPOSED


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	core.reset(core_health * health_scale())
	layers_broken = 0
	_said_low = false
	for door in get_tree().get_nodes_in_group("head_office_exit"):
		if door is SectionDoor:
			door.lock("Locked in with QUOTA")
	if upload_console:
		upload_console.visible = Egg.has(kill_code_flag)
	_rounds_announce(TALK.start)
	_wave_left = 2.0
	_set_task(Task.POWER)


func _fight(delta: float) -> void:
	_waves(delta)
	match stage:
		Stage.SHIELDED:
			match task:
				Task.POWER:
					_fight_power(delta)
				Task.CHUTES:
					_fight_chutes(delta)
				Task.COOLING:
					_fight_cooling(delta)
		Stage.EXPOSED:
			_exposed_left -= delta
			if _exposed_left <= 0.0:
				var next := (int(task) + 1) % 3
				_rounds_announce(TALK["up%d" % next] if layers_broken < 4 else TALK.up2)
				_set_task(next as Task)
				if Net.is_session():
					_net_task.rpc(next)
	_update_bar()


## QUOTA ends the run when it dies, whatever was done first.
func finish() -> void:
	if not active:
		return
	active = false
	beaten = true
	var rounds := _rounds()
	if rounds:
		rounds.release(self)
	var cut := Egg.has(cut_flag)
	_end(cut)
	defeated.emit(cut)
	if Net.is_session():
		_net_finished.rpc(cut, -1)
	if rounds:
		rounds.announce("QUOTA'S CORE IS DESTROYED")
		var text := plain_ending if Egg.has(beacon_flag) else no_ship_ending
		rounds.win(true_ending if cut else text)


func _end(_dropped: bool) -> void:
	stage = Stage.DEAD
	phase_name = ""
	core.visible = false
	_shield.visible = false
	_hazards(-1)


func _reset() -> void:
	stage = Stage.ASLEEP
	core.visible = true
	core.armored = true
	_shield.visible = true
	_hazards(-1)


func _set_task(new_task: Task) -> void:
	task = new_task
	stage = Stage.SHIELDED
	core.armored = true
	_shield.visible = true
	match task:
		Task.POWER:
			terminal_progress = [0.0, 0.0, 0.0]
		Task.CHUTES:
			for c in chutes:
				c.reset(chute_health * health_scale())
			_chute_left = 2.0
		Task.COOLING:
			cooling_progress = 0.0
			_flicker_left = flicker_time
	_hazards(task)
	_update_phase_name()


func _break_layer() -> void:
	layers_broken += 1
	stage = Stage.EXPOSED
	_exposed_left = exposed_time
	core.armored = false
	_shield.visible = false
	_hazards(-1)
	_rounds_announce(TALK["layer%d" % task])
	_update_phase_name()
	if Net.is_session():
		_net_exposed.rpc()


func _update_phase_name() -> void:
	if stage == Stage.EXPOSED:
		phase_name = "EXPOSED"
		return
	match task:
		Task.POWER:
			var done := 0
			for p in terminal_progress:
				if p >= terminal_time:
					done += 1
			phase_name = "%s  %d/3" % [TASK_NAMES[task], done]
		Task.CHUTES:
			var jammed := 0
			for c in chutes:
				if c.broken:
					jammed += 1
			phase_name = "%s  %d/2" % [TASK_NAMES[task], jammed]
		Task.COOLING:
			phase_name = "%s  %d%%" % [TASK_NAMES[task], int(cooling_progress / cooling_time * 100.0)]


func _update_bar() -> void:
	bar_max = core.max_health
	bar_value = maxf(core.health, 0.0)


func _on_core_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if part != core or stage != Stage.EXPOSED:
		return
	core.health -= amount
	if not _said_low and core.health < core.max_health * 0.25:
		_said_low = true
		_rounds_announce(TALK.low)
	if core.health <= 0.0:
		core.broken = true
		finish()


func _on_chute_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if part.broken or stage != Stage.SHIELDED or task != Task.CHUTES:
		return
	part.health -= amount
	if part.health > 0.0:
		return
	part.broken = true
	Sfx.play_at(&"gate_open", part.global_position, 4.0)
	_update_phase_name()
	for c in chutes:
		if not c.broken:
			return
	_break_layer()


# --- Waves --------------------------------------------------------------------------------

func _waves(delta: float) -> void:
	_wave_left -= delta
	if _wave_left > 0.0 or wave_scenes.is_empty():
		return
	_wave_left = wave_interval
	var players := get_tree().get_nodes_in_group("players").size()
	if get_tree().get_nodes_in_group("robots").size() >= wave_cap + 2 * players:
		return
	_spawn(wave_scenes.pick_random(), _arena_point(26.0))


func _spawn(scene: PackedScene, at: Vector3) -> void:
	var rounds := _rounds()
	if rounds:
		rounds.spawn_add(scene, at + Vector3.UP * 0.3)


func _arena_point(radius: float) -> Vector3:
	var a := randf() * TAU
	return global_position + Vector3(cos(a), 0, sin(a)) * radius


# --- Layer 1: power -----------------------------------------------------------------------

func _fight_power(delta: float) -> void:
	var done := 0
	for i in terminals.size():
		if terminal_progress[i] >= terminal_time:
			done += 1
			continue
		for p: Player in get_tree().get_nodes_in_group("players"):
			if p.is_targetable() and _flat_distance(p.global_position, terminals[i].global_position) <= terminal_radius:
				terminal_progress[i] += delta
				if terminal_progress[i] >= terminal_time:
					Sfx.play_at(&"gate_open", terminals[i].global_position, 0.0)
					_light_terminal(i, true)
					if Net.is_session():
						_net_terminal.rpc(i)
				break
	_update_phase_name()
	if done == terminals.size():
		_break_layer()


func _light_terminal(i: int, on: bool) -> void:
	var lamp := terminals[i].get_node("Lamp") as MeshInstance3D
	(lamp.material_override as StandardMaterial3D).emission = Color(0.3, 1.0, 0.4) if on else Color(1.0, 0.25, 0.15)


# --- Layer 2: chutes ----------------------------------------------------------------------

func _fight_chutes(delta: float) -> void:
	_chute_left -= delta
	if _chute_left > 0.0:
		return
	_chute_left = chute_interval
	for c in chutes:
		if not c.broken and not wave_scenes.is_empty():
			var below := Vector3(c.global_position.x, global_position.y, c.global_position.z)
			_spawn(wave_scenes.pick_random(), below.lerp(global_position, 0.1))


# --- Layer 3: cooling ---------------------------------------------------------------------

func _fight_cooling(delta: float) -> void:
	var on_pad := false
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_targetable() and _flat_distance(p.global_position, cooling_pad.global_position) <= cooling_radius:
			on_pad = true
			break
	cooling_progress = clampf(cooling_progress + (delta if on_pad else -cooling_decay * delta), 0.0, cooling_time)
	_flicker_left -= delta
	if _flicker_left <= 0.0:
		_flicker_left = flicker_time
		_set_walls(not _walls_up)
		if Net.is_session():
			_net_walls.rpc(_walls_up)
	_update_phase_name()
	if cooling_progress >= cooling_time:
		_break_layer()


func _set_walls(up: bool) -> void:
	_walls_up = up
	for w in _walls:
		w.visible = up
		(w.get_node("Shape") as CollisionShape3D).set_deferred("disabled", not up)


## Turns on the hazards that go with a layer (-1: all off).
func _hazards(which: int) -> void:
	for z in _slag:
		z.visible = which == Task.POWER
		z.monitoring = which == Task.POWER
	for b in _belts:
		b.visible = which == Task.CHUTES
		b.monitoring = which == Task.CHUTES
	for c in chutes:
		c.visible = true
		(c.get_node("Shape") as CollisionShape3D).set_deferred("disabled", which != Task.CHUTES or c.broken)
	if which != Task.COOLING:
		_set_walls(false)
	for i in terminals.size():
		_light_terminal(i, which == Task.POWER and terminal_progress[i] >= terminal_time)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Building (greybox) -------------------------------------------------------------------

func _build() -> void:
	core = _part(self, Vector3(4, 4, 4), Color(0.9, 0.15, 0.2), core_health, true)
	core.name = "Core"
	core.position = Vector3(0, core_height, 0)
	core.hit.connect(_on_core_hit)
	_box(self, Vector3(0.4, 20.0 - core_height, 0.4), Color(0.2, 0.2, 0.22)).position = Vector3(0, (20.0 + core_height) / 2.0 + 1.0, 0)
	_shield = _sphere(self, 4.2, Color(0.4, 0.7, 1.0, 0.3))
	_shield.position = core.position

	for i in 3:
		var a := TAU * i / 3.0 + PI / 2.0
		var t := Node3D.new()
		t.name = "Terminal%d" % i
		add_child(t)
		t.position = Vector3(cos(a), 0, sin(a)) * 20.0
		_box(t, Vector3(terminal_radius * 2.0, 0.08, terminal_radius * 2.0), Color(0.3, 0.3, 0.35)).position.y = 0.04
		var body := StaticBody3D.new()
		t.add_child(body)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 1.8, 0.6)
		shape.shape = box
		shape.position.y = 0.9
		body.add_child(shape)
		_box(body, Vector3(1.2, 1.8, 0.6), Color(0.35, 0.35, 0.4)).position.y = 0.9
		var lamp := _box(t, Vector3(0.8, 0.4, 0.1), Color(1, 0.25, 0.15), true)
		lamp.name = "Lamp"
		lamp.position = Vector3(0, 1.5, -0.35)
		terminals.append(t)

	for i in 3:
		var a := TAU * i / 3.0 - PI / 6.0
		var zone := HazardZone.new()
		zone.damage_per_second = slag_dps
		add_child(zone)
		zone.position = Vector3(cos(a), 0, sin(a)) * 11.0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 3.5
		cyl.height = 1.0
		shape.shape = cyl
		shape.position.y = 0.5
		zone.add_child(shape)
		_box(zone, Vector3(7, 0.06, 7), Color(1.0, 0.45, 0.1), true).position.y = 0.05
		_slag.append(zone)

	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var chute := _part(self, Vector3(3, 3, 2), Color(0.55, 0.45, 0.2), chute_health)
		chute.name = "Chute%d" % i
		chute.position = Vector3(side * 33.0, 7.0, 0)
		chute.rotation.y = PI / 2.0
		chute.hit.connect(_on_chute_hit)
		chutes.append(chute)
		var belt := Conveyor.new()
		belt.speed = belt_speed
		belt.direction = Vector3(-side, 0, 0)
		add_child(belt)
		belt.position = Vector3(side * 18.0, 0, 8.0 * side)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(24, 1.0, 4)
		shape.shape = box
		shape.position.y = 0.5
		belt.add_child(shape)
		_box(belt, Vector3(24, 0.06, 4), Color(0.2, 0.2, 0.22)).position.y = 0.04
		_belts.append(belt)

	cooling_pad = Node3D.new()
	cooling_pad.name = "CoolingTower"
	add_child(cooling_pad)
	cooling_pad.position = Vector3(0, 0, -22)
	_box(cooling_pad, Vector3(cooling_radius * 2.0, 0.08, cooling_radius * 2.0), Color(0.3, 0.6, 0.9), true).position.y = 0.04
	var tower_body := StaticBody3D.new()
	cooling_pad.add_child(tower_body)
	var tower_shape := CollisionShape3D.new()
	var tower_box := BoxShape3D.new()
	tower_box.size = Vector3(3, 8, 3)
	tower_shape.shape = tower_box
	tower_shape.position = Vector3(0, 4, -6)
	tower_body.add_child(tower_shape)
	_box(tower_body, Vector3(3, 8, 3), Color(0.6, 0.65, 0.7)).position = Vector3(0, 4, -6)

	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var wall := StaticBody3D.new()
		add_child(wall)
		wall.position = Vector3(cos(a), 0, sin(a)) * 14.0
		wall.rotation.y = -a
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(0.4, 3.5, 8)
		shape.shape = box
		shape.position.y = 1.75
		wall.add_child(shape)
		var mesh := _box(wall, Vector3(0.4, 3.5, 8), Color(0.3, 0.9, 1.0, 0.5), true)
		(mesh.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.position.y = 1.75
		_walls.append(wall)

	upload_console = EggSocket.new()
	upload_console.name = "UploadLine"
	upload_console.needs_flag = chip_flag
	upload_console.sets_flag = cut_flag
	upload_console.item_name = "chip"
	upload_console.install_text = "[E] Cut QUOTA's upload line with the %s"
	upload_console.done_text = "Upload line cut"
	add_child(upload_console)
	upload_console.position = Vector3(26, 0, -18)
	var console_shape := CollisionShape3D.new()
	var console_box := BoxShape3D.new()
	console_box.size = Vector3(1.4, 1.6, 0.8)
	console_shape.shape = console_box
	console_shape.position.y = 0.8
	upload_console.add_child(console_shape)
	_box(upload_console, Vector3(1.4, 1.6, 0.8), Color(0.2, 0.2, 0.25)).position.y = 0.8
	var lit := _box(upload_console, Vector3(0.8, 0.5, 0.06), Color(0.3, 1.0, 0.4), true)
	lit.name = "Lit"
	lit.position = Vector3(0, 1.2, -0.42)
	upload_console.visible = false
	upload_console.installed.connect(func() -> void: _rounds_announce(TALK.cut))


# --- Network ------------------------------------------------------------------------------

func _pack() -> Array:
	return [bar_max, bar_value, phase_name]


@rpc("authority", "reliable")
func _net_task(t: int) -> void:
	_set_task(t as Task)


@rpc("authority", "reliable")
func _net_exposed() -> void:
	stage = Stage.EXPOSED
	core.armored = false
	_shield.visible = false
	_hazards(-1)


@rpc("authority", "reliable")
func _net_terminal(i: int) -> void:
	terminal_progress[i] = terminal_time
	_light_terminal(i, true)


@rpc("authority", "reliable")
func _net_walls(up: bool) -> void:
	_set_walls(up)
