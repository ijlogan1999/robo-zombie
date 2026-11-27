class_name LandMine
extends Area3D
## A training mine. Step on it (player or robot) and it beeps, then blows. Every game
## blows its own copy and hurts its own player; the host hurts robots. It re-arms a while
## later.

@export var fuse := 0.6
@export var radius := 3.5
@export var damage := 40.0
@export var rearm_time := 12.0

var armed := true

var _fuse_left := -1.0
var _rearm_left := 0.0
var _light: MeshInstance3D


func _ready() -> void:
	add_to_group(&"land_mines")
	_light = get_node_or_null("Light") as MeshInstance3D
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if armed and _fuse_left < 0.0 and (body is Player or body is Robot):
		_fuse_left = fuse
		Sfx.play_at(&"robot_swing", global_position, -6.0)


func _physics_process(delta: float) -> void:
	if not armed:
		_rearm_left -= delta
		if _rearm_left <= 0.0:
			armed = true
			visible = true
		return
	if _fuse_left >= 0.0:
		_fuse_left -= delta
		if _light:
			_light.visible = int(_fuse_left * 12.0) % 2 == 0
		if _fuse_left < 0.0:
			_blow()


func _blow() -> void:
	armed = false
	visible = false
	_rearm_left = rearm_time
	Sfx.play_at(&"gate_open", global_position, 6.0)
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_multiplayer_authority() and p.global_position.distance_to(global_position) <= radius:
			p.take_damage(damage, global_position, self)
	if not Net.is_session() or multiplayer.is_server():
		for r in get_tree().get_nodes_in_group("robots"):
			if r is Robot and (r as Robot).global_position.distance_to(global_position) <= radius:
				(r as Robot).take_damage(damage * 2.0, global_position)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.6, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = global_position
	get_tree().create_timer(0.25, false).timeout.connect(flash.queue_free)
