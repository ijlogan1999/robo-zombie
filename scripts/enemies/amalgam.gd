class_name Amalgam
extends Robot
## The Line's unique robot: something the giant bolted together from parts off the belt.
## Each one gets two random traits from other sections' robots:
## plated (tough), quick, burning (leaves molten scorch marks) or splitter (bursts into Bugs).

enum { PLATED = 1, QUICK = 2, BURNING = 4, SPLITTER = 8 }
const TRAITS := [PLATED, QUICK, BURNING, SPLITTER]
const BUG := preload("res://scenes/enemies/bug.tscn")

@export var traits := 0 ## Picked by the host; synced at spawn.
@export var scorch_every := 3.0
@export var scorch_time := 3.0
@export var scorch_damage := 20.0
@export var split_count := 3

var _walked := 0.0
var _last := Vector3.ZERO


func _ready() -> void:
	if multiplayer.is_server() and traits == 0:
		var picks := TRAITS.duplicate()
		picks.shuffle()
		traits = picks[0] | picks[1]
	super._ready()
	if multiplayer.is_server():
		if traits & PLATED:
			health.max_health *= 2.0
			health.health = health.max_health
		if traits & QUICK:
			move_speed = minf(move_speed * 1.5, max_speed)
	_last = global_position
	_dress()


func _dress() -> void:
	var tint := Color(0.5, 0.5, 0.5)
	if traits & PLATED:
		tint = tint.lerp(Color(0.35, 0.33, 0.3), 0.6)
		_meshes.scale = Vector3(1.2, 1.15, 1.2)
	if traits & QUICK:
		tint = tint.lerp(Color(0.85, 0.8, 0.2), 0.5)
	if traits & BURNING:
		tint = tint.lerp(Color(1.0, 0.4, 0.1), 0.6)
	if traits & SPLITTER:
		tint = tint.lerp(Color(0.2, 0.6, 0.25), 0.6)
	_body_color = tint
	_base_color = tint
	_body_material.albedo_color = tint


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or health.dead or not (traits & BURNING) or not is_on_floor():
		_last = global_position
		return
	_walked += global_position.distance_to(_last)
	_last = global_position
	if _walked >= scorch_every:
		_walked = 0.0
		if Net.is_session():
			_net_scorch.rpc(global_position)
		_scorch(global_position)


func _on_died() -> void:
	if multiplayer.is_server() and traits & SPLITTER:
		var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
		if rounds:
			for i in split_count:
				rounds.spawn_add.call_deferred(BUG, global_position + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)))
	super._on_died()


@rpc("authority", "reliable")
func _net_scorch(at: Vector3) -> void:
	_scorch(at)


## A molten scorch mark that burns for a few seconds. Each game makes its own.
func _scorch(at: Vector3) -> void:
	var patch := HazardZone.new()
	patch.damage_per_second = scorch_damage
	patch.hurts_robots = false
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.9
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position.y = 0.5
	patch.add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.05
	mesh.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.position.y = 0.03
	patch.add_child(mesh)
	get_tree().current_scene.add_child(patch)
	patch.global_position = at
	get_tree().create_timer(scorch_time, false).timeout.connect(patch.queue_free)
