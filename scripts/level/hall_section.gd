class_name HallSection
extends GraphSection
## Cold Storage's layout: one huge refrigerated warehouse, split by long rows of shelving
## into a 3 by 3 grid of bays. Which shelf rows have a gap (with a gate) is shuffled each
## run, always leaving every bay reachable. The cryo chamber sits in the middle bay; the
## loading bay on the south wall is the way in from Servo Works and the Chassis Yard.
##
## Frozen stock waits on ledges along the shelving: shelf spots for Thawed robots.

const SLOTS := [
	Vector2i(0, 1), # 0: loading bay (start)
	Vector2i(0, 0), # 1: centre (cryo chamber)
	Vector2i(-1, 1), Vector2i(1, 1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

@export var center_room: PackedScene
@export var extra_links := 3
@export var bay_size := 36.0
@export var hall_height := 10.0
@export var rack_height := 6.0
@export var rack_thickness := 2.4
@export var ledge_height := 1.0
@export var ledge_depth := 0.9
@export var shelf_spot_spacing := 6.0
@export var rack_material: Material
@export var roofed := true
@export var far_room: PackedScene ## Fixed in the north-centre bay when set (the way on).
@export var office_walls := false ## Plain office walls instead of shelving (no ledges).
@export_group("Containers")
@export var container_walls := false ## Stacked shipping containers instead of shelving.
@export var shifting_walls := 0 ## Closed walls that get a container a crane lifts now and then.
@export var shifter_script: Script
@export var container_colors: Array[Color] = [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.6), Color(0.2, 0.5, 0.3), Color(0.8, 0.55, 0.15), Color(0.45, 0.45, 0.48)]

const FAR_SLOT := 7

var links: Array = []
var shelf_spots: Array[Marker3D] = []
var shifters: Array[Node3D] = []


func _build() -> void:
	_pick_links()
	_set_links(SLOTS.size(), links)
	var fill := _pick_fill()
	for i in SLOTS.size():
		var scene: PackedScene
		if i == 0:
			scene = start_room
		elif i == 1:
			scene = center_room
		elif i == FAR_SLOT and far_room:
			scene = far_room
		else:
			scene = fill.pop_front()
		_place_bay(scene, i)
	var half := bay_size * 1.5
	var floor_box := CSGBox3D.new()
	floor_box.use_collision = true
	floor_box.material = floor_material
	floor_box.size = Vector3(half * 2.0, 1.0, half * 2.0)
	floor_box.position.y = -0.5
	add_child(floor_box)
	for side: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wall := CSGBox3D.new()
		wall.use_collision = true
		wall.material = wall_material
		var along := Vector3(absf(side.z), 0, absf(side.x))
		wall.size = along * (half * 2.0 + 2.0) + side.abs() * wall_thickness + Vector3.UP * hall_height
		wall.position = side * (half + wall_thickness / 2.0) + Vector3.UP * hall_height / 2.0
		add_child(wall)
	if roofed:
		var roof := CSGBox3D.new()
		roof.use_collision = true
		roof.material = wall_material
		roof.size = Vector3(half * 2.0 + 2.0, 0.6, half * 2.0 + 2.0)
		roof.position.y = hall_height + 0.3
		add_child(roof)
	_build_racks()
	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("%s layout (seed %d): %s" % [get_parent().name, used_seed, ", ".join(names)])


func room_at_position(world_position: Vector3) -> Room:
	var local := to_local(world_position)
	var half := bay_size * 1.5
	if absf(local.x) > half + 0.5 or absf(local.z) > half + 0.5 or local.y < -3.0 or local.y > hall_height + 1.0:
		return null
	var cell := Vector2i(clampi(roundi(local.x / bay_size), -1, 1), clampi(roundi(local.z / bay_size), -1, 1))
	var i := SLOTS.find(cell)
	return rooms[i] if i >= 0 and i < rooms.size() else null


func bay_center(i: int) -> Vector3:
	var cell: Vector2i = SLOTS[i]
	return to_global(Vector3(cell.x, 0, cell.y) * bay_size)


# --- Layout -------------------------------------------------------------------------------

func _candidate_links() -> Array:
	var pairs: Array = []
	for a in SLOTS.size():
		for b in range(a + 1, SLOTS.size()):
			var d: Vector2i = SLOTS[a] - SLOTS[b]
			if absi(d.x) + absi(d.y) == 1:
				pairs.append([a, b])
	return pairs


## A random spanning tree from the loading bay, plus a few extra gaps.
func _pick_links() -> void:
	var candidates := _candidate_links()
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


func _pick_fill() -> Array[PackedScene]:
	var count := SLOTS.size() - (3 if far_room else 2)
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


func _place_bay(scene: PackedScene, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index
	var floor_node := room.get_node_or_null("Floor")
	if floor_node:
		room.remove_child(floor_node)
		floor_node.free()
	var cell: Vector2i = SLOTS[index]
	room.position = Vector3(cell.x, 0, cell.y) * bay_size
	if room.can_rotate:
		room.rotation.y = _rng.randi_range(0, 3) * PI / 2.0
	add_child(room)
	rooms.append(room)


# --- Shelving -----------------------------------------------------------------------------

## A shelf row along every edge between two bays. Linked bays get a gap and a gate.
## A few closed rows may get a crane-lifted container in the middle instead (a shortcut
## that opens now and then).
func _build_racks() -> void:
	var closed: Array = []
	for pair in _candidate_links():
		if not linked(pair[0], pair[1]):
			closed.append(pair)
	_shuffle(closed)
	var shifting := closed.slice(0, mini(shifting_walls, closed.size()))
	for pair in _candidate_links():
		var a: int = pair[0]
		var b: int = pair[1]
		var ca: Vector2i = SLOTS[a]
		var cb: Vector2i = SLOTS[b]
		var mid := Vector3(ca.x + cb.x, 0, ca.y + cb.y) * bay_size / 2.0
		var across := Vector3(cb.x - ca.x, 0, cb.y - ca.y) # From a to b.
		var along := Vector3(absf(across.z), 0, absf(across.x))
		var half := bay_size / 2.0
		if linked(a, b):
			var gap := door_width / 2.0 + 0.5
			var piece := half - gap
			for s: float in [-1.0, 1.0]:
				_rack(mid + along * s * (gap + piece / 2.0), along, across, piece)
			_add_gate(a, b, mid, 0.0 if across.x == 0.0 else PI / 2.0)
		elif shifting.has(pair) and shifter_script:
			var gap := door_width / 2.0 + 0.5
			var piece := half - gap
			for s: float in [-1.0, 1.0]:
				_rack(mid + along * s * (gap + piece / 2.0), along, across, piece)
			var shifter := AnimatableBody3D.new()
			shifter.name = "Shifter%d" % shifters.size()
			shifter.set_script(shifter_script)
			shifter.set("size", along * gap * 2.0 + across.abs() * rack_thickness + Vector3.UP * rack_height)
			shifter.set("color", container_colors[_rng.randi_range(0, container_colors.size() - 1)])
			shifter.set("bays", [a, b])
			shifter.position = mid
			add_child(shifter)
			shifters.append(shifter)
		else:
			_rack(mid, along, across, bay_size)


func _rack(center: Vector3, along: Vector3, across: Vector3, length: float) -> void:
	if container_walls:
		_container_stack(center, along, across, length)
		return
	if office_walls:
		var wall := CSGBox3D.new()
		wall.use_collision = true
		wall.material = rack_material if rack_material else wall_material
		wall.size = along * length + across.abs() * rack_thickness + Vector3.UP * rack_height
		wall.position = center + Vector3.UP * rack_height / 2.0
		add_child(wall)
		return
	var body := CSGBox3D.new()
	body.use_collision = true
	body.material = rack_material if rack_material else wall_material
	body.size = along * length + across.abs() * rack_thickness + Vector3.UP * rack_height
	body.position = center + Vector3.UP * rack_height / 2.0
	add_child(body)
	# Shelf boards sticking out a little, so the row reads as shelving.
	for level: float in [2.6, 4.2]:
		var board := CSGBox3D.new()
		board.use_collision = false
		board.material = wall_material
		board.size = along * length + across.abs() * (rack_thickness + 0.8) + Vector3.UP * 0.15
		board.position = center + Vector3.UP * level
		add_child(board)
	# A ledge each side: frozen stock waits on it.
	for s: float in [-1.0, 1.0]:
		var out := across * s
		var ledge := CSGBox3D.new()
		ledge.use_collision = true
		ledge.material = rack_material if rack_material else wall_material
		ledge.size = along * length + across.abs() * ledge_depth + Vector3.UP * ledge_height
		ledge.position = center + out * (rack_thickness + ledge_depth) / 2.0 + Vector3.UP * ledge_height / 2.0
		add_child(ledge)
		var count := floori(length / shelf_spot_spacing)
		for k in count:
			var t := (k + 0.5) / count - 0.5
			var spot := Marker3D.new()
			spot.name = "ShelfSpot%d" % shelf_spots.size()
			spot.add_to_group(Thawed.SHELF_GROUP)
			spot.position = center + along * t * length + out * (rack_thickness + ledge_depth) / 2.0 + Vector3.UP * (ledge_height + 0.05)
			# Faces out into the aisle (a node's front is -Z).
			spot.rotation.y = atan2(-out.x, -out.z)
			add_child(spot)
			shelf_spots.append(spot)


## Shipping containers stacked two or three high along the row, in random colours.
func _container_stack(center: Vector3, along: Vector3, across: Vector3, length: float) -> void:
	var body := CSGBox3D.new()
	body.use_collision = true
	body.material = rack_material if rack_material else wall_material
	body.size = along * length + across.abs() * rack_thickness + Vector3.UP * rack_height
	body.position = center + Vector3.UP * rack_height / 2.0
	add_child(body)
	var box_len := 6.0
	var count := maxi(1, floori(length / box_len))
	var level_h := rack_height / 2.0
	for k in count:
		for level in 2:
			var crate := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = along * (length / count - 0.15) + across.abs() * (rack_thickness + 0.1) + Vector3.UP * (level_h - 0.1)
			crate.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = container_colors[_rng.randi_range(0, container_colors.size() - 1)]
			mat.roughness = 0.8
			crate.material_override = mat
			var t := (k + 0.5) / count - 0.5
			crate.position = center + along * t * length + Vector3.UP * (level_h * level + level_h / 2.0)
			add_child(crate)
