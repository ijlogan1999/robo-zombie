class_name Robot
extends CharacterBody3D
## Basic melee robot: walks to the nearest player along the navmesh and swings when close.
##
## The swing has a wind-up (eyes flare) so players can read it and back off.
## Robots only think on the server; in co-op, clients will just see the results.

signal struck(attacker: Node) ## Host only: something hit it.

signal died(robot: Robot)

@export var move_speed := 3.0
@export var turn_speed := 10.0
@export var attack_range := 1.6
@export var attack_reach := 2.2 ## A swing still lands if the target is this close when it finishes.
@export var attack_damage := 20.0
@export var attack_windup := 0.45
@export var attack_cooldown := 1.2
@export var repath_interval := 0.25
@export var separation_radius := 1.4 ## Robots closer than this steer apart.
@export var separation_strength := 0.8
@export var scrap_scene: PackedScene
@export var scrap_value := 10
@export_group("Round scaling")
@export var health_multiplier := 1.0 ## Applied to the round's robot health. Tougher or flimsier types.
@export var speed_multiplier := 1.0 ## Applied to the round's robot speed.
@export var max_speed := 7.0

var target: Node3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _repath_left := 0.0
var _cooldown_left := 0.0
var _windup_left := -1.0
var _body_material: StandardMaterial3D
var _body_color: Color
var _base_color: Color
var _frozen_left := 0.0
var _eye_material: StandardMaterial3D
## Docile robots (Accounting's office staff) ignore players and wander between their
## points until something sets them off.
var docile := false
var wander_points: Array[Node3D] = []
var _wander_to: Node3D

@onready var health: HealthComponent = $HealthComponent
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _meshes: Node3D = $Meshes


## Set stats before adding the robot to the scene (used by the round spawner).
## Each robot type scales the round's numbers by its own multipliers.
func configure(max_health: float, speed: float) -> void:
	$HealthComponent.max_health = max_health * health_multiplier
	move_speed = minf(speed * speed_multiplier, max_speed)


func _ready() -> void:
	# Each robot gets its own materials so hit flashes and eye flares don't affect others.
	_body_material = ($Meshes/Body as MeshInstance3D).get_active_material(0).duplicate()
	_body_color = _body_material.albedo_color
	_base_color = _body_color
	_eye_material = ($Meshes/Eyes as MeshInstance3D).get_active_material(0).duplicate()
	for mesh: MeshInstance3D in _meshes.get_children():
		mesh.material_override = _eye_material if mesh.name == "Eyes" else _body_material
	health.died.connect(_on_died)
	add_to_group("robots")


## Called by weapons. Returns true if this hit destroyed the robot.
## In co-op, other players' hits are sent to the host, whose robots are the real ones.
func take_damage(amount: float, hit_position: Vector3, attacker: Node = null) -> bool:
	if health.dead:
		return false
	if multiplayer.is_server():
		struck.emit(attacker)
	_body_material.albedo_color = Color.WHITE
	create_tween().tween_property(_body_material, "albedo_color", _body_color, 0.12)
	if not multiplayer.is_server():
		_net_take_damage.rpc_id(1, amount, hit_position, attacker.get_path() if attacker else NodePath())
		return false
	return health.take_damage(amount)


@rpc("any_peer", "reliable")
func _net_take_damage(amount: float, hit_position: Vector3, attacker_path: NodePath) -> void:
	take_damage(amount, hit_position, get_node_or_null(attacker_path))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or health.dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _frozen_left > 0.0:
		_frozen_left -= delta
		_set_horizontal_velocity(Vector3.ZERO)
		_windup_left = -1.0
		move_and_slide()
		if _frozen_left <= 0.0:
			_frost(false)
		return
	_cooldown_left -= delta
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = repath_interval
		target = _wander_target() if docile else _find_nearest_player()
		if target:
			_agent.target_position = target.global_position

	var flat_to_target := Vector3.ZERO
	if target:
		flat_to_target = target.global_position - global_position
		flat_to_target.y = 0.0

	if _windup_left >= 0.0:
		_windup_left -= delta
		_set_horizontal_velocity(Vector3.ZERO)
		if _windup_left < 0.0:
			_finish_attack()
	elif docile:
		if target and not _agent.is_navigation_finished():
			var stroll := _agent.get_next_path_position() - global_position
			stroll.y = 0.0
			_set_horizontal_velocity(stroll.normalized() * minf(move_speed, 1.6))
		else:
			_set_horizontal_velocity(Vector3.ZERO)
	elif target and flat_to_target.length() <= attack_range and _cooldown_left <= 0.0 and _can_attack():
		_start_attack()
		_set_horizontal_velocity(Vector3.ZERO)
	elif target and _should_hold_position(flat_to_target.length()):
		_set_horizontal_velocity(Vector3.ZERO)
	elif target and not _agent.is_navigation_finished():
		var to_next := _agent.get_next_path_position() - global_position
		to_next.y = 0.0
		var direction := (to_next.normalized() + _separation() * separation_strength).normalized()
		_set_horizontal_velocity(direction * move_speed)
	else:
		_set_horizontal_velocity(Vector3.ZERO)

	_face(flat_to_target, delta)
	move_and_slide()


