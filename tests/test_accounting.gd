extends Node
## Accounting: offices that start calm, staff that ignore you until you take QUOTA's Ledger
## or shoot one of them, no outside robots while it's calm, and the Staff Bot's clearance
## opening the way to Head Office.

const LEVEL := preload("res://scenes/levels/heap.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func make_level(seed_value: int) -> Node3D:
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = seed_value
	level.get_node("AccountingNav/Section").layout_seed = seed_value + 808
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func staff_alive(office: AccountingOffice) -> Array[Robot]:
	var out: Array[Robot] = []
	for r in office.staff:
		if is_instance_valid(r) and not r.health.dead:
			out.append(r)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var valid := true
	var orders := {}
	for s in range(1, 13):
		var level := make_level(s)
		var office: HallSection = level.get_node("AccountingNav/Section")
		var names := []
		for room in office.rooms:
			names.append(room.display_name)
		valid = valid and office.rooms.size() == 9 and names[0] == "Lobby" and names[1] == "Records Vault" and names[7] == "Executive Lift"
		valid = valid and office.shelf_spots.is_empty() and office.gates.size() == office.links.size()
		for i in 9:
			valid = valid and office.depth[i] >= 0 and office.room_at_position(office.bay_center(i) + Vector3.UP) == office.rooms[i]
		orders[str(names)] = true
		level.free()
	check(valid, "12 layouts: lobby in the south, the Ledger's vault in the middle, the lift to Head Office in the north")
	check(orders.size() >= 8, "the offices shuffle (%d orders)" % orders.size())

	var level := make_level(4)
	var yard: HallSection = level.get_node("ShippingNav/Section")
	var section: HallSection = level.get_node("AccountingNav/Section")
	var office: AccountingOffice = level.get_node("AccountingNav/Office")
	var rounds: RoundManager = level.get_node("RoundManager")
	var player: Player = level.get_node("Player")
	await level.get_node("AccountingNav").baked
	var door: SectionDoor = yard.rooms[7].get_node("AccountingDoor")
	player.add_scrap(door.cost)
	check(not door.locked and door.interact(player) and door.interact(player) and section.room_at_position(player.global_position) == section.rooms[0], "the Shipping Bay's Accounting door leads to the lobby")
	await frames(3)
	check(office.calm and office.staffed and office.staff.size() >= 10, "walk in and the staff are at work (%d)" % office.staff.size())
	var dressed := true
	for r in office.staff:
		dressed = dressed and r.docile and r.has_node("Meshes/Tie")
	check(dressed, "they're dressed for the office")

	# Calm: nobody comes for you, and nothing spawns here.
	for g in section.gates:
		g.open()
	player.health.health = player.health.max_health
	var hp_before: float = player.health.health + player.health.shields
	var clerk: Robot = office.staff[0]
	player.global_position = clerk.global_position + Vector3(1.0, 0.3, 0.0)
	await get_tree().create_timer(3.0).timeout
	check(player.health.health + player.health.shields >= hp_before, "standing right next to a clerk, it leaves you alone")
	var moved := false
	var starts := {}
	for r in office.staff:
		starts[r] = r.global_position
	await get_tree().create_timer(3.0).timeout
	for r in office.staff:
		if is_instance_valid(r) and r.global_position.distance_to(starts[r]) > 1.0:
			moved = true
	check(moved, "the staff walk between their desks")
	section._update_active_spawns()
	var active := 0
	for room in section.rooms:
		for m in room.spawn_points():
			if m.is_in_group(Room.SPAWN_GROUP):
				active += 1
	check(active == 0, "while it's calm, no robots from outside spawn in Accounting")

	# Shoot one and the whole office goes off.
	clerk.take_damage(1.0, clerk.global_position, player)
	await frames(2)
	var all_off := not office.calm
	for r in staff_alive(office):
		all_off = all_off and not r.docile and r.has_node("Meshes/Weapon")
	check(all_off, "shoot one clerk and every one of them pulls out a weapon")
	section._update_active_spawns()
	active = 0
	for room in section.rooms:
		for m in room.spawn_points():
			if m.is_in_group(Room.SPAWN_GROUP):
				active += 1
	check(active > 0, "and now robots spawn here like anywhere else")
	await get_tree().create_timer(2.0).timeout
	check(player.health.health + player.health.shields < hp_before, "and they come for you")
	check(rounds.remaining() == 0, "the staff don't count toward the round")

	# The Ledger.
	var ledger: Ledger = section.rooms[1].get_node("Ledger")
	var lift: SectionDoor = section.rooms[7].get_node("HeadOfficeDoor")
	check(lift.locked and ledger.get_prompt(player).contains("Take"), "the Head Office lift is staff only")
	ledger.interact(player)
	check(Egg.has(&"ledger") and lift.locked, "taking the Ledger without the Staff Bot doesn't clear you")
	level.free()
	await frames(2)

	# Second run: the Staff Bot is with you.
	Egg.clear()
	level = make_level(9)
	section = level.get_node("AccountingNav/Section")
	office = level.get_node("AccountingNav/Office")
	player = level.get_node("Player")
	await level.get_node("AccountingNav").baked
	player.global_position = section.bay_center(1) + Vector3(3, 0.3, 3)
	await frames(3)
	Egg.set_flag(&"staff_bot_awake")
	ledger = section.rooms[1].get_node("Ledger")
	lift = section.rooms[7].get_node("HeadOfficeDoor")
	check(ledger.get_prompt(player).contains("Staff Bot"), "with the Staff Bot awake, the Ledger offers to put it on the payroll")
	check(office.calm and ledger.interact(player), "you enter it in the Ledger")
	await frames(2)
	check(not office.calm and Egg.has(&"staff_bot_cleared") and not lift.locked, "that sets the office off and clears the way to Head Office")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
