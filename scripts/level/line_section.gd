class_name LineSection
extends GraphSection
## The Line's layout: a four-storey assembly line around an open atrium where the giant is
## built. Each storey is two work areas split by a wall with a gate; switchback ramps
## at the ends climb to the next storey. The path is fixed (in at the bottom west, the
## Assembly Floor at the top west); which work areas fill the middle shuffles each run.
##
## Local layout: storeys sit on z 0..depth at y = 8 per storey, the atrium is z < 0.
## Area order: 0 L0 west, 1 L0 east, 2 L1 east, 3 L1 west, 4 L2 west, 5 L2 east,
## 6 L3 east, 7 L3 west.

const STOREYS := 4

@export var storey_height := 8.0
@export var hall_half_width := 37.0
@export var hall_depth := 30.0
@export var pad_depth := 5.0
@export var ramp_width := 5.0
@export var atrium_depth := 34.0
@export var roof_height := 34.0
@export var railing_height := 1.2

var area_count := STOREYS * 2


func _build() -> void:
	var links: Array = []
	for i in area_count - 1:
		links.append([i, i + 1])
	_set_links(area_count, links)
	var fill := _pick_fill()
	for i in area_count:
		var scene: PackedScene = start_room if i == 0 else (end_room if i == area_count - 1 else fill.pop_front())
		_place_area(scene, i)
	_build_shell()
	for k in STOREYS:
		_build_storey(k)
	for k in STOREYS - 1:
		_build_ramp(k)
	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Line layout (seed %d): %s" % [used_seed, ", ".join(names)])


## Which storey an area is on, and which side (-1 west, 1 east).
func area_storey(i: int) -> int:
	return i / 2


func area_side(i: int) -> int:
	var k := area_storey(i)
	var first := -1 if k % 2 == 0 else 1
	return first if i % 2 == 0 else -first


func area_center(i: int) -> Vector3:
	return to_global(_area_local(i))


func _area_local(i: int) -> Vector3:
	return Vector3(area_side(i) * hall_half_width / 2.0, area_storey(i) * storey_height, hall_depth / 2.0)


## The end a storey's ramp up leaves from (1 east, -1 west).
func ramp_end(k: int) -> int:
	return 1 if k % 2 == 0 else -1


## z of the ramp's bottom landing on storey k (low z on even storeys).
func _pad_z(k: int, bottom: bool) -> float:
	var low := k % 2 == 0
	if not bottom:
		low = not low
	return pad_depth / 2.0 if low else hall_depth - pad_depth / 2.0


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	if local.z < -1.0 or local.z > hall_depth + 1.0 or absf(local.x) > hall_half_width + ramp_width + 1.0:
		return null
	if local.y < -3.0 or local.y > roof_height:
		return null
	var k := clampi(floori((local.y + 1.5) / storey_height), 0, STOREYS - 1)
	var side := 1 if local.x >= 0.0 else -1
	for i in area_count:
		if area_storey(i) == k and area_side(i) == side:
			return rooms[i] if i < rooms.size() else null
	return null


func _pick_fill() -> Array[PackedScene]:
	var count := area_count - 2
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


