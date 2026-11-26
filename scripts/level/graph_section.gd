class_name GraphSection
extends Section
## A section whose rooms sit in fixed slots joined by doorways, like a graph.
## Subclasses lay out the slots and the geometry; this handles door depths and prices,
## clearing leftover gates, robot spawns near players, and shared drawing helpers.

@export var floor_material: Material
@export var arc_segments_per_45 := 4 ## Straight wall pieces used to draw 45 degrees of curve.

var depth: Array[int] = [] ## Doors from the start room to each room.

var _neighbours: Array = [] # index -> Array[int]
var _gate_rooms := {} # Gate -> [room index, room index]


## Records which rooms join which and how deep each one is from room 0.
func _set_links(count: int, pairs: Array) -> void:
	_neighbours.clear()
	for i in count:
		_neighbours.append([])
	for pair in pairs:
		_neighbours[pair[0]].append(pair[1])
		_neighbours[pair[1]].append(pair[0])
	depth.clear()
	depth.resize(count)
	depth.fill(-1)
	depth[0] = 0
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for next: int in _neighbours[at]:
			if depth[next] < 0:
				depth[next] = depth[at] + 1
				queue.append(next)


func linked(a: int, b: int) -> bool:
	return b in _neighbours[a]


## A gate in a doorway between rooms a and b. It costs more the deeper it leads.
func _add_gate(a: int, b: int, at: Vector3, yaw: float) -> Gate:
	var deeper := b if depth[b] > depth[a] else a
	var shallower := a if deeper == b else b
	var gate := gate_scene.instantiate() as Gate
	gate.name = "Gate%d" % gates.size()
	gate.cost = first_gate_cost + gate_cost_step * maxi(depth[deeper] - 1, 0)
	gate.room_name = rooms[deeper].display_name
	gate.position = at
	gate.rotation.y = yaw
	add_child(gate)
	gate.opened.connect(_on_gate_opened.bind(gate))
	gates.append(gate)
	_gate_rooms[gate] = [shallower, deeper]
	return gate


func gate_rooms(gate: Gate) -> Array:
	return _gate_rooms[gate]

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
	var player_rooms := _player_room_indices()
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
