class_name SentryTurret
extends StaticBody3D
## A training turret on the Proving Grounds' firing ranges. It tracks you when you're in
## range and in sight, paints you with a laser for a moment, then fires. Shoot it enough
## and it sparks out for a while.
##
## Each game's turret aims at its own player (like other hazards). Knocking it out counts
## for everyone.

@export var reach := 24.0
@export var lock_time := 0.7
@export var fire_interval := 1.8
@export var bolt_speed := 22.0
@export var bolt_damage := 12.0
@export var max_health := 80.0
@export var down_time := 15.0

var health := 0.0
var down := false

var _lock := 0.0
var _cooldown := 0.0
var _down_left := 0.0
var _head: Node3D
var _laser: MeshInstance3D


func _ready() -> void:
	add_to_group(&"sentry_turrets")
	health = max_health
	_head = get_node_or_null("Head")
	_laser = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 1.0)
	_laser.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.1, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser.material_override = mat
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)


func muzzle() -> Vector3:
	return (_head.global_position if _head else global_position + Vector3.UP * 2.0)


func take_damage(amount: float, _at: Vector3, _attacker: Node = null) -> bool:
	if down:
		return false
	health -= amount
	if health <= 0.0:
		if Net.is_session():
			_net_down.rpc()
		else:
			_net_down()
		return true
	return false


@rpc("any_peer", "call_local", "reliable")
func _net_down() -> void:
	if down:
		return
	down = true
	_down_left = down_time
	_laser.visible = false
	_lock = 0.0
	if _head:
		_head.rotation.x = 0.6 # Slumped.
	Sfx.play_at(&"gate_open", muzzle(), 0.0)


func _physics_process(delta: float) -> void:
	if down:
		_down_left -= delta
		if _down_left <= 0.0:
			down = false
			health = max_health
			if _head:
				_head.rotation.x = 0.0
		return
	_cooldown -= delta
	var player := _local_player()
	if player == null or not _sees(player):
		_lock = 0.0
		_laser.visible = false
		return
	var aim_at := player.global_position + Vector3.UP * 1.2
	if _head:
		var flat := aim_at - _head.global_position
		_head.global_rotation.y = atan2(-flat.x, -flat.z)
	_lock += delta
	_show_laser(aim_at)
	if _lock >= lock_time and _cooldown <= 0.0:
		_cooldown = fire_interval
		_fire(aim_at)


func _fire(aim_at: Vector3) -> void:
	var from := muzzle()
	var dir := (aim_at - from).normalized()
	var bolt: BoltProjectile = preload("res://scenes/enemies/bolt_projectile.tscn").instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from + dir * 1.8 # Clear of its own body.
	bolt.launch(dir * bolt_speed, bolt_damage, self)
	Sfx.play_at(&"bolt_fire", from, -4.0)


func _show_laser(aim_at: Vector3) -> void:
	var from := muzzle()
	var span := aim_at - from
	_laser.visible = true
	_laser.global_position = from + span / 2.0
	_laser.global_basis = Basis.looking_at(span.normalized(), Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT).scaled(Vector3(1, 1, span.length()))


func _sees(player: Player) -> bool:
	var from := muzzle()
	var to := player.global_position + Vector3.UP * 1.2
	if from.distance_to(to) > reach:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Layers.SHOTS
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _local_player() -> Player:
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority() and p.is_targetable():
			return p
	return null
