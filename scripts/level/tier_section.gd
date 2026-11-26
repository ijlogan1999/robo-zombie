class_name TierSection
extends GraphSection
## Servo Works' layout: clearings on three tiers, like a jungle. The floor (undergrowth),
## the trunks (platforms on server racks) and the canopy (giant circuit boards). Clearings
## are linked by catwalk bridges on a tier and long ramps between tiers. Which links exist,
## and which clearing sits in each slot of a tier, are shuffled every run.
##
## Slot 0 is the way in from the Crucible; slot 9 is the end clearing up in the canopy.

const FLOOR := 0
const TRUNK := 1
const CANOPY := 2

const SLOTS := [
	{"key": "entry", "pos": Vector3(0, 0, 48), "tier": FLOOR},
	{"key": "floor_w", "pos": Vector3(-32, 0, 0), "tier": FLOOR},
	{"key": "floor_c", "pos": Vector3(0, 0, 0), "tier": FLOOR},
	{"key": "floor_e", "pos": Vector3(32, 0, 0), "tier": FLOOR},
	{"key": "trunk_w", "pos": Vector3(-32, 8, -48), "tier": TRUNK},
	{"key": "trunk_c", "pos": Vector3(0, 8, -48), "tier": TRUNK},
	{"key": "trunk_e", "pos": Vector3(32, 8, -48), "tier": TRUNK},
	{"key": "canopy_w", "pos": Vector3(-32, 16, -96), "tier": CANOPY},
	{"key": "canopy_e", "pos": Vector3(32, 16, -96), "tier": CANOPY},
	{"key": "end", "pos": Vector3(0, 16, -96), "tier": CANOPY},
]

## Every link that could exist, as [slot, slot]. The first is always there.
const CANDIDATE_LINKS := [
	[0, 2],
	[1, 2], [2, 3], [4, 5], [5, 6], [7, 9], [9, 8],
	[1, 4], [2, 5], [3, 6], [4, 7], [5, 9], [6, 8],
]

@export var floor_rooms: Array[PackedScene] = []
@export var trunk_rooms: Array[PackedScene] = []
@export var canopy_rooms: Array[PackedScene] = []
@export var extra_links := 2
@export var platform_size := 24.0
@export var walk_width := 4.5
@export var railing_height := 1.2
@export var trunk_material: Material

var links: Array = []
var slot_keys: Array[String] = []


func _build() -> void:
	_pick_links()
	_set_links(SLOTS.size(), links)
	var floor_deck := _deck(floor_rooms, 3)
	var trunk_deck := _deck(trunk_rooms, 3)
	var canopy_deck := _deck(canopy_rooms, 2)
	for i in SLOTS.size():
		var scene: PackedScene
		if i == 0:
			scene = start_room
		elif i == SLOTS.size() - 1:
			scene = end_room
		else:
			match SLOTS[i].tier:
				FLOOR: scene = floor_deck.pop_front()
				TRUNK: scene = trunk_deck.pop_front()
				_: scene = canopy_deck.pop_front()
		_place_slot_room(scene, i)
	for i in SLOTS.size():
		_build_platform_edges(i)
		_build_trunks(i)
	for pair in links:
		_build_link(pair[0], pair[1])
	_build_undergrowth()
	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Servo layout (seed %d): %s" % [used_seed, ", ".join(names)])


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	var half := platform_size / 2.0 + 0.5
	for i in SLOTS.size():
		var p: Vector3 = SLOTS[i].pos
		if absf(local.x - p.x) <= half and absf(local.z - p.z) <= half and local.y > p.y - 1.5 and local.y < p.y + 7.0:
			return rooms[i] if i < rooms.size() else null
	return null


func slot_center(i: int) -> Vector3:
	return to_global(SLOTS[i].pos)


# --- Layout -------------------------------------------------------------------------------

func _pick_links() -> void:
	var candidates := CANDIDATE_LINKS.duplicate()
	var first: Array = candidates.pop_front()
	_shuffle(candidates)
	links = [first]
	var reached := {0: true, 2: true}
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


## Clearings for one tier's `count` slots, shuffled. Required rooms (like the Acid Swamp,
## which the Easter egg needs) always make the cut.
func _deck(pool: Array[PackedScene], count: int) -> Array[PackedScene]:
	var deck: Array[PackedScene] = []
	while deck.size() < count and not pool.is_empty():
		var round_deck := pool.duplicate()
		_shuffle(round_deck)
		deck.append_array(round_deck)
	for scene in required_rooms:
		var at := deck.find(scene)
		if at >= count:
			var swap := _rng.randi_range(0, count - 1)
			deck[at] = deck[swap]
			deck[swap] = scene
	return deck


