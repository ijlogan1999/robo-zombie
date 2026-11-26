class_name ShiftingContainer
extends AnimatableBody3D
## A container in a Shipping Bay row that a crane lifts out now and then, opening a
## shortcut between two bays for a while before it's set back down. It won't come down on
## anyone. The host runs the cycle and tells everyone.

enum State { DOWN, RISING, UP, LOWERING }

@export var size := Vector3(5, 6, 2.6)
@export var color := Color(0.7, 0.2, 0.15)
@export var down_time := 40.0
@export var up_time := 20.0
@export var move_time := 3.0
@export var lift := 7.0

var state := State.DOWN
var bays: Array = []

var _left := 0.0
var _base_y := 0.0


func _ready() -> void:
	add_to_group(&"shifting_containers")
	sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material_override = mat
	mesh.position.y = size.y / 2.0
	add_child(mesh)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = size + Vector3(0.05, -size.y + 0.4, 0.05)
	stripe.mesh = stripe_mesh
	var warn := StandardMaterial3D.new()
	warn.albedo_color = Color(0.95, 0.8, 0.1)
	stripe.material_override = warn
	stripe.position.y = size.y - 0.4
	add_child(stripe)
	_base_y = position.y
	_left = down_time * randf_range(0.5, 1.0)


func is_open() -> bool:
	return state == State.UP


func _physics_process(delta: float) -> void:
	match state:
		State.RISING:
			position.y = minf(position.y + lift / move_time * delta, _base_y + lift)
		State.LOWERING:
			if _blocked():
				return
			position.y = maxf(position.y - lift / move_time * delta, _base_y)
	if Net.is_session() and not multiplayer.is_server():
		return
	_left -= delta
	if _left > 0.0:
		return
	match state:
		State.DOWN:
			_go(State.RISING)
		State.RISING:
			_go(State.UP)
		State.UP:
			_go(State.LOWERING)
		State.LOWERING:
			if not _blocked():
				_go(State.DOWN)


func _go(new_state: State) -> void:
	if Net.is_session() and multiplayer.is_server():
		_net_state.rpc(new_state)
	_set_state(new_state)


func _set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.DOWN:
			_left = down_time
			position.y = _base_y
		State.RISING:
			_left = move_time
			Sfx.play_at(&"gate_open", global_position + Vector3.UP * size.y, 0.0)
		State.UP:
			_left = up_time
			position.y = _base_y + lift
		State.LOWERING:
			_left = move_time


## Something standing in the gap: hold the container up.
func _blocked() -> bool:
	var half := size / 2.0
	for group in ["players", "robots"]:
		for body: Node3D in get_tree().get_nodes_in_group(group):
			var local := to_local(body.global_position)
			local.y = 0.0
			if absf(local.x) < half.x + 0.6 and absf(local.z) < half.z + 0.6:
				var under := body.global_position.y - (global_position.y - position.y + _base_y)
				if under < size.y:
					return true
	return false


@rpc("authority", "reliable")
func _net_state(new_state: State) -> void:
	_set_state(new_state)
