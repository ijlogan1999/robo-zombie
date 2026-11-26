class_name LineGiant
extends Boss
## The Line's boss: a giant robot the line builds in the atrium while players climb.
##
## The fight starts as soon as anyone walks into the Line, but the giant can't be hurt until
## it's finished. Every area players open builds more of it: legs, hips, torso, arms,
## shoulders, head. While it builds it grabs parts off the belts and bolts robots together
## (random robots from every section, and Amalgams), and once it has arms it sweeps them
## along the storeys' edges. When it's done it smashes open the way to the Proving Grounds,
## and players break its shoulders, then its chest core, then its head.
##
## Sits at the Line's origin; the giant stands in the atrium. Built in code (greybox).

enum Stage { ASLEEP, BUILDING, COMPLETE, DEAD }

const BUILD_STEPS := [
	"", "THE LINE BUILDS ITS LEGS", "THE LINE BOLTS ON ITS HIPS", "THE LINE LOWERS ITS TORSO IN",
	"IT GRABS A LEFT ARM", "IT GRABS A RIGHT ARM", "IT PLATES ITS SHOULDERS", "IT LIFTS ITS HEAD",
]

@export var section_path: NodePath = ^"../Section"
@export var built_scenes: Array[PackedScene] = []
@export var giant_at := Vector3(0, 0, -17)

@export_group("Building")
@export var build_interval := 9.0
@export var max_built := 8
@export var sweep_interval := 11.0
@export var sweep_warning := 1.3
@export var sweep_depth := 6.0
@export var sweep_damage := 35.0

@export_group("Complete")
@export var shoulder_health := 1200.0
@export var core_health := 2000.0
@export var head_health := 1500.0
@export var final_sweep_interval := 8.0
@export var slam_interval := 7.0
@export var slam_warning := 1.2
@export var slam_radius := 4.0
@export var slam_damage := 45.0

var stage := Stage.ASLEEP
var built := 0 ## Build steps done, 0..7.

var section: LineSection
var shoulders: Array[BossPart] = []
var core: BossPart
var head: BossPart

var _pieces: Array = [] ## [Node3D, step it appears at]
var _arms: Array[Node3D] = []
var _robots: Array = []
var _build_left := 0.0
var _sweep_left := 0.0
var _slam_left := 0.0


func _ready() -> void:
	super._ready()
	section = get_node_or_null(section_path) as LineSection
	_build_giant()
	_reset()


func max_steps() -> int:
	return section.area_count - 1 if section else 7


## Build steps earned: one per area opened past the first.
func earned_steps() -> int:
	if section == null:
		return 0
	var open := 0
	for room in section.rooms:
		if room.is_open:
			open += 1
	return clampi(open - 1, 0, max_steps())


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Net.is_session() and not multiplayer.is_server():
		return
	if not active and can_start() and _players_inside().size() > 0:
		start()


func _players_inside() -> Array[Player]:
	var inside: Array[Player] = []
	if section == null:
		return inside
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_targetable() and section.room_at_position(player.global_position) != null:
			inside.append(player)
	return inside


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	var scale := health_scale()
	for part in shoulders:
		part.reset(shoulder_health * scale)
	core.reset(core_health * scale)
	head.reset(head_health * scale)
	_build_left = 3.0
	_sweep_left = sweep_interval
	_slam_left = slam_interval
	_robots.clear()
	_set_stage(Stage.BUILDING)
	_set_built(0)


func _fight(delta: float) -> void:
	var earned := earned_steps()
	if stage == Stage.BUILDING and earned > built:
		_set_built(built + 1)
		_rounds_announce(BUILD_STEPS[built])
		if Net.is_session():
			_net_built.rpc(built)
		if built >= max_steps():
			_complete()
	var inside := _players_inside()
	_build_left -= delta
	if _build_left <= 0.0 and not inside.is_empty():
		_build_left = build_interval
		_bolt_together(inside.pick_random())
	_sweep_left -= delta
	if _sweep_left <= 0.0 and _has_arm() and not inside.is_empty():
		_sweep_left = final_sweep_interval if stage == Stage.COMPLETE else sweep_interval
		var k := section.area_storey(section.room_at_position(inside.pick_random().global_position).index)
		_sweep(k, false)
		if Net.is_session():
			_net_sweep.rpc(k, false)
		get_tree().create_timer(sweep_warning, false).timeout.connect(func() -> void:
			if active:
				_sweep(k, true)
				if Net.is_session():
					_net_sweep.rpc(k, true))
	if stage == Stage.COMPLETE:
		_slam_left -= delta
		if _slam_left <= 0.0:
			_slam_left = slam_interval
			var top: Array[Player] = []
			for p in inside:
				if section.area_storey(section.room_at_position(p.global_position).index) == LineSection.STOREYS - 1:
					top.append(p)
			if not top.is_empty():
				var at := top.pick_random().global_position as Vector3
				_slam_warn(at)
				if Net.is_session():
					_net_slam.rpc(at)
				get_tree().create_timer(slam_warning, false).timeout.connect(func() -> void:
					if active:
						_stomp(at, slam_radius, slam_damage))
	_update_bar()


