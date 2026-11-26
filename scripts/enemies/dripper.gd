class_name Dripper
extends Robot
## The Chassis Yard's unique robot: a half-coated chassis that climbed out of a dip tank
## still dripping oil. It leaves a trail, and the trail catches fire behind it.

@export var drip_every := 2.0 ## Metres walked between drips.
@export var ignite_after := 1.5
@export var burn_time := 4.0
@export var fire_damage := 25.0
@export var oil_material: Material
@export var fire_material: Material

var _walked := 0.0
var _last := Vector3.ZERO


func _ready() -> void:
	super._ready()
	_last = global_position


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not multiplayer.is_server() or health.dead or not is_on_floor():
		_last = global_position
		return
	_walked += global_position.distance_to(_last)
	_last = global_position
	if _walked >= drip_every:
		_walked = 0.0
		_drip(global_position)
		if Net.is_session():
			_net_drip.rpc(global_position)


@rpc("authority", "reliable")
func _net_drip(at: Vector3) -> void:
	_drip(at)


## A patch of oil that lights up a moment later. Each game makes its own (hazards hurt
## each player in their own game), and it outlives the robot.
func _drip(at: Vector3) -> void:
	var patch := HazardZone.new()
	patch.damage_per_second = 0.0
	patch.hurts_robots = false
	patch.add_to_group(&"oil_patches")
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.0
	cylinder.height = 1.0
	shape.shape = cylinder
	shape.position.y = 0.5
	patch.add_child(shape)
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	mesh.mesh = disc
	mesh.material_override = oil_material
	mesh.position.y = 0.03
	patch.add_child(mesh)
	get_tree().current_scene.add_child(patch)
	patch.global_position = at
	var tree := get_tree()
	tree.create_timer(ignite_after, false).timeout.connect(func() -> void:
		if not is_instance_valid(patch):
			return
		patch.damage_per_second = fire_damage
		mesh.material_override = fire_material
		mesh.scale = Vector3(1, 6, 1)
		tree.create_timer(burn_time, false).timeout.connect(patch.queue_free))
