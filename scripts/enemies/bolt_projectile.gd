class_name BoltProjectile
extends Area3D
## A slow energy bolt fired by ranged robots. Flies straight, hurts players,
## passes through other robots and fizzles on walls.

@export var lifetime := 4.0

var velocity := Vector3.ZERO
var damage := 15.0
var shooter: Node
var slow_scale := 1.0 ## Below 1: a taser bolt that slows whoever it hits.
var slow_time := 2.0
var harmless := false ## Just for show (co-op copies of the host's bolts).
var modulate_color := Color(0, 0, 0, 0) ## Set to tint the bolt.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if modulate_color.a > 0.0:
		var glow := get_node_or_null("Glow") as MeshInstance3D
		if glow:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = modulate_color
			glow.material_override = mat


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
	if body is Robot or body is Warden or body.is_in_group(&"boss_body"):
		return
	if harmless:
		queue_free()
		return
	if body is Player:
		body.take_damage(damage, global_position, shooter)
		if slow_scale < 1.0:
			body.slow(slow_scale, slow_time)
	Sfx.broadcast_at(&"bolt_impact", global_position, -4.0)
	queue_free()
