class_name Section
extends Node3D
## Builds a section out of rooms, in a new order and shape every run.
##
## The start room sits at the origin. Each next room attaches to the north, east or west
## of the one before it (never south, so the path keeps climbing and can't run into itself).
## Walls go up around every room. Between rooms that follow each other the wall gets a
## doorway with a gate that players pay scrap to clear. Robots only spawn in open rooms
## near the players.
##
## Must sit under the NavigationRegion3D so its rooms and walls are in the navmesh bake.
## Co-op: the host will pick the seed and send it to everyone so all players build the same layout.

signal room_opened(room: Room)

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)] ## North, east, west.
const ALL_SIDES: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

@export var start_room: PackedScene
@export var required_rooms: Array[PackedScene] = [] ## Always in the run (like the shop).
@export var optional_rooms: Array[PackedScene] = [] ## Drawn at random to fill the rest.
@export var room_count := 4 ## Rooms after the start room.
@export var gate_scene: PackedScene
@export var first_gate_cost := 100
@export var gate_cost_step := 50 ## Each gate deeper in costs this much more.
@export var layout_seed := 0 ## 0 = new layout every run. Set a number to replay one layout.

@export_group("Shape")
@export var cell_size := 32.0 ## Every room is this wide and deep.
@export var wall_height := 7.0
@export var wall_thickness := 1.0
@export var door_width := 4.0
@export var door_height := 3.6
@export var wall_material: Material

@export_group("Spawning")
@export var spawn_reach := 1 ## Robots spawn in the players' rooms and this many rooms either side.
@export var spawn_update_interval := 0.5

var rooms: Array[Room] = [] ## In path order; rooms[0] is the start room.
var gates: Array[Gate] = [] ## gates[i] leads into rooms[i + 1].
var used_seed := 0

var _rng := RandomNumberGenerator.new()
var _room_at := {} # Vector2i cell -> Room
var _cells: Array[Vector2i] = []
var _spawn_update_left := 0.0


func _ready() -> void:
	used_seed = layout_seed if layout_seed != 0 else randi()
	_rng.seed = used_seed
	_build()
	_update_active_spawns()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_spawn_update_left -= delta
	if _spawn_update_left <= 0.0:
		_spawn_update_left = spawn_update_interval
		_update_active_spawns()


func room_at_position(world_position: Vector3) -> Room:
	var cell := Vector2i(roundi(world_position.x / cell_size), roundi(-world_position.z / cell_size))
	return _room_at.get(cell)


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * cell_size, 0.0, -cell.y * cell_size)


func _build() -> void:
	var scenes: Array[PackedScene] = [start_room]
	scenes.append_array(_pick_rooms())
	var cell := Vector2i.ZERO
	for i in scenes.size():
		if i > 0:
			cell = _next_cell(cell)
		_place_room(scenes[i], cell, i)

	var built := {}
	for i in rooms.size():
		for side in ALL_SIDES:
			var key := _cells[i] * 2 + side # The same wall seen from either room gets the same key.
			if built.has(key):
				continue
			built[key] = true
			var neighbour: Room = _room_at.get(_cells[i] + side)
			if neighbour and absi(neighbour.index - i) == 1:
				_build_doorway(_cells[i], side, rooms[maxi(i, neighbour.index)])
			else:
				_build_wall(_cells[i], side)

	gates.sort_custom(func(a: Gate, b: Gate) -> bool: return a.cost < b.cost)
	rooms[0].is_open = true
	var names := PackedStringArray()
	for room in rooms:
		names.append(room.display_name)
	print("Section layout (seed %d): %s" % [used_seed, " -> ".join(names)])


## The required rooms plus random optional ones, in a shuffled order.
func _pick_rooms() -> Array[PackedScene]:
	var optional := optional_rooms.duplicate()
	_shuffle(optional)
	var picked: Array[PackedScene] = required_rooms.duplicate()
	for scene: PackedScene in optional:
		if picked.size() >= room_count:
			break
		picked.append(scene)
	_shuffle(picked)
	return picked


## Fisher-Yates using the section's own RNG, so a seed always gives the same layout.
func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap


func _next_cell(from: Vector2i) -> Vector2i:
	var free: Array[Vector2i] = []
	for direction in DIRECTIONS:
		if not _room_at.has(from + direction):
			free.append(direction)
	# North is always free because the path never goes south.
	return from + free[_rng.randi_range(0, free.size() - 1)]


func _place_room(scene: PackedScene, cell: Vector2i, index: int) -> void:
	var room := scene.instantiate() as Room
	room.index = index
	room.name = "Room%d" % index # Same names in every co-op player's game.
	room.position = cell_to_world(cell)
	if room.can_rotate:
		room.rotation.y = _rng.randi_range(0, 3) * PI / 2.0
	add_child(room)
	rooms.append(room)
	_cells.append(cell)
	_room_at[cell] = room


func _build_wall(cell: Vector2i, side: Vector2i) -> void:
	_add_wall_box(cell, side, 0.0, cell_size + wall_thickness, 0.0, wall_height)


## A wall with a hole in the middle and a gate in the hole.
func _build_doorway(cell: Vector2i, side: Vector2i, leads_to: Room) -> void:
	var piece := (cell_size + wall_thickness - door_width) / 2.0
	var piece_offset := (door_width + piece) / 2.0
	_add_wall_box(cell, side, -piece_offset, piece, 0.0, wall_height)
	_add_wall_box(cell, side, piece_offset, piece, 0.0, wall_height)
	_add_wall_box(cell, side, 0.0, door_width, door_height, wall_height - door_height)

	var gate := gate_scene.instantiate() as Gate
	gate.name = "Gate%d" % (leads_to.index - 1)
	gate.cost = first_gate_cost + gate_cost_step * (leads_to.index - 1)
	gate.room_name = leads_to.display_name
	gate.position = cell_to_world(cell) + Vector3(side.x, 0.0, -side.y) * cell_size / 2.0
	if side.x != 0:
		gate.rotation.y = PI / 2.0
	add_child(gate)
	gate.opened.connect(_open_room.bind(leads_to))
	gates.append(gate)


## One box of wall on the given side of a cell. `along` slides it sideways along the wall.
func _add_wall_box(cell: Vector2i, side: Vector2i, along: float, length: float, bottom: float, height: float) -> void:
	var span := Vector3(1, 0, 0) if side.y != 0 else Vector3(0, 0, 1)
	var across := Vector3(absi(side.x), 0, absi(side.y))
	var box := CSGBox3D.new()
	box.use_collision = true
	box.material = wall_material
	box.size = span * length + across * wall_thickness + Vector3.UP * height
	box.position = cell_to_world(cell) + Vector3(side.x, 0.0, -side.y) * cell_size / 2.0 \
			+ span * along + Vector3.UP * (bottom + height / 2.0)
	add_child(box)


func _open_room(room: Room) -> void:
	if room.is_open:
		return
	room.is_open = true
	room_opened.emit(room)
	_update_active_spawns()


func _update_active_spawns() -> void:
	var player_rooms: Array[int] = []
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		var room := room_at_position(player.global_position)
		if room:
			player_rooms.append(room.index)
	if player_rooms.is_empty():
		player_rooms.append(0)
	for room in rooms:
		var near := false
		for player_room in player_rooms:
			if absi(room.index - player_room) <= spawn_reach:
				near = true
				break
		room.set_spawns_active(room.is_open and near)
