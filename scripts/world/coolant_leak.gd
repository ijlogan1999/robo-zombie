class_name CoolantLeak
extends StaticBody3D
## A cracked coolant pipe in Cold Storage. Shoot it and it bursts into a freezing cloud for
## a few seconds: robots caught in it freeze solid, players in it get frostbite. Then it
## seals itself and can be burst again a while later.
##
## The host decides when it bursts. Each game hurts its own player; the host freezes robots.

signal burst

@export var radius := 5.0
@export var burst_time := 4.0
@export var freeze_time := 4.0 ## How long a robot stays frozen after leaving the cloud.
@export var chill_damage := 12.0 ## Per second to players in the cloud.
@export var reseal_time := 20.0

var bursting := false
var sealed := true

var _left := 0.0
var _tick := 0.0
var _cloud: MeshInstance3D


func _ready() -> void:
	add_to_group(&"coolant_leaks")
	_cloud = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.4
	_cloud.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.95, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cloud.material_override = mat
	_cloud.visible = false
	add_child(_cloud)


func take_damage(_amount: float, _at: Vector3, _attacker: Node = null) -> bool:
	if not sealed:
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_shot.rpc_id(1)
		return false
	_burst()
	return false


func _burst() -> void:
	if not sealed:
		return
	if Net.is_session() and multiplayer.is_server():
		_net_burst.rpc()
	_burst_here()


func _burst_here() -> void:
	sealed = false
	bursting = true
	_left = burst_time
	_cloud.visible = true
	_cloud.global_position = global_position
	Sfx.play_at(&"gate_open", global_position, 2.0)
	burst.emit()


func _physics_process(delta: float) -> void:
	if sealed:
		return
	_left -= delta
	if bursting:
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.25
			_chill(0.25)
		if _left <= 0.0:
			bursting = false
			_cloud.visible = false
			_left = reseal_time
	elif _left <= 0.0:
		sealed = true


func _chill(step: float) -> void:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority() and player.global_position.distance_to(global_position) <= radius:
			player.take_damage(chill_damage * step, global_position, self)
			player.slip(0.3, 0.3)
	if Net.is_session() and not multiplayer.is_server():
		return
	for robot: Node in get_tree().get_nodes_in_group("robots"):
		if robot is Robot and (robot as Robot).global_position.distance_to(global_position) <= radius:
			(robot as Robot).freeze(freeze_time)


@rpc("any_peer", "reliable")
func _net_shot() -> void:
	_burst()


@rpc("authority", "reliable")
func _net_burst() -> void:
	_burst_here()
