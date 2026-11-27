class_name ProvingSection
extends GraphSection
## The Proving Grounds: one long, open-air test course where finished robots are tried
## out. No boss and no unique robot, just a lot of the existing ones.
##
## The first time players walk in, the gauntlet starts: rounds pause and robots pour in
## around the players. Checkpoint gates replace scrap gates: hold the pad in front of each
## one until it opens. Past the last one the gauntlet is over, rounds start again and the
## course stays open. The trial yards in the middle shuffle each run.

signal gauntlet_finished

enum Gauntlet { WAITING, RUNNING, PAUSED, DONE }

@export var yard_count := 4 ## Trial yards between the entry and the exit.
@export var yard_width := 30.0
@export var yard_length := 36.0
@export var fence_height := 6.0
@export var hold_time := 20.0
@export var hold_step := 4.0 ## Each checkpoint further in holds this much longer.
@export var gauntlet_scenes: Array[PackedScene] = []
@export var spawn_interval := 1.3
@export var max_alive := 12
@export var max_alive_per_player := 3
@export var leave_grace := 10.0 ## Seconds with nobody inside before the gauntlet pauses.
@export var checkpoint_scene: PackedScene
@export var pad_material: Material

var gauntlet := Gauntlet.WAITING
var robots: Array = []

var _spawn_left := 0.0
var _away := 0.0


func _build() -> void:
	var count := yard_count + 2
	var links: Array = []
	for i in count - 1:
		links.append([i, i + 1])
	_set_links(count, links)
	var fill := _pick_fill()
	for i in count:
		var scene: PackedScene = start_room if i == 0 else (end_room if i == count - 1 else fill.pop_front())
		_place_yard(scene, i)
	var total := yard_length * count
	var floor_box := CSGBox3D.new()
	floor_box.use_collision = true
	floor_box.material = floor_material
	floor_box.size = Vector3(yard_width, 1.0, total)
	floor_box.position = Vector3(0, -0.5, -total / 2.0 + yard_length / 2.0)
	add_child(floor_box)
	for s: float in [-1.0, 1.0]:
		_fence(Vector3(s * (yard_width / 2.0 + wall_thickness / 2.0), 0, floor_box.position.z), Vector3(wall_thickness, fence_height, total))
	for z: float in [yard_length / 2.0, yard_length / 2.0 - total]:
		_fence(Vector3(0, 0, z), Vector3(yard_width + 2.0, fence_height, wall_thickness))
	for i in count - 1:
		_build_checkpoint(i)
	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Proving Grounds layout (seed %d): %s" % [used_seed, ", ".join(names)])


func yard_center(i: int) -> Vector3:
	return to_global(Vector3(0, 0, -yard_length * i))


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	if absf(local.x) > yard_width / 2.0 + 1.0 or local.y < -3.0 or local.y > 20.0:
		return null
	var i := roundi(-local.z / yard_length)
	return rooms[i] if i >= 0 and i < rooms.size() else null


func _pick_fill() -> Array[PackedScene]:
	var picked: Array[PackedScene] = required_rooms.duplicate()
	while picked.size() < yard_count and not optional_rooms.is_empty():
		var deck := optional_rooms.duplicate()
		_shuffle(deck)
		for scene: PackedScene in deck:
			if picked.size() >= yard_count:
				break
			picked.append(scene)
	_shuffle(picked)
	return picked


