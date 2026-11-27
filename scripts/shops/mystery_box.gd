class_name MysteryBox
extends StaticBody3D
## A Zombies-style crate that hands out a random gun, and moves around the map.
##
## It sits on one of the "box_spot" markers that rooms carry, so spots survive the shuffle.
## After a random 4 to 8 rolls, QUOTA recalls it: that roll is refunded and the crate
## moves to another spot. Every player's game keeps the same count and picks the same
## next spot, because each roll is sent to everyone and the spots come from the layout seed.

signal moved(spot: Node3D)

const SPOT_GROUP := &"box_spot"

@export var cost := 950
@export var weapons: Array[WeaponData] = []
@export var min_rolls := 4
@export var max_rolls := 8

var spot_index := -1
var rolls_left := 0
var recalled := false ## True for a moment after a recall, while the sign says so.

var _rng := RandomNumberGenerator.new()
var _spots: Array[Node3D] = []


func _ready() -> void:
	_setup.call_deferred()


func _setup() -> void:
	for node in get_tree().get_nodes_in_group(SPOT_GROUP):
		_spots.append(node as Node3D)
	# Same order in every game: by room name, then spot name.
	_spots.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return str(a.get_path()).naturalnocasecmp_to(str(b.get_path())) < 0)
	var section := get_tree().get_first_node_in_group("section") as Section
	_rng.seed = (section.used_seed if section else 1) + 7
	if _spots.is_empty():
		hide()
		$CollisionShape3D.disabled = true
		return
	_go_to(_rng.randi_range(0, _spots.size() - 1))
	rolls_left = _rng.randi_range(min_rolls, max_rolls)
	_update_sign()


func spots() -> Array[Node3D]:
	return _spots


func get_prompt(_player: Player) -> String:
	if recalled:
		return ""
	return "[E] Mystery crate  -  %d scrap" % cost


func interact(player: Player) -> bool:
	if recalled or not player.try_spend(cost):
		return false
	if rolls_left <= 0:
		player.add_scrap(cost)
		_roll(true)
		if Net.is_session():
			_net_roll.rpc(true)
		return true
	var gun := _pick_gun(player)
	if gun:
		player.weapon_holder.give_weapon(gun)
	Sfx.play_at(&"buy", global_position)
	_roll(false)
	if Net.is_session():
		_net_roll.rpc(false)
	return true


## A gun the player doesn't already carry, if there is one.
func _pick_gun(player: Player) -> WeaponData:
	var choices: Array[WeaponData] = []
	for gun in weapons:
		if not player.weapon_holder.owns(gun):
			choices.append(gun)
	if choices.is_empty():
		choices = weapons.duplicate()
	if choices.is_empty():
		return null
	return choices[randi() % choices.size()]


@rpc("any_peer", "reliable")
func _net_roll(was_recall: bool) -> void:
	_roll(was_recall)


func _roll(was_recall: bool) -> void:
	if not was_recall:
		rolls_left -= 1
		return
	# QUOTA takes the crate back. It turns up somewhere else.
	recalled = true
	$Sign.text = "RECALLED\nBY QUOTA"
	var next := spot_index
	if _spots.size() > 1:
		while next == spot_index:
			next = _rng.randi_range(0, _spots.size() - 1)
	rolls_left = _rng.randi_range(min_rolls, max_rolls)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(func() -> void:
		recalled = false
		_go_to(next)
		_update_sign())


func _go_to(index: int) -> void:
	spot_index = index
	global_transform = _spots[index].global_transform
	moved.emit(_spots[index])


func _update_sign() -> void:
	$Sign.text = "MYSTERY CRATE\n%d" % cost
