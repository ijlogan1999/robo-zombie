class_name CableWhip
extends StaticBody3D
## A live cable hanging in Servo Works like a vine. Walk under it and it twitches, then
## lashes down and grabs you: it holds you in place and burns until you shoot it loose.
## Each game runs its own whips against its own player (like other hazards).

@export var reach := 2.6
@export var warn_time := 0.6
@export var grab_damage := 12.0
@export var hold_damage := 10.0 ## Per second while held.
@export var hold_time := 2.0
@export var regrow_time := 15.0

enum State { IDLE, WARN, HOLD, BROKEN }

var state := State.IDLE

var _left := 0.0
var _held: Player
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group(&"cable_whips")
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh:
		_mat = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D)
		if _mat:
			_mat = _mat.duplicate()
			_mesh.material_override = _mat


func _physics_process(delta: float) -> void:
	_left -= delta
	match state:
		State.IDLE:
			var player := _local_player()
			if player and _in_reach(player):
				_set_state(State.WARN, warn_time)
		State.WARN:
			_mesh_shake()
			if _left <= 0.0:
				var player := _local_player()
				if player and _in_reach(player):
					_held = player
					player.take_damage(grab_damage, global_position, self)
					_set_state(State.HOLD, hold_time)
				else:
					_set_state(State.IDLE, 0.0)
		State.HOLD:
			if not is_instance_valid(_held) or not _held.is_targetable():
				_set_state(State.IDLE, 0.0)
				return
			var to := global_position - _held.global_position
			to.y = 0.0
			_held.pull(to * 6.0 - _held.velocity * Vector3(1, 0, 1))
			_held.take_damage(hold_damage * delta, global_position, self)
			if _left <= 0.0:
				_set_state(State.IDLE, 1.5)
		State.BROKEN:
			if _left <= 0.0:
				_set_state(State.IDLE, 0.0)


## Shooting a whip snaps it (and frees whoever it's holding).
func take_damage(_amount: float, _at: Vector3, _attacker: Node = null) -> bool:
	if state == State.BROKEN:
		return false
	_set_state(State.BROKEN, regrow_time)
	return true


func _set_state(new_state: State, time: float) -> void:
	state = new_state
	_left = time
	if new_state != State.HOLD:
		_held = null
	if _mesh:
		_mesh.visible = new_state != State.BROKEN
		_mesh.position = Vector3.ZERO
	if _mat:
		_mat.emission_energy_multiplier = 4.0 if new_state in [State.WARN, State.HOLD] else 0.8
	($Shape as CollisionShape3D).set_deferred("disabled", new_state == State.BROKEN)


func _mesh_shake() -> void:
	if _mesh:
		_mesh.position = Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08))


func _in_reach(player: Player) -> bool:
	var flat := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	var below := global_position.y - player.global_position.y
	return flat.length() <= reach and below > 0.0 and below < 6.0 and player.is_targetable()


func _local_player() -> Player:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority():
			return player
	return null
