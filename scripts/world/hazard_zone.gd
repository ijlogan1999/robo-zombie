class_name HazardZone
extends Area3D
## Hurts whatever stands in it: molten metal, acid, freezing coolant.
## Players are hurt by their own game; robots by the host's.

@export var damage_per_second := 25.0
@export var hurts_robots := true
@export var tick := 0.25

var _left := 0.0


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = tick
	for body in get_overlapping_bodies():
		if body is Player:
			if body.is_multiplayer_authority():
				body.take_damage(damage_per_second * tick, global_position)
		elif hurts_robots and body.has_method("take_damage") and multiplayer.is_server():
			body.take_damage(damage_per_second * tick, body.global_position)
