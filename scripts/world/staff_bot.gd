class_name StaffBot
extends CharacterBody3D
## The fake employee players build for the Easter egg. Once the Line wakes it, it follows
## the team around Kiln: it walks after the nearest player and, if it falls far behind or gets
## stuck (a door or a chute took the team elsewhere), it catches up by turning up next to them.
## The host moves it and tells everyone where it is.

const FOLLOW_DISTANCE := 3.0
const CATCH_UP_DISTANCE := 30.0
const SYNC_INTERVAL := 0.1

@export var speed := 5.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _sync_left := 0.0
var _agent: NavigationAgent3D
var _stuck_for := 0.0


func _ready() -> void:
	add_to_group("staff_bot")
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.8
	_agent.target_desired_distance = FOLLOW_DISTANCE
	add_child(_agent)
	for part in StaffBot.build_body():
		add_child(part)


## The Staff Bot's look: a grey robot in a tie, with a badge clip.
static func build_body() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for spec in [
		[Vector3(0.8, 1.0, 0.5), Vector3(0, 1.0, 0), Color(0.62, 0.64, 0.68)],
		[Vector3(0.55, 0.45, 0.5), Vector3(0, 1.75, 0), Color(0.7, 0.72, 0.76)],
		[Vector3(0.4, 0.08, 0.05), Vector3(0, 1.8, -0.27), Color(0.3, 0.9, 1.0)],
		[Vector3(0.14, 0.55, 0.05), Vector3(0, 1.05, -0.27), Color(0.15, 0.25, 0.6)],
		[Vector3(0.18, 0.5, 0.2), Vector3(-0.2, 0.25, 0), Color(0.4, 0.4, 0.44)],
		[Vector3(0.18, 0.5, 0.2), Vector3(0.2, 0.25, 0), Color(0.4, 0.4, 0.44)],
	]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[0]
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[2]
		mesh.material_override = mat
		mesh.position = spec[1]
		parts.append(mesh)
	return parts


func _physics_process(delta: float) -> void:
	if Net.is_session() and not multiplayer.is_server():
		return
	var leader := _nearest_player()
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var flat := Vector3.ZERO
	if leader:
		var to := leader.global_position - global_position
		var lagging := to.length() > FOLLOW_DISTANCE * 2.5
		_stuck_for = _stuck_for + delta if lagging and Vector2(get_real_velocity().x, get_real_velocity().z).length() < 0.5 else 0.0
		if to.length() > CATCH_UP_DISTANCE or _stuck_for > 1.5:
			_stuck_for = 0.0
			global_position = leader.global_position - leader.global_basis.z * -1.5 + Vector3.UP * 0.2
			velocity = Vector3.ZERO
		else:
			_agent.target_position = leader.global_position
			if Vector2(to.x, to.z).length() > FOLLOW_DISTANCE:
				var next := _agent.get_next_path_position() - global_position
				next.y = 0.0
				if next.length() < 0.1:
					next = Vector3(to.x, 0, to.z)
				flat = next.normalized() * speed
				rotation.y = atan2(-flat.x, -flat.z)
	velocity.x = flat.x
	velocity.z = flat.z
	move_and_slide()
	if Net.is_session():
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_net_place.rpc(global_position, rotation.y)


func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	for p: Player in get_tree().get_nodes_in_group("players"):
		if not p.is_targetable():
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


@rpc("authority", "unreliable_ordered")
func _net_place(at: Vector3, yaw: float) -> void:
	global_position = at
	rotation.y = yaw
