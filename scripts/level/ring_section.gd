class_name RingSection
extends Section
## The Heap's layout: a two-floor ring of rooms around a central pit.
##
## Ground floor: the spawn yard, then three rooms each way round the ring to a shared
## stairwell on the far side. Upper floor: from the top of the stairwell two rooms each
## way loop back round to the crane control room above the spawn yard.
## The ring's shape is fixed. Each run shuffles which hand-made room goes in which slot.
##
## Rooms are authored as 32 m squares like everywhere else. Here the section lays its own
## curved floors, so each room's "Floor" node is removed and its props sit on the ring.

const GROUND := 0
const UPPER := 1
const BOTH := 2

## Slot order is fixed, so every co-op player names rooms and gates the same way.
## angle and span are in degrees (0 = +X, 90 = +Z, toward the spawn yard).
## r_out < 0 means the ring's outer radius.
const SLOTS := [
	{"key": "spawn", "angle": 90.0, "span": 45.0, "floor": GROUND},
	{"key": "west_1", "angle": 135.0, "span": 45.0, "floor": GROUND},
	{"key": "west_2", "angle": 180.0, "span": 45.0, "floor": GROUND},
	{"key": "west_3", "angle": 225.0, "span": 45.0, "floor": GROUND},
	{"key": "stairwell", "angle": 270.0, "span": 45.0, "floor": BOTH},
	{"key": "east_3", "angle": 315.0, "span": 45.0, "floor": GROUND},
	{"key": "east_2", "angle": 0.0, "span": 45.0, "floor": GROUND},
	{"key": "east_1", "angle": 45.0, "span": 45.0, "floor": GROUND},
	{"key": "upper_west_1", "angle": 213.75, "span": 67.5, "floor": UPPER},
	{"key": "upper_west_2", "angle": 146.25, "span": 67.5, "floor": UPPER},
	{"key": "crane_control", "angle": 90.0, "span": 45.0, "floor": UPPER, "r_out": 48.0},
	{"key": "upper_east_2", "angle": 33.75, "span": 67.5, "floor": UPPER},
	{"key": "upper_east_1", "angle": 326.25, "span": 67.5, "floor": UPPER},
]

## Doorways between slots, as [slot, slot, floor the door is on].
const LINKS := [
	[0, 1, GROUND], [1, 2, GROUND], [2, 3, GROUND], [3, 4, GROUND],
	[0, 7, GROUND], [7, 6, GROUND], [6, 5, GROUND], [5, 4, GROUND],
	[4, 8, UPPER], [8, 9, UPPER], [9, 10, UPPER],
	[4, 12, UPPER], [12, 11, UPPER], [11, 10, UPPER],
]

@export var stairwell_room: PackedScene
@export var crane_control_room: PackedScene

@export_group("Ring")
@export var inner_radius := 30.0 ## Inner wall, facing the pit.
@export var outer_radius := 66.0
@export var upper_floor_height := 8.0
@export var slab_thickness := 0.5
@export var upper_wall_height := 6.0
@export var railing_height := 1.1 ## Upper floor edge over the pit. An invisible wall stops falls.
@export var pit_radius := 18.0
@export var balcony_height := 4.0 ## The boss fight balcony circling the pit.
@export var floor_material: Material
@export var arc_segments_per_45 := 4 ## Straight wall pieces used to draw 45 degrees of curve.

@export_group("Stairwell")
@export var ramp_length := 20.0
@export var ramp_width := 4.5
@export var ramp_radius := 40.0 ## Distance of the ramp from the ring's centre.

var slot_keys: Array[String] = [] ## slot_keys[i] names the slot rooms[i] sits in.
var depth: Array[int] = [] ## Doors from the spawn yard to each room.

var _neighbours: Array = [] # index -> Array[int]
var _gate_rooms := {} # Gate -> [room index, room index]


func _build() -> void:
	_compute_depths()
	var fill := _pick_ring_rooms()
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var scene: PackedScene
		match slot.key:
			"spawn": scene = start_room
			"stairwell": scene = stairwell_room
			"crane_control": scene = crane_control_room
			_: scene = fill.pop_front()
		_place_ring_room(scene, i)

	_build_floors()
	_build_walls()
	_build_stairwell()
	_build_pit()

	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Heap layout (seed %d): %s" % [used_seed, ", ".join(names)])


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	var r := Vector2(local.x, local.z).length()
	if r < inner_radius - 1.0 or r > outer_radius + 1.0:
		return null
	var angle := rad_to_deg(atan2(local.z, local.x))
	var on_upper := local.y > upper_floor_height - 1.0
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		if slot.floor != BOTH and (slot.floor == UPPER) != on_upper:
			continue
		if absf(angle_difference(deg_to_rad(angle), deg_to_rad(slot.angle))) > deg_to_rad(slot.span / 2.0):
			continue
		if r > _slot_outer(i) + 1.0:
			continue
		return rooms[i]
	return null


