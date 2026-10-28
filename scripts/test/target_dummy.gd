class_name TargetDummy
extends StaticBody3D
## Shootable practice target. Flashes and shows damage numbers when hit,
## then respawns a moment after being destroyed. Stand-in until robots exist.

@export var max_health := 100.0
@export var respawn_time := 2.0

var health := 0.0

var _material: StandardMaterial3D
var _base_color: Color

@onready var _meshes: Node3D = $Meshes
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _health_label: Label3D = $HealthLabel


func _ready() -> void:
	# One shared material per dummy so only the dummy that was hit flashes.
	_material = ($Meshes/Body as MeshInstance3D).get_active_material(0).duplicate()
	_base_color = _material.albedo_color
	for mesh: MeshInstance3D in _meshes.get_children():
		mesh.material_override = _material
	_reset()


## Returns true if this hit destroyed the dummy.
func take_damage(amount: float, hit_position: Vector3, _attacker: Node = null) -> bool:
	if health <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	_health_label.text = str(ceili(health))
	_spawn_damage_number(amount, hit_position)

	_material.albedo_color = Color.WHITE
	create_tween().tween_property(_material, "albedo_color", _base_color, 0.15)

	if health > 0.0:
		return false
	_meshes.visible = false
	_health_label.visible = false
	_collision.set_deferred("disabled", true)
	get_tree().create_timer(respawn_time).timeout.connect(_reset)
	return true


func _reset() -> void:
	health = max_health
	_meshes.visible = true
	_health_label.visible = true
	_health_label.text = str(ceili(health))
	_collision.set_deferred("disabled", false)


func _spawn_damage_number(amount: float, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1.0, 0.9, 0.4)
	get_tree().current_scene.add_child(label)
	label.global_position = at + Vector3(randf_range(-0.2, 0.2), 0.2, 0.0)

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.8, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(label.queue_free)
