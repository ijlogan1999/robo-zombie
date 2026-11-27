class_name Bug
extends Robot
## Servo Works' unique robot: a tiny insect drone. Weak alone, but they come in clouds
## (the round manager spawns a whole swarm at once) and nibble fast.

@export var swarm_size := 5


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Buzz up and down a little so a swarm reads as flying.
	_meshes.position.y = sin(Time.get_ticks_msec() / 90.0 + get_instance_id()) * 0.12