## World position of a point on the ring. angle in degrees.
func ring_point(angle: float, radius: float, height := 0.0) -> Vector3:
	var a := deg_to_rad(angle)
	return to_global(Vector3(cos(a) * radius, height, sin(a) * radius))


func slot_center(index: int) -> Vector3:
	var slot: Dictionary = SLOTS[index]
	var height := upper_floor_height if slot.floor == UPPER else 0.0
	return ring_point(slot.angle, (inner_radius + _slot_outer(index)) / 2.0, height)


func _slot_outer(index: int) -> float:
	return SLOTS[index].get("r_out", outer_radius)


# --- Layout -------------------------------------------------------------------------------

func _compute_depths() -> void:
	_neighbours.clear()
	for i in SLOTS.size():
		_neighbours.append([])
	for link in LINKS:
		_neighbours[link[0]].append(link[1])
		_neighbours[link[1]].append(link[0])
	depth.clear()
	depth.resize(SLOTS.size())
	depth.fill(-1)
	depth[0] = 0
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for next: int in _neighbours[at]:
			if depth[next] < 0:
				depth[next] = depth[at] + 1
				queue.append(next)


## Rooms for the shuffled slots: the required ones, then optional ones. If there are more
## slots than rooms, the optional rooms are dealt again.
func _pick_ring_rooms() -> Array[PackedScene]:
	var count := 0
	for slot in SLOTS:
		if not slot.key in ["spawn", "stairwell", "crane_control"]:
			count += 1
	var picked: Array[PackedScene] = required_rooms.duplicate()
	while picked.size() < count and not optional_rooms.is_empty():
		var deck := optional_rooms.duplicate()
		_shuffle(deck)
		for scene: PackedScene in deck:
			if picked.size() >= count:
				break
			picked.append(scene)
	_shuffle(picked)
	return picked


func _place_ring_room(scene: PackedScene, index: int) -> void:
	var slot: Dictionary = SLOTS[index]
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	var floor_node := room.get_node_or_null("Floor")
	if floor_node:
		room.remove_child(floor_node)
		floor_node.free()
	var height := upper_floor_height if slot.floor == UPPER else 0.0
	var a := deg_to_rad(slot.angle)
	var r := (inner_radius + _slot_outer(index)) / 2.0
	room.position = Vector3(cos(a) * r, height, sin(a) * r)
	# Local +Z points out from the pit, so a room authored facing +Z looks the same in any slot.
	var turn := 0.0
	if room.can_rotate:
		turn = _rng.randi_range(0, 3) * PI / 2.0
	room.rotation.y = PI / 2.0 - a + turn
	add_child(room)
	rooms.append(room)
	slot_keys.append(slot.key)


# --- Geometry -----------------------------------------------------------------------------

func _build_floors() -> void:
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var a0: float = slot.angle - slot.span / 2.0
		var a1: float = slot.angle + slot.span / 2.0
		if slot.floor != UPPER:
			_add_sector(a0, a1, inner_radius, _slot_outer(i), -slab_thickness, slab_thickness)
		if slot.floor == UPPER:
			_add_sector(a0, a1, inner_radius, _slot_outer(i), upper_floor_height - slab_thickness, slab_thickness)


## A flat slab shaped like a slice of a ring. Returns it so holes can be cut into it.
func _add_sector(a0: float, a1: float, r0: float, r1: float, bottom: float, thickness: float) -> CSGPolygon3D:
	var points := PackedVector2Array()
	var steps := maxi(2, ceili(absf(a1 - a0) / 45.0 * arc_segments_per_45))
	for s in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(s) / steps))
		points.append(Vector2(cos(a), sin(a)) * r0)
	for s in range(steps, -1, -1):
		var a := deg_to_rad(lerpf(a0, a1, float(s) / steps))
		points.append(Vector2(cos(a), sin(a)) * r1)
	var poly := CSGPolygon3D.new()
	poly.polygon = points
	poly.depth = thickness
	poly.use_collision = true
	poly.material = floor_material
	# The polygon is drawn in X/Z: turning it about X makes its depth point straight up.
	poly.rotation.x = PI / 2.0
	poly.position.y = bottom
	add_child(poly)
	return poly


