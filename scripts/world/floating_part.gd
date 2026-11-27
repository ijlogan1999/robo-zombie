class_name FloatingPart
extends AnimatableBody3D
## A car body or door panel bobbing in a dip tank. It drifts back and forth, so players can
## hop across the tank on it. Every game drifts its own copy on the same clock.

@export var travel := Vector3(8, 0, 0)
@export var period := 7.0
@export var bob := 0.12

var _home := Vector3.ZERO


func _ready() -> void:
	_home = position
	sync_to_physics = true


func _physics_process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var along := 0.5 - 0.5 * cos(TAU * t / period)
	position = _home + travel * along + Vector3.UP * sin(t * 2.1) * bob
