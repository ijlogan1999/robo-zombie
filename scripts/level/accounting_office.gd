class_name AccountingOffice
extends Node3D
## Accounting starts out calm. Its staff are robots players have met before, dressed up
## for the office, going about their work and ignoring everyone. No outside robots spawn in
## here while it's calm, so a round can't end with robots left alive outside.
##
## Whichever happens first sets the whole office off: someone takes QUOTA's Ledger, or
## shoots one of the staff. Then the staff pull out their weapons and the section spawns
## like any other. The staff don't count toward the round.
##
## No boss and no hazards. Host runs it; robots carry their own looks to everyone.

signal triggered

@export var section_path: NodePath = ^"../Section"
@export var staff_scenes: Array[PackedScene] = []
@export var staff_per_room := 2
@export var head_office_flag: StringName = &"staff_bot_cleared" ## Opens the way to Head Office.

var calm := true
var staffed := false
var staff: Array[Robot] = []

@onready var section: HallSection = get_node(section_path)


func _ready() -> void:
	add_to_group("accounting_office")
	section.spawns_enabled = false
	Egg.flag_set.connect(_on_flag)
	_on_flag.call_deferred(head_office_flag)


func _physics_process(_delta: float) -> void:
	if staffed or not calm or (Net.is_session() and not multiplayer.is_server()):
		return
	for player: Player in get_tree().get_nodes_in_group("players"):
		if section.room_at_position(player.global_position):
			_hire_staff()
			return


## Everyone back to work (the first player to walk in brings them in at this round's
## strength).
func _hire_staff() -> void:
	staffed = true
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds == null or staff_scenes.is_empty():
		return
	for room in section.rooms:
		var desks: Array[Node3D] = []
		var holder := room.get_node_or_null("Desks")
		if holder == null:
			continue
		for d in holder.get_children():
			desks.append(d as Node3D)
		if desks.is_empty():
			continue
		for i in staff_per_room:
			var at: Node3D = desks[i % desks.size()]
			var robot := rounds.spawn_add(staff_scenes.pick_random(), at.global_position + Vector3.UP * 0.3)
			robot.wander_points = desks
			robot.set_docile(true)
			robot.struck.connect(_on_struck)
			staff.append(robot)


func _on_struck(attacker: Node) -> void:
	if attacker is Player:
		trigger()


## Sets every member of staff off at once. Anyone may call it; it's passed to the host.
func trigger() -> void:
	if not calm:
		return
	if Net.is_session() and not multiplayer.is_server():
		_net_request_trigger.rpc_id(1)
		return
	_set_off()
	for robot in staff:
		if is_instance_valid(robot) and not robot.health.dead:
			robot.set_docile(false)
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds:
		rounds.announce("ACCOUNTING HAS NOTICED YOU")
	if Net.is_session():
		_net_set_off.rpc()


func _set_off() -> void:
	calm = false
	section.spawns_enabled = true
	triggered.emit()


func _on_flag(flag: StringName) -> void:
	if flag != head_office_flag or not Egg.has(flag):
		return
	for door in get_tree().get_nodes_in_group("head_office_door"):
		if door is SectionDoor and door.locked:
			door.unlock()


@rpc("any_peer", "reliable")
func _net_request_trigger() -> void:
	trigger()


@rpc("authority", "reliable")
func _net_set_off() -> void:
	_set_off()
