class_name IcePatch
extends Area3D
## Frost on the Cold Storage floor. While you stand on it you can barely grip: you keep
## sliding the way you were going and turning takes a while. Each game runs its own player.

@export var grip := 0.12 ## 1 = normal floor.


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is Player and body.is_multiplayer_authority() and body.is_on_floor():
			body.slip(grip, 0.25)
