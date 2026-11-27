class_name BossPart
extends StaticBody3D
## A piece of a boss that can be shot: a valve, a door, a pipe. Hits are passed to the boss,
## which decides what they do. Other players' hits go to the host.

signal hit(part: BossPart, amount: float, at: Vector3)

@export var max_health := 100.0
@export var armored := false ## Takes no damage right now (closed door, hot shell).

var health := 0.0
var broken := false


func _ready() -> void:
	health = max_health


func take_damage(amount: float, at: Vector3, _attacker: Node = null) -> bool:
	if broken or armored:
		_flash(Color(0.6, 0.6, 0.6))
		return false
	_flash(Color.WHITE)
	if Net.is_session() and not multiplayer.is_server():
		_net_hit.rpc_id(1, amount, at)
		return false
	hit.emit(self, amount, at)
	return broken


func reset(new_max := -1.0) -> void:
	if new_max > 0.0:
		max_health = new_max
	health = max_health
	broken = false


@rpc("any_peer", "reliable")
func _net_hit(amount: float, at: Vector3) -> void:
	take_damage(amount, at)


func _flash(color: Color) -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		if not mi.has_meta("base_color"):
			mi.set_meta("base_color", mat.albedo_color)
		mat.albedo_color = color
		create_tween().tween_property(mat, "albedo_color", mi.get_meta("base_color"), 0.1)