func _build_walls() -> void:
	var ground_height := upper_floor_height - slab_thickness
	for i in SLOTS.size():
		var slot: Dictionary = SLOTS[i]
		var a0: float = slot.angle - slot.span / 2.0
		var a1: float = slot.angle + slot.span / 2.0
		if slot.floor != UPPER:
			_add_arc_wall(a0, a1, outer_radius, 0.0, ground_height, true)
			_add_arc_wall(a0, a1, inner_radius, 0.0, ground_height, true)
		if slot.floor != GROUND:
			var base := upper_floor_height
			_add_arc_wall(a0, a1, _slot_outer(i), base, upper_wall_height, true)
			_add_arc_wall(a0, a1, inner_radius, base, railing_height, true)
			_add_arc_wall(a0, a1, inner_radius, base + railing_height, upper_wall_height - railing_height, false)

	# Radial walls sit on each slot's edges. Every edge is shared by two slots on a floor.
	var done := {}
	for floor_level in [GROUND, UPPER]:
		for i in SLOTS.size():
			if not _on_floor(i, floor_level):
				continue
			for edge in [-1, 1]:
				var slot: Dictionary = SLOTS[i]
				var angle: float = fposmod(slot.angle + edge * slot.span / 2.0, 360.0)
				var key := "%d:%d" % [floor_level, roundi(angle * 100.0)]
				if done.has(key):
					continue
				done[key] = true
				var other := _slot_across(i, angle, floor_level)
				_build_radial(i, other, angle, floor_level)


func _on_floor(index: int, floor_level: int) -> bool:
	var f: int = SLOTS[index].floor
	return f == BOTH or f == floor_level


func _slot_across(index: int, edge_angle: float, floor_level: int) -> int:
	for j in SLOTS.size():
		if j == index or not _on_floor(j, floor_level):
			continue
		var slot: Dictionary = SLOTS[j]
		for edge in [-1, 1]:
			var angle: float = fposmod(slot.angle + edge * slot.span / 2.0, 360.0)
			if absf(angle_difference(deg_to_rad(angle), deg_to_rad(edge_angle))) < 0.001:
				return j
	return -1


func _linked(a: int, b: int, floor_level: int) -> bool:
	for link in LINKS:
		if link[2] == floor_level and ((link[0] == a and link[1] == b) or (link[0] == b and link[1] == a)):
			return true
	return false


func _build_radial(a: int, b: int, angle: float, floor_level: int) -> void:
	var base := upper_floor_height if floor_level == UPPER else 0.0
	var height := upper_wall_height if floor_level == UPPER else upper_floor_height - slab_thickness
	var r_end := _slot_outer(a) if b < 0 else maxf(_slot_outer(a), _slot_outer(b))
	if b < 0 or not _linked(a, b, floor_level):
		_add_radial_box(angle, inner_radius, r_end, base, height)
		return
	# A doorway in the middle of the part both rooms share, with a gate in it.
	var shared_out := minf(_slot_outer(a), _slot_outer(b))
	var door_r := (inner_radius + shared_out) / 2.0
	_add_radial_box(angle, inner_radius, door_r - door_width / 2.0, base, height)
	_add_radial_box(angle, door_r + door_width / 2.0, r_end, base, height)
	_add_radial_box(angle, door_r - door_width / 2.0, door_r + door_width / 2.0, base + door_height, height - door_height)

	var deeper := b if depth[b] > depth[a] else a
	var shallower := a if deeper == b else b
	var gate := gate_scene.instantiate() as Gate
	gate.name = "Gate%d" % gates.size()
	gate.cost = first_gate_cost + gate_cost_step * maxi(depth[deeper] - 1, 0)
	gate.room_name = rooms[deeper].display_name
	var rad := deg_to_rad(angle)
	gate.position = Vector3(cos(rad) * door_r, base, sin(rad) * door_r)
	gate.rotation.y = -rad
	add_child(gate)
	gate.opened.connect(_on_gate_opened.bind(gate))
	gates.append(gate)
	_gate_rooms[gate] = [shallower, deeper]


## A straight wall along a line out from the ring's centre.
func _add_radial_box(angle: float, r0: float, r1: float, bottom: float, height: float) -> void:
	if r1 - r0 <= 0.01 or height <= 0.01:
		return
	var rad := deg_to_rad(angle)
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = wall_material
	box.size = Vector3(r1 - r0, height, wall_thickness)
	var mid := (r0 + r1) / 2.0
	box.position = Vector3(cos(rad) * mid, bottom + height / 2.0, sin(rad) * mid)
	box.rotation.y = -rad
	add_child(box)


