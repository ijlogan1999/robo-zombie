class_name Slagger
extends Robot
## The Crucible's unique robot: a flamethrower that sprays molten metal onto scrap to melt it.
## It ignores players and works the scrap until it spots one (or gets shot, or loses
## patience), then turns its spray on them. Each spray leaves a puddle of molten metal.

@export var sight_range := 18.0
@export var patience := 10.0 ## Seconds before it comes for players anyway.
@export var spray_time := 1.2
@export var spray_tick := 0.2
@export var spray_reach := 6.0
@export var spray_angle := 35.0 ## Degrees either side of straight ahead.
@export var puddle_time := 4.0
@export var puddle_damage := 20.0

var aware := false
var spraying := false: ## Replicated, so co-op copies show the flame.
	set(value):
		spraying = value
		if is_node_ready():
			$Flame.visible = value

var _spray_left := 0.0
var _tick_left := 0.0
var _alive_for := 0.0
var _work_spot: Marker3D
var _has_spot := false


func _ready() -> void:
	super._ready()
	$Flame.visible = false
	_work_spot = Marker3D.new()
	_work_spot.top_level = true
	add_child(_work_spot)
	health.damaged.connect(func(_amount: float) -> void: aware = true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or health.dead:
		return
	_alive_for += delta
	if not aware and _alive_for >= patience:
		aware = true
	if spraying:
		_spray_left -= delta
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = spray_tick
			_burn_cone()
		if _spray_left <= 0.0:
			spraying = false
			_cooldown_left = attack_cooldown
			_leave_puddle()


func _find_nearest_player() -> Node3D:
	var nearest := super._find_nearest_player()
	if not aware and nearest and global_position.distance_to(nearest.global_position) <= sight_range \
			and _can_see(nearest):
		aware = true
	if aware:
		return nearest
	if not is_on_floor():
		_work_spot.global_position = global_position # Wait until it has landed.
	elif not _has_spot or (global_position.distance_to(_work_spot.global_position) < attack_range * 0.8 and not spraying):
		_has_spot = true
		_pick_work_spot()
	return _work_spot


func _can_attack() -> bool:
	return not spraying and is_on_floor()


func _should_hold_position(_distance: float) -> bool:
	return spraying


func _finish_attack() -> void:
	_eye_material.emission_energy_multiplier = 1.5
	spraying = true
	_spray_left = spray_time
	_tick_left = 0.0
	Sfx.broadcast_at(&"bolt_fire", global_position + Vector3.UP, -2.0)


func _burn_cone() -> void:
	var forward := -global_transform.basis.z
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.is_targetable():
			continue
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() <= spray_reach and rad_to_deg(forward.angle_to(to.normalized())) <= spray_angle:
			player.take_damage(attack_damage * spray_tick, global_position, self)


func _leave_puddle() -> void:
	var at := global_position - global_transform.basis.z * spray_reach * 0.6
	_spawn_puddle(at)
	if Net.is_session():
		_net_puddle.rpc(at)


@rpc("authority", "reliable")
func _net_puddle(at: Vector3) -> void:
	_spawn_puddle(at)


## Puddles are separate from the robot so they outlive it. Every game makes its own copy,
## so each player's own game hurts them.
func _spawn_puddle(at: Vector3) -> void:
	var puddle := HazardZone.new()
	puddle.damage_per_second = puddle_damage
	puddle.hurts_robots = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.6
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position.y = 0.5
	puddle.add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.6
	disc.height = 0.08
	mesh.mesh = disc
	mesh.material_override = preload("res://materials/molten.tres")
	mesh.position.y = 0.04
	puddle.add_child(mesh)
	get_tree().current_scene.add_child(puddle)
	puddle.global_position = at
	get_tree().create_timer(puddle_time, false).timeout.connect(puddle.queue_free)


func _can_see(player: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.5, player.global_position + Vector3.UP)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player


func _pick_work_spot() -> void:
	var a := randf() * TAU
	var r := randf_range(4.0, 9.0)
	var spot := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	# Snap to the navmesh so the spot is on the floor, not in the air or inside a mound.
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var snapped := NavigationServer3D.map_get_closest_point(map, spot)
		if snapped.distance_to(spot) < 4.0:
			spot = snapped
	_work_spot.global_position = spot