func _place_slot_room(scene: PackedScene, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	room.position = SLOTS[index].pos
	if room.can_rotate:
		room.rotation.y = _rng.randi_range(0, 3) * PI / 2.0
	add_child(room)
	rooms.append(room)
	slot_keys.append(SLOTS[index].key)


## Which way a link leaves slot `from` toward slot `to`: one of the four sides.
func _side(from: int, to: int) -> Vector3:
	var d: Vector3 = SLOTS[to].pos - SLOTS[from].pos
	d.y = 0.0
	if absf(d.x) > absf(d.z):
		return Vector3(signf(d.x), 0, 0)
	return Vector3(0, 0, signf(d.z))


## Railings round each platform, with a gap wherever a link joins it.
func _build_platform_edges(i: int) -> void:
	var p: Vector3 = SLOTS[i].pos
	var half := platform_size / 2.0
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var open := false
		for n: int in _neighbours[i]:
			if _side(i, n) == side:
				open = true
		var along := Vector3(absf(side.z), 0, absf(side.x))
		var edge := p + side * half
		if open:
			var piece := (platform_size - walk_width) / 2.0
			for s: float in [-1.0, 1.0]:
				_railing(edge + along * s * (walk_width + piece) / 2.0, along * piece + side.abs() * 0.3)
		else:
			_railing(edge, along * platform_size + side.abs() * 0.3)


func _railing(center: Vector3, span: Vector3) -> void:
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = wall_material
	box.size = Vector3(maxf(span.x, 0.3), railing_height, maxf(span.z, 0.3))
	box.position = center + Vector3.UP * railing_height / 2.0
	add_child(box)


## Server-rack trunks holding up the raised platforms.
func _build_trunks(i: int) -> void:
	var p: Vector3 = SLOTS[i].pos
	if p.y <= 0.0:
		return
	var off := platform_size / 2.0 - 2.0
	for x: float in [-off, off]:
		for z: float in [-off, off]:
			var trunk := CSGBox3D.new()
			trunk.use_collision = true
			trunk.material = trunk_material if trunk_material else wall_material
			trunk.size = Vector3(2.5, p.y + 4.0, 2.5)
			trunk.position = Vector3(p.x + x, (p.y - 1.0) / 2.0 - 2.5, p.z + z)
			add_child(trunk)


## A catwalk (same tier) or a long ramp (between tiers), railed on both sides, with a gate
## where it meets the deeper clearing.
func _build_link(a: int, b: int) -> void:
	var side := _side(a, b)
	var start: Vector3 = SLOTS[a].pos + side * platform_size / 2.0
	var end: Vector3 = SLOTS[b].pos - side * platform_size / 2.0
	var run := end - start
	var flat := Vector3(run.x, 0, run.z)
	var length := sqrt(flat.length_squared() + run.y * run.y) + 0.6
	var deck := CSGBox3D.new()
	deck.use_collision = true
	deck.material = floor_material
	deck.size = Vector3(walk_width, 0.5, length)
	var mid := (start + end) / 2.0
	deck.position = mid + Vector3.DOWN * 0.25
	var yaw := atan2(flat.x, flat.z)
	var pitch := -atan2(run.y, flat.length())
	deck.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	add_child(deck)
	for s: float in [-1.0, 1.0]:
		var rail := CSGBox3D.new()
		rail.use_collision = true
		rail.material = wall_material
		rail.size = Vector3(0.3, railing_height, length)
		rail.basis = deck.basis
		rail.position = mid + deck.basis.x * s * (walk_width / 2.0 + 0.15) + Vector3.UP * (railing_height / 2.0)
		add_child(rail)
	var deeper := b if depth[b] > depth[a] else a
	var gate_at: Vector3 = SLOTS[deeper].pos + _side(deeper, b if deeper == a else a) * (platform_size / 2.0 - 0.5)
	_add_gate(a, b, gate_at, 0.0 if side.x == 0.0 else PI / 2.0)


## Mist over the jungle floor far below (just for looks).
func _build_undergrowth() -> void:
	var mist := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 200)
	mist.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.75, 0.45, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.mesh.material = mat
	mist.position = Vector3(0, -3, -24)
	add_child(mist)