func _end(_dropped: bool) -> void:
	for robot in _robots:
		if is_instance_valid(robot):
			robot.queue_free()
	_robots.clear()
	_set_stage(Stage.DEAD)


func _reset() -> void:
	_set_stage(Stage.ASLEEP)
	_set_built(0)
	for part in shoulders:
		part.reset()
	core.reset()
	head.reset()


func _set_stage(new_stage: Stage) -> void:
	stage = new_stage
	var hittable := stage == Stage.COMPLETE
	for part: BossPart in [shoulders[0], shoulders[1], core, head]:
		(part.get_node("Shape") as CollisionShape3D).disabled = not hittable or part.broken
	_update_armor()
	match stage:
		Stage.BUILDING:
			phase_name = "BUILDING"
		Stage.COMPLETE:
			phase_name = "COMPLETE"
		_:
			phase_name = ""


func _set_built(steps: int) -> void:
	built = steps
	for entry in _pieces:
		var node := entry[0] as Node3D
		node.visible = built >= entry[1] and stage != Stage.DEAD and not (node is BossPart and node.broken)
	for i in shoulders.size():
		if shoulders[i].broken:
			_arms[i].visible = false
	if stage == Stage.BUILDING:
		phase_name = "BUILDING %d/%d" % [built, max_steps()]


func _has_arm() -> bool:
	for i in _arms.size():
		if built >= 4 + i and not shoulders[i].broken:
			return true
	return false


## Done: it rips the door to the Proving Grounds open and can be hurt now.
func _complete() -> void:
	_set_stage(Stage.COMPLETE)
	_set_built(max_steps())
	_rounds_announce("THE GIANT IS COMPLETE. IT SMASHES THE WAY TO THE PROVING GROUNDS OPEN")
	_blow_door()
	if Net.is_session():
		_net_complete.rpc()


func _blow_door() -> void:
	for door in get_tree().get_nodes_in_group(&"line_blast_door"):
		if door is SectionDoor and door.locked:
			door.unlock()


func _update_bar() -> void:
	if stage == Stage.BUILDING:
		bar_max = max_steps()
		bar_value = built
		return
	bar_max = 0.0
	bar_value = 0.0
	for part: BossPart in [shoulders[0], shoulders[1], core, head]:
		bar_max += part.max_health
		bar_value += maxf(part.health, 0.0) if not part.broken else 0.0


func _update_armor() -> void:
	for part in shoulders:
		part.armored = stage != Stage.COMPLETE
	core.armored = stage != Stage.COMPLETE or not (shoulders[0].broken and shoulders[1].broken)
	head.armored = stage != Stage.COMPLETE or not core.broken


func _on_part_hit(part: BossPart, amount: float, _at: Vector3) -> void:
	if stage != Stage.COMPLETE or part.broken or part.armored:
		return
	part.health -= amount
	if part.health > 0.0:
		return
	_break_part([shoulders[0], shoulders[1], core, head].find(part))
	if Net.is_session():
		_net_break.rpc([shoulders[0], shoulders[1], core, head].find(part))
	if part == head:
		finish()


func _break_part(i: int) -> void:
	var part: BossPart = [shoulders[0], shoulders[1], core, head][i]
	part.broken = true
	part.health = 0.0
	part.visible = false
	(part.get_node("Shape") as CollisionShape3D).disabled = true
	if i < 2:
		_arms[i].visible = false
		_rounds_announce("AN ARM CRASHES DOWN")
	elif i == 2:
		_rounds_announce("ITS CORE IS OPEN. GO FOR THE HEAD")
	Sfx.play_at(&"gate_open", part.global_position, 6.0)
	_update_armor()


# --- Attacks ------------------------------------------------------------------------------

## Grabs parts off the belt and bolts a robot together near a player.
func _bolt_together(player: Player) -> void:
	var alive: Array = []
	for robot in _robots:
		if is_instance_valid(robot) and not robot.health.dead:
			alive.append(robot)
	_robots = alive
	if _robots.size() >= max_built or built_scenes.is_empty():
		return
	var rounds := _rounds()
	var room := section.room_at_position(player.global_position)
	if rounds == null or room == null:
		return
	var points := room.spawn_points()
	var at: Vector3 = (points.pick_random() as Node3D).global_position if not points.is_empty() else room.global_position
	_robots.append(rounds.spawn_add(built_scenes.pick_random(), at + Vector3.UP * 0.3))


