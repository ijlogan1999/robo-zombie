class_name ScrapPickup
extends Area3D
## Scrap dropped by destroyed robots. It lies on the ground for a long time, and walking
## over it pays every player the full amount (shared pickups, separate wallets).
##
## New drops merge into a pile close by instead of making another one, and the total
## number of piles is capped, so big waves don't flood the level with objects.

const MERGE_RADIUS := 2.0
const MAX_PILES := 80
const BLINK_TIME := 10.0 ## Blinks this long before disappearing.

@export var lifetime := 120.0

var amount := 10:
	set(value):
		amount = value
		if is_node_ready():
			_update_size() # Co-op copies get new amounts from the host.

var _age := 0.0

@onready var _visual: Node3D = $Visual


## Drops scrap at a spot, merging it into a nearby pile when there is one.
## Goes in the level's "spawn_root" when there is one, so co-op players all see it.
static func drop(scene: PackedScene, parent: Node, at: Vector3, value: int) -> void:
	var spawn_root := parent.get_tree().get_first_node_in_group("spawn_root")
	if spawn_root:
		parent = spawn_root
	var piles := parent.get_tree().get_nodes_in_group("scrap_piles")
	for pile: ScrapPickup in piles:
		if pile.global_position.distance_to(at) <= MERGE_RADIUS:
			pile.add_amount(value)
			return
	if piles.size() >= MAX_PILES:
		piles.front().queue_free()
	var pile: ScrapPickup = scene.instantiate()
	pile.amount = value
	pile.position = at # The parent sits at the world origin.
	parent.add_child(pile, true)


func _ready() -> void:
	add_to_group("scrap_piles")
	body_entered.connect(_on_body_entered)
	_update_size()


func add_amount(value: int) -> void:
	amount += value
	_age = 0.0


func _process(delta: float) -> void:
	_age += delta
	_visual.rotate_y(1.5 * delta)
	_visual.position.y = 0.15 + sin(_age * 3.0) * 0.05
	var time_left := lifetime - _age
	_visual.visible = time_left > BLINK_TIME or fmod(_age, 0.4) < 0.25
	if time_left <= 0.0 and multiplayer.is_server():
		queue_free()


func _update_size() -> void:
	# Bigger piles look bigger, with diminishing growth.
	var size := clampf(1.0 + log(amount / 10.0) * 0.35, 1.0, 2.5)
	_visual.scale = Vector3.ONE * size


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server() or not body is Player:
		return
	for player: Player in get_tree().get_nodes_in_group("players"):
		player.add_scrap(amount)
	Sfx.broadcast_at(&"scrap", global_position, -4.0)
	remove_from_group("scrap_piles")
	queue_free()
