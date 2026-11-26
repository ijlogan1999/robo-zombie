class_name Boss
extends Node3D
## A section boss. Something starts the fight (a lever, an Easter egg step); while it runs
## the rounds hold still. Health scales with the number of players.
##
## Boss rule: a boss can be beaten without its Easter egg step done first. Then it drops
## nothing and comes back for a rematch 2 rounds later. Beaten with the step done, it drops
## its egg item (sets drop_flag) and stays down.
##
## Only the host runs the fight. Subclasses pack what the other players need to see into
## an array that's sent a few times a second.

signal started
signal defeated(dropped: bool)

const PLAYER_HEALTH_SCALE := [1.0, 1.0, 1.75, 2.5, 3.25] ## By player count (1-4).
const SYNC_INTERVAL := 0.1

@export var display_name := "BOSS"
@export var requires_flag: StringName ## Egg step that has to be done for the drop.
@export var drop_flag: StringName ## Set when it's beaten with the step done.
@export var drop_text := "" ## Banner when it drops its item.
@export var rematch_rounds := 2

var active := false
var beaten := false ## Beaten with the drop; it stays down for the run.
var rematch_in := -1 ## Rounds until it can be fought again, or -1.
var bar_max := 1.0
var bar_value := 1.0
var phase_name := ""

var _sync_left := 0.0


func _ready() -> void:
	add_to_group("boss")
	_connect_rounds.call_deferred() # The round manager may not be ready yet.


func can_start() -> bool:
	return not active and not beaten and rematch_in < 0


## Starts the fight. Anyone may call it; it's passed to the host.
func start() -> bool:
	if not can_start():
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_request_start.rpc_id(1)
		return true
	active = true
	var rounds := _rounds()
	if rounds:
		rounds.hold(self)
		rounds.announce("%s AWAKENS" % display_name)
	_begin()
	started.emit()
	if Net.is_session():
		_net_started.rpc()
	return true


## Number to multiply boss health by for the players in the game.
func health_scale() -> float:
	var count := clampi(get_tree().get_nodes_in_group("players").size(), 1, 4)
	return PLAYER_HEALTH_SCALE[count]


func bar_title() -> String:
	return display_name if phase_name == "" else "%s  -  %s" % [display_name, phase_name]


## Subclasses call this when the last phase dies. Host only.
func finish() -> void:
	if not active:
		return
	active = false
	var dropped := Egg.has(requires_flag)
	var rounds := _rounds()
	if rounds:
		rounds.release(self)
	if dropped:
		beaten = true
		Egg.set_flag(drop_flag)
		if rounds:
			rounds.announce(drop_text if drop_text != "" else "%s DESTROYED" % display_name)
	else:
		rematch_in = rematch_rounds
		if rounds:
			rounds.announce("%s FELL, BUT DROPPED NOTHING. IT WILL BE BACK" % display_name)
	_end(dropped)
	defeated.emit(dropped)
	if Net.is_session():
		_net_finished.rpc(dropped, rematch_in)


func _physics_process(delta: float) -> void:
	if not active or (Net.is_session() and not multiplayer.is_server()):
		return
	_fight(delta)
	if Net.is_session():
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_net_state.rpc(_pack())


func _on_round_ended(_number: int) -> void:
	if rematch_in < 0:
		return
	rematch_in -= 1
	if rematch_in <= 0:
		rematch_in = -1
		_reset()
		var rounds := _rounds()
		if rounds and multiplayer.is_server():
			rounds.announce("%s STIRS AGAIN" % display_name)


func _connect_rounds() -> void:
	var rounds := _rounds()
	if rounds and not rounds.round_ended.is_connected(_on_round_ended):
		rounds.round_ended.connect(_on_round_ended)


func _rounds() -> RoundManager:
	return get_tree().get_first_node_in_group("round_manager") as RoundManager


# --- For subclasses -----------------------------------------------------------------------

func _begin() -> void:
	pass


func _fight(_delta: float) -> void:
	pass


func _end(_dropped: bool) -> void:
	pass


## Back to sleep, ready for a rematch.
func _reset() -> void:
	pass


func _pack() -> Array:
	return [bar_max, bar_value, phase_name]


func _unpack(state: Array) -> void:
	bar_max = state[0]
	bar_value = state[1]
	phase_name = state[2]


# --- Shared helpers (bosses are greybox, built in code) ---------------------------------

func _nearest_player(from: Vector3) -> Player:
	var best: Player = null
	var best_d := INF
	for player: Player in get_tree().get_nodes_in_group("players"):
		if not player.is_targetable():
			continue
		var d := from.distance_squared_to(player.global_position)
		if d < best_d:
			best = player
			best_d = d
	return best


func _rounds_announce(text: String) -> void:
	var rounds := _rounds()
	if rounds:
		rounds.announce(text)


func _part(parent: Node3D, size: Vector3, color: Color, hp: float, glow := false) -> BossPart:
	var part := BossPart.new()
	part.max_health = hp
	parent.add_child(part)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	part.add_child(shape)
	var mesh := _box(part, size, color, glow)
	mesh.name = "Mesh"
	return part


func _box(parent: Node, size: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 2.5
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


func _sphere(parent: Node, radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


func _stomp(at: Vector3, reach: float, damage: float) -> void:
	Sfx.broadcast_at(&"robot_swing", at + Vector3.UP, 4.0)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_targetable() and player.global_position.distance_to(at) <= reach:
			player.take_damage(damage, at, self)
	_shockwave(at, reach)
	if Net.is_session():
		_net_shockwave.rpc(at, reach)


func _shockwave(at: Vector3, reach: float) -> void:
	var ring := _box(self, Vector3(reach * 2.0, 0.1, reach * 2.0), Color(1, 0.6, 0.2, 0.4), true)
	(ring.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.global_position = Vector3(at.x, global_position.y + 0.1, at.z)
	get_tree().create_timer(0.3, false).timeout.connect(ring.queue_free)


# --- Network ------------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _net_request_start() -> void:
	start()


@rpc("authority", "reliable")
func _net_started() -> void:
	active = true
	_begin()
	started.emit()


@rpc("authority", "reliable")
func _net_finished(dropped: bool, rematch: int) -> void:
	active = false
	beaten = dropped
	rematch_in = rematch
	_end(dropped)
	defeated.emit(dropped)


@rpc("authority", "unreliable_ordered")
func _net_state(state: Array) -> void:
	_unpack(state)


@rpc("authority", "unreliable")
func _net_shockwave(at: Vector3, reach: float) -> void:
	_shockwave(at, reach)