## An arm sweeps along the atrium edge of storey k: a warning strip, then the hit.
func _sweep(k: int, real: bool) -> void:
	var y := section.global_position.y + k * section.storey_height
	var strip := _box(self, Vector3(section.hall_half_width * 2.0, 0.08 if not real else 2.5, sweep_depth),
		Color(1.0, 0.2, 0.1, 0.35) if not real else Color(0.35, 0.33, 0.3), not real)
	if not real:
		(strip.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	strip.global_position = section.to_global(Vector3(0, k * section.storey_height + (0.05 if not real else 1.25), sweep_depth / 2.0))
	get_tree().create_timer(sweep_warning if not real else 0.3, false).timeout.connect(strip.queue_free)
	if not real:
		return
	Sfx.play_at(&"robot_swing", strip.global_position, 6.0)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.is_targetable():
			continue
		var local := section.to_local(player.global_position)
		if absf(player.global_position.y - y) < 2.5 and local.z >= -0.5 and local.z <= sweep_depth and absf(local.x) <= section.hall_half_width:
			player.take_damage(sweep_damage, strip.global_position, self)


func _slam_warn(at: Vector3) -> void:
	var ring := _box(self, Vector3(slam_radius * 2.0, 0.08, slam_radius * 2.0), Color(1, 0.2, 0.1, 0.35), true)
	(ring.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.global_position = at + Vector3.UP * 0.05
	get_tree().create_timer(slam_warning, false).timeout.connect(ring.queue_free)


# --- Network ------------------------------------------------------------------------------

func _pack() -> Array:
	return [bar_max, bar_value, phase_name]


@rpc("authority", "reliable")
func _net_built(steps: int) -> void:
	_set_built(steps)


@rpc("authority", "reliable")
func _net_complete() -> void:
	_set_stage(Stage.COMPLETE)
	_set_built(max_steps())
	_blow_door()


@rpc("authority", "reliable")
func _net_break(i: int) -> void:
	_break_part(i)


@rpc("authority", "unreliable")
func _net_sweep(k: int, real: bool) -> void:
	_sweep(k, real)


@rpc("authority", "unreliable")
func _net_slam(at: Vector3) -> void:
	_slam_warn(at)


# --- Building -----------------------------------------------------------------------------

func _build_giant() -> void:
	var rig := Node3D.new()
	rig.name = "Giant"
	rig.position = giant_at
	add_child(rig)
	var steel := Color(0.42, 0.4, 0.38)
	var dark := Color(0.25, 0.24, 0.24)
	# The gantry that holds it while it's built (always there).
	for x in [-11.0, 11.0]:
		var post := _box(rig, Vector3(1.2, 32, 1.2), Color(0.8, 0.6, 0.15))
		post.position = Vector3(x, 16, -6)
	var beam := _box(rig, Vector3(23.2, 1.2, 1.2), Color(0.8, 0.6, 0.15))
	beam.position = Vector3(0, 32, -6)
	for x in [-4.0, 4.0]:
		_piece(rig, Vector3(3, 10, 3), Vector3(x, 5, 0), steel, 1)
	_piece(rig, Vector3(12, 3, 5), Vector3(0, 11.5, 0), dark, 2)
	_piece(rig, Vector3(12, 10, 6), Vector3(0, 18, 0), steel, 3)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var arm := _piece(rig, Vector3(3, 12, 3), Vector3(side * 8.0, 16, 0), dark, 4 + i)
		_arms.append(arm)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var pad := _piece(rig, Vector3(4, 2, 4), Vector3(side * 8.0, 23, 0), steel, 6)
		var joint := _part(rig, Vector3(2.4, 2.4, 1.0), Color(1.0, 0.7, 0.2), shoulder_health, true)
		joint.name = "Shoulder%d" % i
		joint.position = Vector3(side * 7.0, 22.5, 3.2)
		joint.hit.connect(_on_part_hit)
		_pieces.append([joint, 6])
		shoulders.append(joint)
		var _unused := pad
	core = _part(rig, Vector3(3.5, 3.5, 1.0), Color(0.3, 0.8, 1.0), core_health, true)
	core.name = "Core"
	core.position = Vector3(0, 18, 3.4)
	core.hit.connect(_on_part_hit)
	_pieces.append([core, 6])
	_piece(rig, Vector3(5, 4, 5), Vector3(0, 25.5, 0), steel, 7)
	head = _part(rig, Vector3(3.2, 1.0, 1.0), Color(1.0, 0.2, 0.15), head_health, true)
	head.name = "Head"
	head.position = Vector3(0, 26, 2.8)
	head.hit.connect(_on_part_hit)
	_pieces.append([head, 7])


func _piece(parent: Node3D, size: Vector3, at: Vector3, color: Color, step: int) -> MeshInstance3D:
	var mesh := _box(parent, size, color)
	mesh.position = at
	_pieces.append([mesh, step])
	return mesh