func _place_yard(scene: PackedScene, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	var floor_node := room.get_node_or_null("Floor")
	if floor_node:
		room.remove_child(floor_node)
		floor_node.free()
	room.position = Vector3(0, 0, -yard_length * index)
	add_child(room)
	rooms.append(room)


func _fence(base: Vector3, size: Vector3) -> void:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = wall_material
	box.size = size
	box.position = base + Vector3.UP * size.y / 2.0
	add_child(box)


## A fence across the course with a checkpoint gate in the middle and its hold pad in front.
func _build_checkpoint(i: int) -> void:
	var z := -yard_length * i - yard_length / 2.0
	var gap := door_width / 2.0 + 0.5
	var piece := yard_width / 2.0 - gap
	for s: float in [-1.0, 1.0]:
		_fence(Vector3(s * (gap + piece / 2.0), 0, z), Vector3(piece, fence_height, wall_thickness))
	var saved := gate_scene
	gate_scene = checkpoint_scene if checkpoint_scene else gate_scene
	var gate := _add_gate(i, i + 1, Vector3(0, 0, z), 0.0)
	gate_scene = saved
	var checkpoint := gate as CheckpointGate
	if checkpoint:
		checkpoint.hold_time = hold_time + hold_step * i
		checkpoint.pad_at = to_global(Vector3(0, 0, z + checkpoint.pad_radius + 2.0))
		var pad := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = checkpoint.pad_radius
		disc.bottom_radius = checkpoint.pad_radius
		disc.height = 0.05
		pad.mesh = disc
		if pad_material:
			pad.material_override = pad_material
		pad.position = Vector3(0, 0.03, z + checkpoint.pad_radius + 2.0)
		add_child(pad)


# --- The gauntlet -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if Net.is_session() and not multiplayer.is_server():
		return
	if gauntlet == Gauntlet.DONE:
		return
	var inside := _players_inside()
	match gauntlet:
		Gauntlet.WAITING, Gauntlet.PAUSED:
			if not inside.is_empty():
				_run()
		Gauntlet.RUNNING:
			if inside.is_empty():
				_away += delta
				if _away >= leave_grace:
					_pause()
				return
			_away = 0.0
			_spawn_left -= delta
			if _spawn_left <= 0.0:
				_spawn_left = spawn_interval
				_spawn_near(inside)


func _players_inside() -> Array[Player]:
	var found: Array[Player] = []
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_targetable() and room_at_position(p.global_position) != null:
			found.append(p)
	return found


func _run() -> void:
	var was := gauntlet
	gauntlet = Gauntlet.RUNNING
	_away = 0.0
	_spawn_left = 2.0
	_arm_next()
	var rounds := _rounds()
	if rounds:
		rounds.hold(self)
		rounds.announce("THE GAUNTLET BEGINS. HOLD EVERY CHECKPOINT" if was == Gauntlet.WAITING else "THE GAUNTLET STARTS AGAIN")


func _pause() -> void:
	gauntlet = Gauntlet.PAUSED
	var rounds := _rounds()
	if rounds:
		rounds.release(self)


func _finish() -> void:
	gauntlet = Gauntlet.DONE
	var rounds := _rounds()
	if rounds:
		rounds.release(self)
		rounds.announce("GAUNTLET CLEARED. THE COURSE STAYS OPEN")
	gauntlet_finished.emit()


## Only the first closed checkpoint counts a hold.
func _arm_next() -> void:
	var next_found := false
	for gate in gates:
		var checkpoint := gate as CheckpointGate
		if checkpoint == null:
			continue
		checkpoint.armed = not checkpoint.is_open and not next_found
		if checkpoint.armed:
			next_found = true


func _on_gate_opened(gate: Gate) -> void:
	super._on_gate_opened(gate)
	if Net.is_session() and not multiplayer.is_server():
		return
	_arm_next()
	var all_open := true
	for g in gates:
		all_open = all_open and g.is_open
	if all_open and gauntlet != Gauntlet.DONE:
		_finish()


## Robots pour in near the players: in their yard or the next one along.
func _spawn_near(inside: Array[Player]) -> void:
	var alive: Array = []
	for r in robots:
		if is_instance_valid(r) and not r.health.dead:
			alive.append(r)
	robots = alive
	if robots.size() >= max_alive + max_alive_per_player * inside.size() or gauntlet_scenes.is_empty():
		return
	var rounds := _rounds()
	if rounds == null:
		return
	var room := room_at_position(inside.pick_random().global_position)
	var choices: Array[Room] = [room]
	if room.index + 1 < rooms.size() and rooms[room.index + 1].is_open:
		choices.append(rooms[room.index + 1])
	var points: Array[Node] = (choices.pick_random() as Room).spawn_points()
	if points.is_empty():
		return
	var at: Vector3 = (points.pick_random() as Node3D).global_position
	robots.append(rounds.spawn_add(gauntlet_scenes.pick_random(), at + Vector3.UP * 0.3))


func _rounds() -> RoundManager:
	return get_tree().get_first_node_in_group("round_manager") as RoundManager
