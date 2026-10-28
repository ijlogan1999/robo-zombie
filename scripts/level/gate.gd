class_name Gate
extends StaticBody3D
## A junk barricade in the doorway between two rooms, Zombies-style.
## Any player can pay to clear it, which opens the room behind it.

signal opened

@export var cost := 100
@export var room_name := "???" ## The room behind the gate, shown on its signs.

var is_open := false
var use_sound := &"" ## Opening plays its own sound.

@onready var _barricade: Node3D = $Barricade


func _ready() -> void:
	var text := "%s\n%d" % [room_name.to_upper(), cost]
	$Barricade/SignFront.text = text
	$Barricade/SignBack.text = text


func get_prompt(_player: Player) -> String:
	return "" if is_open else "[E] Clear the way to %s  -  %d scrap" % [room_name, cost]


func interact(player: Player) -> bool:
	if is_open or not player.try_spend(cost):
		return false
	open()
	return true


## Opens the gate in everyone's game.
func open() -> void:
	if is_open:
		return
	if Net.is_session():
		_net_open.rpc()
	_open_here()


@rpc("any_peer", "reliable")
func _net_open() -> void:
	_open_here()


func _open_here() -> void:
	if is_open:
		return
	is_open = true
	Sfx.play_at(&"gate_open", global_position + Vector3.UP * 1.5)
	$CollisionShape3D.set_deferred("disabled", true)
	# The junk sinks into the floor.
	var tween := create_tween()
	tween.tween_property(_barricade, "position:y", -4.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_barricade.hide)
	opened.emit()
