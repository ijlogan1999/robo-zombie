class_name RangedRobot
extends Robot
## Keeps its distance and fires slow, glowing bolts that players can dodge.
## It needs a clear line to its target; without one it walks closer.

@export var projectile_scene: PackedScene
@export var projectile_speed := 16.0
@export var hold_distance := 12.0 ## Stops walking once this close with a clear shot.

@onready var _muzzle: Node3D = $Muzzle


func _can_attack() -> bool:
	return has_line_of_sight()


func _should_hold_position(distance: float) -> bool:
	return distance <= hold_distance and has_line_of_sight()


func has_line_of_sight() -> bool:
	if not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters3D.create(_muzzle.global_position, _aim_point())
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


func _finish_attack() -> void:
	_cooldown_left = attack_cooldown
	_eye_material.emission_energy_multiplier = 1.5
	if projectile_scene == null or not has_line_of_sight():
		return
	Sfx.broadcast_at(&"bolt_fire", _muzzle.global_position)
	var bolt: BoltProjectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = _muzzle.global_position
	var bolt_velocity := (_aim_point() - _muzzle.global_position).normalized() * projectile_speed
	bolt.launch(bolt_velocity, attack_damage, self)
	if Net.is_session():
		_net_show_bolt.rpc(_muzzle.global_position, bolt_velocity)


## Co-op copies get a harmless bolt to look at. The host's bolt does the damage.
@rpc("authority", "unreliable")
func _net_show_bolt(from: Vector3, bolt_velocity: Vector3) -> void:
	if projectile_scene == null:
		return
	var bolt: BoltProjectile = projectile_scene.instantiate()
	bolt.harmless = true
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.launch(bolt_velocity, 0.0, self)


func _aim_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.1 # Chest height.