func _place_area(scene: PackedScene, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	var floor_node := room.get_node_or_null("Floor")
	if floor_node:
		room.remove_child(floor_node)
		floor_node.free()
	room.position = _area_local(index)
	add_child(room)
	rooms.append(room)


# --- Geometry -----------------------------------------------------------------------------

func _slab(center: Vector3, size: Vector3, mat: Material = null) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = mat if mat else floor_material
	box.size = size
	box.position = center
	add_child(box)
	return box


func _build_shell() -> void:
	var outer := hall_half_width + ramp_width
	var z0 := -atrium_depth
	var z1 := hall_depth
	# Ground floor under everything (storeys and atrium).
	_slab(Vector3(0, -0.5, (z0 + z1) / 2.0), Vector3(outer * 2.0, 1.0, z1 - z0))
	# Walls: back, both ends, and the far side of the atrium.
	var h := roof_height
	_slab(Vector3(0, h / 2.0, z1 + wall_thickness / 2.0), Vector3(outer * 2.0 + 2.0, h, wall_thickness), wall_material)
	_slab(Vector3(0, h / 2.0, z0 - wall_thickness / 2.0), Vector3(outer * 2.0 + 2.0, h, wall_thickness), wall_material)
	for s: float in [-1.0, 1.0]:
		_slab(Vector3(s * (outer + wall_thickness / 2.0), h / 2.0, (z0 + z1) / 2.0), Vector3(wall_thickness, h, z1 - z0 + 2.0), wall_material)
	_slab(Vector3(0, h + 0.3, (z0 + z1) / 2.0), Vector3(outer * 2.0 + 2.0, 0.6, z1 - z0 + 2.0), wall_material)
	# The atrium is the giant's: a rail along its edge on the ground floor, and walls closing
	# the ramp strips off from it.
	for s: float in [-1.0, 1.0]:
		_slab(Vector3(s * (hall_half_width + ramp_width / 2.0), h / 2.0, -wall_thickness / 2.0), Vector3(ramp_width, h, wall_thickness), wall_material)


func _build_storey(k: int) -> void:
	var y := k * storey_height
	if k > 0:
		_slab(Vector3(0, y - 0.25, hall_depth / 2.0), Vector3(hall_half_width * 2.0, 0.5, hall_depth))
	# Railing over the atrium.
	_rail(Vector3(0, y, 0.15), Vector3(hall_half_width * 2.0, railing_height, 0.3))
	# Wall between the two areas, with a gate.
	var west := 2 * k if area_side(2 * k) == -1 else 2 * k + 1
	var east := 2 * k + 1 if west == 2 * k else 2 * k
	var wall_h := storey_height - 0.5 if k < STOREYS - 1 else 7.0
	var gap := door_width / 2.0 + 0.5
	var piece := (hall_depth - gap * 2.0) / 2.0
	for s: float in [-1.0, 1.0]:
		_slab(Vector3(0, y + wall_h / 2.0, hall_depth / 2.0 + s * (gap + piece / 2.0)), Vector3(wall_thickness, wall_h, piece), wall_material)
	_slab(Vector3(0, y + door_height + (wall_h - door_height) / 2.0, hall_depth / 2.0), Vector3(wall_thickness, wall_h - door_height, gap * 2.0), wall_material)
	_add_gate(west, east, Vector3(0, y, hall_depth / 2.0), PI / 2.0)
	# Each end: a rail along the ramp strip, with a gap at the landing pad(s) on this storey.
	for end: int in [-1, 1]:
		var pads: Array[float] = []
		if k < STOREYS - 1 and ramp_end(k) == end:
			pads.append(_pad_z(k, true))
		if k > 0 and ramp_end(k - 1) == end:
			pads.append(_pad_z(k - 1, false))
		_end_rail(k, end, pads)


## The rail (or wall, on the ground floor) between a storey and the ramp strip at one end.
func _end_rail(k: int, end: int, pads: Array[float]) -> void:
	var y := k * storey_height
	var x := end * hall_half_width
	var h := railing_height if k > 0 else storey_height - 0.5
	var cuts: Array = []
	for z in pads:
		cuts.append([z - pad_depth / 2.0, z + pad_depth / 2.0])
	var at := 0.0
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for cut in cuts:
		if cut[0] > at:
			_rail(Vector3(x, y, (at + cut[0]) / 2.0), Vector3(0.3, h, cut[0] - at))
		at = cut[1]
	if at < hall_depth:
		_rail(Vector3(x, y, (at + hall_depth) / 2.0), Vector3(0.3, h, hall_depth - at))


func _rail(base: Vector3, size: Vector3) -> void:
	_slab(base + Vector3.UP * size.y / 2.0, size, wall_material)


## A ramp up the strip at one end, from storey k to k + 1, with a landing pad at each end
## and a gate at the bottom.
func _build_ramp(k: int) -> void:
	var end := ramp_end(k)
	var x := end * (hall_half_width + ramp_width / 2.0)
	var y0 := k * storey_height
	var y1 := y0 + storey_height
	var zb := _pad_z(k, true)
	var zt := _pad_z(k, false)
	if k > 0:
		_slab(Vector3(x, y0 - 0.25, zb), Vector3(ramp_width, 0.5, pad_depth))
	_slab(Vector3(x, y1 - 0.25, zt), Vector3(ramp_width, 0.5, pad_depth))
	var start := Vector3(x, y0, zb + signf(zt - zb) * pad_depth / 2.0)
	var finish := Vector3(x, y1, zt - signf(zt - zb) * pad_depth / 2.0)
	var run := finish - start
	var length := run.length() + 0.6
	var deck := CSGBox3D.new()
	deck.use_collision = true
	deck.material = floor_material
	deck.size = Vector3(ramp_width, 0.5, length)
	var pitch := -atan2(run.y, absf(run.z))
	deck.basis = Basis.from_euler(Vector3(pitch, 0.0 if run.z > 0.0 else PI, 0.0), EULER_ORDER_YXZ)
	deck.position = (start + finish) / 2.0 + Vector3.DOWN * 0.25
	add_child(deck)
	var lower := 2 * k + 1 # The second area on storey k is the one at this end.
	_add_gate(lower, lower + 1, Vector3(end * hall_half_width, y0, zb), PI / 2.0)
