class_name SectionDoor
extends StaticBody3D
## A big door out of a section. Pay once to unlock it for everyone, then use it to travel.
## Doors can be locked by the Easter egg or a boss until something calls unlock().

signal unlocked

@export var destination_name := "Somewhere"
@export var arrival_id: StringName
@export var cost := 1000
@export var locked := false ## Needs something other than scrap first.
@export var locked_reason := "Sealed"

var is_open := false


func _ready() -> void:
	_update_sign()


func get_prompt(_player: Player) -> String:
	if locked:
		return "%s  -  %s" % [destination_name, locked_reason]
	if not is_open:
		return "[E] Open the way to %s  -  %d scrap" % [destination_name, cost]
	return "[E] Go to %s" % destination_name


func interact(player: Player) -> bool:
	if locked:
		return false
	if not is_open:
		if not player.try_spend(cost):
			return false
		open()
		return true
	return Arrival.send(player, arrival_id)


func open() -> void:
	if Net.is_session():
		_net_open.rpc()
	_open_here()


func unlock() -> void:
	locked = false
	_update_sign()
	unlocked.emit()


@rpc("any_peer", "reliable")
func _net_open() -> void:
	_open_here()


func _open_here() -> void:
	if is_open:
		return
	is_open = true
	Sfx.play_at(&"gate_open", global_position + Vector3.UP * 1.5)
	_update_sign()


func _update_sign() -> void:
	var sign := get_node_or_null("Sign") as Label3D
	if sign:
		sign.text = destination_name.to_upper() + ("" if is_open or locked else "\n%d" % cost)