## A push away from robots that are too close, so a crowd spreads out instead of
## stacking up and shoving each other along the same path.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other: Node3D in get_tree().get_nodes_in_group("robots"):
		if other == self:
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var distance := away.length()
		if distance < separation_radius and distance > 0.01:
			push += away / distance * (1.0 - distance / separation_radius)
	return push


## Coolant: stops the robot dead for a few seconds (host decides).
## Office staff mode: on, it wears a tie and minds its own business; off, it pulls out a
## weapon and goes for the players.
func set_docile(on: bool) -> void:
	docile = on
	_wander_to = null
	_repath_left = 0.0
	if Net.is_session():
		_net_dress.rpc(on)
	else:
		_net_dress(on)


func _wander_target() -> Node3D:
	if wander_points.is_empty():
		return null
	if not is_instance_valid(_wander_to) or global_position.distance_to(_wander_to.global_position) < 1.5:
		_wander_to = wander_points.pick_random()
	return _wander_to


@rpc("authority", "call_local", "reliable")
func _net_dress(on: bool) -> void:
	if on and not _meshes.has_node("Tie"):
		var tie := MeshInstance3D.new()
		tie.name = "Tie"
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.5, 0.06)
		tie.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.08, 0.1)
		tie.material_override = mat
		tie.position = Vector3(0, 1.15, -0.42)
		_meshes.add_child(tie)
	if not on and _meshes.has_node("Tie") and not _meshes.has_node("Weapon"):
		var weapon := MeshInstance3D.new()
		weapon.name = "Weapon"
		var bar := BoxMesh.new()
		bar.size = Vector3(0.12, 0.12, 0.9)
		weapon.mesh = bar
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.25, 0.25, 0.28)
		steel.metallic = 0.8
		weapon.material_override = steel
		weapon.position = Vector3(0.5, 1.0, -0.4)
		_meshes.add_child(weapon)


func freeze(seconds: float) -> void:
	if health.dead:
		return
	if _frozen_left <= 0.0:
		_frost(true)
	_frozen_left = maxf(_frozen_left, seconds)


func is_frozen() -> bool:
	return _frozen_left > 0.0


func _frost(on: bool) -> void:
	if Net.is_session():
		_net_frost.rpc(on)
	else:
		_net_frost(on)


@rpc("authority", "call_local", "reliable")
func _net_frost(on: bool) -> void:
	_body_color = Color(0.6, 0.85, 1.0) if on else _base_color
	_body_material.albedo_color = _body_color


## Robot types override these to change how they fight (see RangedRobot).
func _can_attack() -> bool:
	return true


func _should_hold_position(_distance: float) -> bool:
	return false


func _start_attack() -> void:
	_windup_left = attack_windup
	_eye_material.emission_energy_multiplier = 6.0


func _finish_attack() -> void:
	_cooldown_left = attack_cooldown
	_eye_material.emission_energy_multiplier = 1.5
	Sfx.broadcast_at(&"robot_swing", global_position + Vector3.UP, -6.0)
	if target and target.has_method("take_damage") \
			and global_position.distance_to(target.global_position) <= attack_reach:
		target.take_damage(attack_damage, global_position, self)


func _find_nearest_player() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		if player.has_method("is_targetable") and not player.is_targetable():
			continue # Downed players are left alone.
		var distance := global_position.distance_squared_to(player.global_position)
		if distance < nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _face(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _set_horizontal_velocity(horizontal: Vector3) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _on_died() -> void:
	_collision.set_deferred("disabled", true)
	Sfx.broadcast_at(&"robot_death", global_position + Vector3.UP, -3.0)
	if scrap_scene:
		ScrapPickup.drop(scrap_scene, get_tree().current_scene, global_position, scrap_value)
	died.emit(self)
	# Quick shrink as a placeholder death effect.
	var tween := create_tween()
	tween.tween_property(_meshes, "scale", Vector3(1.2, 0.05, 1.2), 0.15)
	tween.tween_callback(queue_free)
