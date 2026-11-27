class_name EggStation
extends StaticBody3D
## One step of the Easter egg chain that players use: a fuse lying on the ground, the radio,
## a kiln, the hot press, a rack. Needs some flags (items the team carries), sets one.
## Built in code by EggChain, the same on every player's game; the host decides.

signal used(player: Player)

@export var needs: Array[StringName] = []
@export var sets: StringName
@export var action_text := "[E] Use"
@export var missing_text := "" ## Shown when something in `needs` is missing ("" = no prompt).
@export var done_text := "" ## Shown once used ("" = no prompt).
@export var hide_when_done := false
@export var only_in_break := false ## Only works between rounds.
@export var break_text := "Locked until the round ends"
@export var hidden_until: StringName ## Not there at all until this flag is set.

var use_sound: StringName = &"gate_open"
## Extra host-side check: return "" when it can be used now, or the reason it can't.
var check: Callable


func is_done() -> bool:
	return sets != &"" and Egg.has(sets)


func ready_to_use() -> bool:
	for flag in needs:
		if not Egg.has(flag):
			return false
	return true


func _ready() -> void:
	Egg.flag_set.connect(func(_f: StringName) -> void: _update())
	_update()


func get_prompt(_player: Player) -> String:
	if not Egg.has(hidden_until):
		return ""
	if is_done():
		return done_text
	if not ready_to_use():
		return missing_text
	if only_in_break and _in_round():
		return break_text
	if check.is_valid():
		var why: String = check.call()
		if why != "":
			return why
	return action_text


func interact(player: Player) -> bool:
	if get_prompt(player) != action_text:
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_use.rpc_id(1, player.get_path())
		return true
	_use(player)
	return true


func _use(player: Player) -> void:
	if is_done() or not ready_to_use():
		return
	Egg.set_flag(sets)
	used.emit(player)


func _in_round() -> bool:
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	return rounds != null and rounds.phase == RoundManager.Phase.ROUND


func _update() -> void:
	var there := Egg.has(hidden_until) and not (hide_when_done and is_done())
	visible = there
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", not there)
	var lit := get_node_or_null("Lit") as Node3D
	if lit:
		lit.visible = is_done()


@rpc("any_peer", "reliable")
func _net_use(player_path: NodePath) -> void:
	var player := get_node_or_null(player_path) as Player
	if player and get_prompt(player) == action_text:
		_use(player)
