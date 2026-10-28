class_name BoltProjectile
extends Area3D
## A slow energy bolt fired by ranged robots. Flies straight, hurts players,
## passes through other robots and fizzles on walls.

@export var lifetime := 4.0

var velocity := Vector3.ZERO
var damage := 15.0
var shooter: Node
var harmless := false ## Just for show (co-op copies of the host's bolts).


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(new_velocity: Vector3, new_damage: float, from: Node) -> void:
	velocity = new_velocity
	damage = new_damage
	shooter = from


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body is Robot or body is Warden:
		return
	if harmless:
		queue_free()
		return
	if body is Player:
		body.take_damage(damage, global_position, shooter)
	Sfx.broadcast_at(&"bolt_impact", global_position, -4.0)
	queue_free()
