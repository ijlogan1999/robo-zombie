class_name DomeSection
extends GraphSection
## The Crucible's layout: one huge dome with a burning scrap heap inside, no built rooms.
##
## Players drop in at the centre. Mounds of scrap split the floor into 10 zones: the centre,
## an inner ring of 3 and an outer ring of 6. Which mounds have a gap (with a scrap gate
## to clear) is shuffled each run, always leaving every zone reachable. The ways out are
## doors in the dome wall, and which outer zones hold them is shuffled too.

const ZONES := [
	{"key": "landing", "angle": 0.0, "span": 360.0, "r0": 0.0, "r1": 14.0},
	{"key": "inner_n", "angle": 90.0, "span": 120.0, "r0": 14.0, "r1": 34.0},
	{"key": "inner_sw", "angle": 210.0, "span": 120.0, "r0": 14.0, "r1": 34.0},
	{"key": "inner_se", "angle": 330.0, "span": 120.0, "r0": 14.0, "r1": 34.0},
	{"key": "outer_0", "angle": 0.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
	{"key": "outer_60", "angle": 60.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
	{"key": "outer_120", "angle": 120.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
	{"key": "outer_180", "angle": 180.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
	{"key": "outer_240", "angle": 240.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
	{"key": "outer_300", "angle": 300.0, "span": 60.0, "r0": 34.0, "r1": 62.0},
]

## Every mound that could have a gap, as [zone, zone].
const CANDIDATE_LINKS := [
	[0, 1], [0, 2], [0, 3],
	[1, 2], [2, 3], [3, 1],
	[1, 5], [1, 6], [2, 7], [2, 8], [3, 9], [3, 4],
	[4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 4],
]

@export var landing_room: PackedScene
@export var extra_links := 4 ## Gaps added on top of the ones needed to reach every zone.
@export var exits: Array[Dictionary] = [] ## {"name": "Servo Works", "arrival": &"servo_from_crucible"}
@export var section_door_scene: PackedScene
@export var exit_cost := 1250

@export_group("Dome")
@export var dome_radius := 62.0
@export var dome_height := 30.0
@export var roof_hole_radius := 18.0
@export var mound_height := 7.0
@export var mound_material: Material

var zone_keys: Array[String] = []
var links: Array = [] ## The mounds with gaps this run, as [zone, zone].
var exit_zones: Array[int] = [] ## Outer zones holding the real doors out, in `exits` order.
var exit_doors: Array[SectionDoor] = []


func _build() -> void:
	_pick_links()
	_set_links(ZONES.size(), links)
	var fill := _pick_zone_rooms()
	for i in ZONES.size():
		_place_zone_room(landing_room if i == 0 else fill.pop_front(), i)

	_add_sector(0.0, 360.0, 0.0, dome_radius, -0.5, 0.5)
	_add_arc_wall(0.0, 360.0, dome_radius, 0.0, dome_height, true)
	_add_sector(0.0, 360.0, roof_hole_radius, dome_radius + 1.0, dome_height, 1.0)
	_build_mounds()
	_build_exits()

	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Crucible layout (seed %d): %s; exits in %s" % [used_seed, ", ".join(names), str(exit_zones)])


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	var r := Vector2(local.x, local.z).length()
	if r > dome_radius + 1.0 or local.y < -5.0 or local.y > dome_height + 2.0:
		return null
	return rooms[zone_at(r, rad_to_deg(atan2(local.z, local.x)))] if not rooms.is_empty() else null


func zone_at(r: float, angle: float) -> int:
	for i in ZONES.size():
		var zone: Dictionary = ZONES[i]
		if r < zone.r0 or r > zone.r1 + 0.5:
			continue
		if zone.span >= 360.0 or absf(angle_difference(deg_to_rad(angle), deg_to_rad(zone.angle))) <= deg_to_rad(zone.span / 2.0):
			return i
	return ZONES.size() - 1 if r > 34.0 else 0


func zone_center(index: int) -> Vector3:
	var zone: Dictionary = ZONES[index]
	if index == 0:
		return to_global(Vector3.ZERO)
	var a := deg_to_rad(zone.angle)
	var r: float = (zone.r0 + zone.r1) / 2.0
	return to_global(Vector3(cos(a) * r, 0.0, sin(a) * r))


# --- Layout -------------------------------------------------------------------------------

## A random spanning tree from the landing zone, plus a few extra gaps.
func _pick_links() -> void:
	var candidates := CANDIDATE_LINKS.duplicate()
	_shuffle(candidates)
	var reached := {0: true}
	links.clear()
	var progress := true
	while progress:
		progress = false
		for pair in candidates:
			if links.has(pair):
				continue
			if reached.has(pair[0]) != reached.has(pair[1]):
				links.append(pair)
				reached[pair[0]] = true
				reached[pair[1]] = true
				progress = true
	var added := 0
	for pair in candidates:
		if added >= extra_links:
			break
		if not links.has(pair):
			links.append(pair)
			added += 1


func _pick_zone_rooms() -> Array[PackedScene]:
	var count := ZONES.size() - 1
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


func _place_zone_room(scene: PackedScene, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	var floor_node := room.get_node_or_null("Floor")
	if floor_node:
		room.remove_child(floor_node)
		floor_node.free()
	room.position = to_local(zone_center(index))
	var a := deg_to_rad(ZONES[index].angle)
	var turn := _rng.randi_range(0, 3) * PI / 2.0 if room.can_rotate else 0.0
	room.rotation.y = PI / 2.0 - a + turn
	add_child(room)
	rooms.append(room)
	zone_keys.append(ZONES[index].key)


# --- Mounds -------------------------------------------------------------------------------

func _build_mounds() -> void:
	# Ring boundaries: landing/inner at r 14, inner/outer at r 34.
	for i in range(1, 4):
		var zone: Dictionary = ZONES[i]
		var a0: float = zone.angle - zone.span / 2.0
		_mound_arc(0, i, a0, zone.span, 14.0)
	for i in range(4, 10):
		var zone: Dictionary = ZONES[i]
		var inner := _inner_of(i)
		_mound_arc(inner, i, zone.angle - zone.span / 2.0, zone.span, 34.0)
	# Radial boundaries between neighbours in the same ring.
	for pair in [[1, 2, 150.0], [2, 3, 270.0], [3, 1, 30.0]]:
		_mound_line(pair[0], pair[1], pair[2], 14.0, 34.0)
	for i in range(4, 10):
		var next := 4 + (i - 4 + 1) % 6
		_mound_line(i, next, ZONES[i].angle + 30.0, 34.0, dome_radius)


func _inner_of(outer: int) -> int:
	match outer:
		5, 6: return 1
		7, 8: return 2
	return 3


## A mound along a circle. If the two zones are linked, it has one gap with a gate.
func _mound_arc(a: int, b: int, start: float, span: float, radius: float) -> void:
	var gap_angle := start + span / 2.0
	var gap_half := rad_to_deg((door_width / 2.0 + 0.5) / radius)
	var has_gap := linked(a, b)
	if has_gap:
		_mound_arc_piece(start, gap_angle - gap_half, radius)
		_mound_arc_piece(gap_angle + gap_half, start + span, radius)
		var rad := deg_to_rad(gap_angle)
		_add_gate(a, b, Vector3(cos(rad) * radius, 0.0, sin(rad) * radius), PI / 2.0 - rad)
	else:
		_mound_arc_piece(start, start + span, radius)


func _mound_arc_piece(a0: float, a1: float, radius: float) -> void:
	var length := deg_to_rad(absf(a1 - a0)) * radius
	var pieces := maxi(1, ceili(length / 3.0))
	for p in pieces:
		var a := deg_to_rad(lerpf(a0, a1, (p + 0.5) / pieces))
		var center := Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		_mound_block(center, -a + PI / 2.0, length / pieces + 0.6)


func _mound_line(a: int, b: int, angle: float, r0: float, r1: float) -> void:
	var rad := deg_to_rad(angle)
	var dir := Vector3(cos(rad), 0.0, sin(rad))
	var gap_r := (r0 + r1) / 2.0
	var has_gap := linked(a, b)
	var length := r1 - r0
	var pieces := maxi(1, ceili(length / 3.0))
	for p in pieces:
		var r := lerpf(r0, r1, (p + 0.5) / pieces)
		if has_gap and absf(r - gap_r) < door_width / 2.0 + 1.0:
			continue
		_mound_block(dir * r, -rad, length / pieces + 0.6)
	if has_gap:
		_add_gate(a, b, dir * gap_r, -rad)


## One lump of scrap. Heights wobble so the mound reads as a pile, not a wall.
func _mound_block(center: Vector3, yaw: float, length: float) -> void:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = mound_material if mound_material else wall_material
	var h := mound_height + _rng.randf_range(-1.0, 2.0)
	box.size = Vector3(length, h, _rng.randf_range(2.2, 3.4))
	box.position = center + Vector3.UP * h / 2.0
	box.rotation = Vector3(_rng.randf_range(-0.06, 0.06), yaw, _rng.randf_range(-0.08, 0.08))
	add_child(box)


# --- Exits --------------------------------------------------------------------------------

func _build_exits() -> void:
	var outer: Array = [4, 5, 6, 7, 8, 9]
	_shuffle(outer)
	exit_zones.clear()
	for i in exits.size():
		exit_zones.append(outer[i])
	if section_door_scene == null:
		return
	for i in exits.size():
		var zone: Dictionary = ZONES[exit_zones[i]]
		var door := section_door_scene.instantiate() as SectionDoor
		door.name = "Exit%d" % i
		door.destination_name = exits[i].get("name", "Exit")
		door.arrival_id = exits[i].get("arrival", &"")
		door.cost = exit_cost
		var a := deg_to_rad(zone.angle)
		door.position = Vector3(cos(a), 0.0, sin(a)) * (dome_radius - 1.5)
		door.rotation.y = PI / 2.0 - a
		add_child(door)
		exit_doors.append(door)
