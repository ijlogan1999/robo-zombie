class_name Conveyor
extends Area3D
## A running belt on the Line. Stand on it and it carries you along (toward the giant).
## Each game moves its own player.

@export var speed := 3.0
@export var direction := Vector3(0, 0, -1) ## Local direction the belt runs.


func _physics_process(_delta: float) -> void:
	if not monitoring:
		return
	var push := global_basis * direction.normalized() * speed
	push.y = 0.0
	for body in get_overlapping_bodies():
		if body is Player and body.is_multiplayer_authority() and body.is_on_floor():
			body.pull(push)
