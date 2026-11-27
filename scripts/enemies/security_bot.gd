class_name SecurityBot
extends RangedRobot
## One of the Shipping Bay's unique robots: yard security with a flashlight and a taser.
## Its taser bolts slow whoever they hit for a couple of seconds.

@export var taser_slow := 0.5
@export var taser_time := 2.5


func _finish_attack() -> void:
	_cooldown_left = attack_cooldown
	_eye_material.emission_energy_multiplier = 1.5
	if projectile_scene == null or not has_line_of_sight():
		return
	Sfx.broadcast_at(&"bolt_fire", _muzzle.global_position)
	var bolt: BoltProjectile = projectile_scene.instantiate()
	bolt.slow_scale = taser_slow
	bolt.slow_time = taser_time
	bolt.modulate_color = Color(1.0, 0.95, 0.3)
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = _muzzle.global_position
	var bolt_velocity := (_aim_point() - _muzzle.global_position).normalized() * projectile_speed
	bolt.launch(bolt_velocity, attack_damage, self)
	if Net.is_session():
		_net_show_bolt.rpc(_muzzle.global_position, bolt_velocity)
