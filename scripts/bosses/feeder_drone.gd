class_name FeederDrone
extends CharacterBody3D
## A flying robot hauling scrap to the Kiln Mother. If it gets there, the kiln opens
## its furnace door to swallow the scrap and heals. Shoot it down first.

signal arrived(drone: FeederDrone)

@export var speed := 5.0
@export var max_health := 45.0
@export var scrap_scene: PackedScene
@export var scrap_value := 10

var target: Node3D ## Where it flies (the kiln's mouth). Host only.
var health := 0.0
var dead := false


func _ready() -> void:
	health = max_health
	add_to_group(&"boss_adds")


func _physics_process(_delta: float) -> void:
	if dead or not multiplayer.is_server() or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	if to.length() < 2.5:
		dead = true
		arrived.emit(self)
		queue_free()
		return
	velocity = to.normalized() * speed
	look_at(target.global_position, Vector3.UP)
	move_and_slide()
	# Bob a little so it reads as flying.
	$Mesh.position.y = sin(Time.get_ticks_msec() / 200.0) * 0.15


func take_damage(amount: float, _at: Vector3, _attacker: Node = null) -> bool:
	if dead:
		return false
	if not multiplayer.is_server():
		_net_damage.rpc_id(1, amount)
		return false
	health -= amount
	if health > 0.0:
		return false
	dead = true
	Sfx.broadcast_at(&"robot_death", global_position, -3.0)
	if scrap_scene:
		ScrapPickup.drop(scrap_scene, get_tree().current_scene, global_position + Vector3.DOWN * 0.5, scrap_value)
	queue_free()
	return true


@rpc("any_peer", "reliable")
func _net_damage(amount: float) -> void:
	take_damage(amount, Vector3.ZERO)