## A curved wall drawn as straight pieces. Invisible walls only block (no mesh, no navmesh).
func _add_arc_wall(a0: float, a1: float, radius: float, bottom: float, height: float, visible_wall: bool) -> void:
	if height <= 0.01:
		return
	var steps := maxi(1, ceili(absf(a1 - a0) / 45.0 * arc_segments_per_45))
	for s in steps:
		var p0 := deg_to_rad(lerpf(a0, a1, float(s) / steps))
		var p1 := deg_to_rad(lerpf(a0, a1, float(s + 1) / steps))
		var start := Vector2(cos(p0), sin(p0)) * radius
		var end := Vector2(cos(p1), sin(p1)) * radius
		var mid := (start + end) / 2.0
		var length := start.distance_to(end) + wall_thickness
		var yaw := -atan2(end.y - start.y, end.x - start.x)
		var center := Vector3(mid.x, bottom + height / 2.0, mid.y)
		var size := Vector3(length, height, wall_thickness)
		if visible_wall:
			var box := CSGBox3D.new()
			box.use_collision = true
			box.material = wall_material
			box.size = size
			box.position = center
			box.rotation.y = yaw
			add_child(box)
		else:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			shape.shape = box_shape
			body.add_child(shape)
			body.position = center
			body.rotation.y = yaw
			add_child(body)


## A straight ramp up to the upper floor, with a hole cut in the slab above it.
func _build_stairwell() -> void:
	var index := slot_keys.find("stairwell")
	var slot: Dictionary = SLOTS[index]
	var rad := deg_to_rad(slot.angle)
	var out := Vector3(cos(rad), 0.0, sin(rad))
	var along := Vector3(-out.z, 0.0, out.x) # Round the ring.
	var center := out * ramp_radius

	# Upper floor slab for the stairwell, with the hole.
	var slab := _add_sector(slot.angle - slot.span / 2.0, slot.angle + slot.span / 2.0,
			inner_radius, outer_radius, upper_floor_height - slab_thickness, slab_thickness)
	var hole := CSGBox3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.size = Vector3(ramp_length, ramp_width + 0.5, 4.0)
	# The slab is turned about X, so work in its local space.
	hole.transform = slab.global_transform.affine_inverse() * Transform3D(Basis(Vector3.UP, -atan2(along.z, along.x)), center + Vector3.UP * (upper_floor_height - slab_thickness))
	slab.add_child(hole)

	var rise := upper_floor_height
	var slope := atan2(rise, ramp_length)
	var ramp := CSGBox3D.new()
	ramp.use_collision = true
	ramp.material = floor_material
	ramp.size = Vector3(sqrt(ramp_length * ramp_length + rise * rise), 0.5, ramp_width)
	ramp.transform = Transform3D(
			Basis(Vector3.UP, -atan2(along.z, along.x)) * Basis(Vector3.BACK, slope),
			center + Vector3.UP * (rise / 2.0 - 0.25))
	add_child(ramp)


## The balcony circling the pit, and the pit itself. Unreachable until the boss fight is built.
func _build_pit() -> void:
	_add_sector(0.0, 360.0, pit_radius, inner_radius - wall_thickness / 2.0, balcony_height - slab_thickness, slab_thickness)
	_add_arc_wall(0.0, 360.0, pit_radius, balcony_height, railing_height, true)
	var pit_floor := _add_sector(0.0, 360.0, 0.0, pit_radius, -24.0, 1.0)
	pit_floor.name = "PitFloor"


# --- Opening rooms and spawns -------------------------------------------------------------

func _on_gate_opened(gate: Gate) -> void:
	var pair: Array = _gate_rooms[gate]
	_open_room(rooms[pair[0]])
	_open_room(rooms[pair[1]])
	# A gate between two rooms that are both open now has no point: clear it for free.
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		for other: Gate in gates:
			if other.is_open:
				continue
			var p: Array = _gate_rooms[other]
			if rooms[p[0]].is_open and rooms[p[1]].is_open:
				other.open()


func _update_active_spawns() -> void:
	if _neighbours.is_empty():
		return
	var player_rooms: Array[int] = []
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		var room := room_at_position(player.global_position)
		if room:
			player_rooms.append(room.index)
	if player_rooms.is_empty():
		player_rooms.append(0)
	var near := _rooms_within(player_rooms, spawn_reach)
	for room in rooms:
		room.set_spawns_active(room.is_open and near.has(room.index))


## Rooms no more than `reach` open doorways from any of the start rooms.
func _rooms_within(start: Array[int], reach: int) -> Dictionary:
	var found := {}
	var frontier: Array[int] = []
	for i in start:
		found[i] = true
		frontier.append(i)
	for step in reach:
		var next: Array[int] = []
		for at in frontier:
			for n: int in _neighbours[at]:
				if not found.has(n):
					found[n] = true
					next.append(n)
		frontier = next
	return found
