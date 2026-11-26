class_name EggSocket
extends StaticBody3D
## A spot where an Easter egg item goes: a socket, a slot, a rack. Holding the item it
## needs (an Egg flag), use it to install the item. That sets another flag for everyone.

signal installed

@export var needs_flag: StringName ## The item players have to be carrying.
@export var sets_flag: StringName
@export var item_name := "part"
@export var install_text := "[E] Install the %s"
@export var missing_text := "Needs a %s"
@export var done_text := "" ## Shown once installed ("" = no prompt).

@onready var _lit: Node3D = get_node_or_null("Lit")


func _ready() -> void:
	Egg.flag_set.connect(func(_f: StringName) -> void: _update())
	_update()


func is_installed() -> bool:
	return Egg.has(sets_flag) and sets_flag != &""


func get_prompt(_player: Player) -> String:
	if is_installed():
		return done_text
	if not Egg.has(needs_flag):
		return missing_text % item_name
	return install_text % item_name


func interact(_player: Player) -> bool:
	if is_installed() or not Egg.has(needs_flag):
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_install.rpc_id(1)
		return true
	_install()
	return true


func _install() -> void:
	if is_installed():
		return
	Egg.set_flag(sets_flag)
	Sfx.broadcast_at(&"gate_open", global_position + Vector3.UP, 0.0)
	installed.emit()


func _update() -> void:
	if _lit:
		_lit.visible = is_installed()


@rpc("any_peer", "reliable")
func _net_install() -> void:
	_install()
