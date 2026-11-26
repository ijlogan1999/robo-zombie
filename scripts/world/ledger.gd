class_name Ledger
extends StaticBody3D
## QUOTA's Ledger: the book of every robot on staff. Taking it sets Accounting off. With
## the Staff Bot awake and following the team, they enter it on the payroll first, which
## clears it to walk them into Head Office.

@export var item_flag: StringName = &"ledger"
@export var staff_bot_flag: StringName = &"staff_bot_awake"
@export var clearance_flag: StringName = &"staff_bot_cleared"

@onready var _book: Node3D = get_node_or_null("Book")


func _ready() -> void:
	Egg.flag_set.connect(func(_f: StringName) -> void: _update())
	_update()


func get_prompt(_player: Player) -> String:
	if Egg.has(item_flag):
		return ""
	if Egg.has(staff_bot_flag):
		return "[E] Enter the Staff Bot in QUOTA's Ledger"
	return "[E] Take QUOTA's Ledger"


func interact(_player: Player) -> bool:
	if Egg.has(item_flag):
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_take.rpc_id(1)
		return true
	_take()
	return true


func _take() -> void:
	if Egg.has(item_flag):
		return
	if Egg.has(staff_bot_flag):
		Egg.set_flag(clearance_flag)
	Egg.set_flag(item_flag)
	Sfx.broadcast_at(&"gate_open", global_position + Vector3.UP, 0.0)
	var office := get_tree().get_first_node_in_group("accounting_office") as AccountingOffice
	if office:
		office.trigger()


func _update() -> void:
	if _book:
		_book.visible = not Egg.has(item_flag)


@rpc("any_peer", "reliable")
func _net_take() -> void:
	_take()
