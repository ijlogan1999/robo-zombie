class_name Thawed
extends Robot
## Cold Storage's unique robot: old stock left on the shelves, frozen in a block of ice.
## It wakes when a player comes close, when it's shot, or when it's waited long enough.
## Then it cracks free, hops off its shelf and comes after the players.
##
## The round spawner drops it near players like any robot. It then takes the nearest free
## shelf spot (Marker3Ds in the "cold_shelf_spots" group) and freezes there.

const SHELF_GROUP := &"cold_shelf_spots"

@export var wake_range := 7.0
@export var patience := 25.0 ## Seconds before it wakes on its own.
@export var shelf_search := 30.0
@export var hop_speed := 3.5
@export var hop_height := 4.5

var asleep := true

var _patience_left := 0.0
var _hop_left := 0.0
var _ice: Node3D


func _ready() -> void:
	super._ready()
	_patience_left = patience
	_ice = get_node_or_null("Ice")
	if multiplayer.is_server():
		_take_shelf()


func take_damage(amount: float, hit_position: Vector3, attacker: Node = null) -> bool:
	if asleep and multiplayer.is_server() and not health.dead:
		_wake()
		amount *= 0.5 # The ice took some of it.
	return super.take_damage(amount, hit_position, attacker)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or health.dead:
		return
	if asleep:
		_patience_left -= delta
		_set_horizontal_velocity(Vector3.ZERO)
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		var player := _find_nearest_player()
		if _patience_left <= 0.0 or (player and player.global_position.distance_to(global_position) <= wake_range):
			_wake()
		return
	if _hop_left > 0.0:
		_hop_left -= delta
		velocity.y -= _gravity * delta
		move_and_slide()
		return
	super._physics_process(delta)


func _take_shelf() -> void:
	var best: Node3D = null
	var best_d := shelf_search * shelf_search
	for spot: Node3D in get_tree().get_nodes_in_group(SHELF_GROUP):
		if spot.has_meta("holder") and is_instance_valid(spot.get_meta("holder")):
			continue
		var d := spot.global_position.distance_squared_to(global_position)
		if d < best_d and _spot_open(spot):
			best = spot
			best_d = d
	if best == null:
		_wake() # No shelf nearby: it was already thawed.
		return
	best.set_meta("holder", self)
	global_position = best.global_position
	rotation.y = best.global_rotation.y


## Only shelves in open bays (so it can't wake up behind a shut gate).
func _spot_open(spot: Node3D) -> bool:
	var section := Section.containing(spot)
	if section == null:
		return true
	var room := section.room_at_position(spot.global_position)
	return room != null and room.is_open


func _wake() -> void:
	if not asleep:
		return
	asleep = false
	_show_ice(false)
	if Net.is_session():
		_net_ice.rpc(false)
	# Hop off the shelf: forward (the shelf spot faces the aisle), up, and toward the nearest player.
	var forward := -global_basis.z
	var player := _find_nearest_player()
	if player:
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			forward = (forward + to.normalized()).normalized()
	velocity = forward * hop_speed + Vector3.UP * hop_height
	_hop_left = 0.9
	Sfx.broadcast_at(&"gate_open", global_position + Vector3.UP, -4.0)


func _show_ice(on: bool) -> void:
	if _ice:
		_ice.visible = on


@rpc("authority", "reliable")
func _net_ice(on: bool) -> void:
	asleep = on
	_show_ice(on)
