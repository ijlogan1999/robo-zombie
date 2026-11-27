extends Node
## The main Easter egg's progress for this run: a set of named flags, one per step or item
## ("grab_magnet", "kiln_heart_left"...). The host sets flags; everyone gets a copy.

signal flag_set(flag: StringName)

var flags := {}


func has(flag: StringName) -> bool:
	return flag == &"" or flags.has(flag)


func set_flag(flag: StringName) -> void:
	if flag == &"" or flags.has(flag):
		return
	if Net.is_session():
		if not multiplayer.is_server():
			return
		_net_set.rpc(flag)
	_set_here(flag)


func clear() -> void:
	flags.clear()


@rpc("authority", "reliable")
func _net_set(flag: StringName) -> void:
	_set_here(flag)


func _set_here(flag: StringName) -> void:
	if flags.has(flag):
		return
	flags[flag] = true
	flag_set.emit(flag)
