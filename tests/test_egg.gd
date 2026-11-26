extends Node
## The main Easter egg, step by step: every station is built where it should be, each one
## needs the right items and gives the next, Dot talks once the radio works, the dip order
## matters, the Staff Bot follows the team and gets stamped, and half 2 leads to the kill
## code. Boss fights are covered by their own tests, so their drops are set directly here.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const DRIPPER := preload("res://scenes/enemies/dripper.tscn")

var fails := 0
var checks := 0
var level: Node3D
var chain: EggChain
var player: Player
var rounds: RoundManager
var said: Array[String] = []


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func use(station_name: String) -> bool:
	var s: EggStation = chain.stations[station_name]
	return s.interact(player)


func section_of(node: Node3D) -> Section:
	for s: Section in get_tree().get_nodes_in_group("section"):
		if s.room_at_position(node.global_position + Vector3.UP * 0.5) != null:
			return s
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	level = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 11
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	chain = level.get_node("EggChain")
	player = level.get_node("Player")
	rounds = level.get_node("RoundManager")
	rounds.announced.connect(func(t: String) -> void: said.append(t))
	await frames(3)

	var expected := ["Radio", "Fuse0", "Fuse1", "Fuse2", "Keycard", "SupervisorBooth", "KilnHeart", "CoilCharger", "QuenchTongs", "BlankBoard", "HotPress", "Dip0", "Dip1", "Dip2", "HeatingCoil", "Etch", "Solder", "BootBoard", "StaffRack", "LineSend", "OverridePanel", "TowerCrane"]
	var missing := []
	var lost := []
	for n in expected:
		if not chain.stations.has(n):
			missing.append(n)
		elif section_of(chain.stations[n]) == null:
			lost.append(n)
	check(missing.is_empty(), "every egg station is built %s" % str(missing))
	check(lost.is_empty(), "and each one sits inside a section's rooms %s" % str(lost))

	# 1. Fuses and the radio.
	check(not use("Radio"), "the radio is dead without its fuses")
	for i in 3:
		use("Fuse%d" % i)
	await frames(1)
	check(not chain.stations["Fuse0"].visible and use("Radio") and Egg.has(&"radio_fixed"), "pick up 3 fuses and fix the radio")
	await frames(1)
	check(said.any(func(t: String) -> bool: return t.begins_with("DOT:")), "Dot comes on the radio")

	# 2. Keycard, only between rounds.
	rounds.phase = RoundManager.Phase.ROUND
	check(not use("Keycard"), "the keycard trailer is locked during a round")
	rounds.phase = RoundManager.Phase.BREAK
	check(use("Keycard") and Egg.has(&"crane_keycard"), "between rounds you can take the keycard")

	# 3-4. Bosses (own tests): the magnet, and the heart left in the kiln.
	Egg.set_flag(&"grab_magnet")
	Egg.set_flag(&"kiln_heart_left")
	await frames(1)
	check(chain.stations["KilnHeart"].visible and not use("KilnHeart"), "the Kiln Heart glows in a kiln, too hot to hold")

	# 5. Tongs from Drippers by the marked tank, and the blank board.
	check(not chain.stations["QuenchTongs"].visible, "the tongs aren't out yet")
	for i in chain.tong_kills:
		var d: Robot = rounds.spawn_add(DRIPPER, chain._tong_spot.global_position + Vector3(2, 0.5, 0))
		await frames(1)
		d.health.take_damage(1e6)
		await frames(2)
	check(Egg.has(&"tongs_dropped") and chain.stations["QuenchTongs"].visible, "kill Drippers by the marked tank and quench tongs drop")
	check(use("QuenchTongs") and use("BlankBoard") and Egg.has(&"blank_board"), "take the tongs; the magnet fishes a blank board out of the deep tank")

	# 6-7. Heart, press and dips.
	check(use("KilnHeart") and Egg.has(&"kiln_heart"), "the tongs pull the Kiln Heart out")
	check(use("HotPress") and Egg.has(&"staff_body_pressed"), "the hot press forges a body")
	await frames(1)
	check(said.any(func(t: String) -> bool: return t.contains("DIP IT IN THIS ORDER")), "Dot reads off the dip order")
	var wrong: EggStation = chain.dip_order[1]
	wrong.interact(player)
	check(chain.dip_done == 0, "dip in the wrong tank and the dips start over")
	for hook in chain.dip_order:
		hook.interact(player)
	check(Egg.has(&"staff_bot_body"), "dip in the right order and the body is done")

	# 8-9. Board and assembly.
	check(not use("Solder"), "the board has to be etched before soldering")
	var bugs_before := get_tree().get_nodes_in_group("robots").size()
	check(use("Etch") and use("Solder") and Egg.has(&"staff_bot_circuits"), "etch the board in the acid, solder it in the canopy")
	check(get_tree().get_nodes_in_group("robots").size() >= bugs_before + 5, "etching it brings a swarm of Bugs")
	for r in get_tree().get_nodes_in_group("robots"):
		r.queue_free()
	check(use("StaffRack") and chain._sleeping_bot.visible, "assemble the Staff Bot on the rack in Cold Storage")

	# 10. The Line.
	check(use("LineSend") and Egg.has(&"staff_bot_on_line") and not chain._sleeping_bot.visible, "send it down the Line")
	var line_giant: Boss = level.get_node("LineNav/LineGiant")
	check(line_giant.requires_flag == &"staff_bot_on_line", "beating the giant now wakes it")
	player.global_position = level.get_node("ProvingNav/Section").rooms[0].global_position + Vector3(0, 0.3, 0)
	Egg.set_flag(&"staff_bot_awake")
	await frames(2)
	check(chain.staff_bot != null, "the Staff Bot walks with the team")
	await get_tree().create_timer(1.0).timeout
	check(chain.staff_bot.global_position.distance_to(player.global_position) < 6.0, "it keeps up with you")

	# 11. Stamps at every checkpoint.
	var proving: ProvingSection = level.get_node("ProvingNav/Section")
	await frames(2)
	for gate in chain.checkpoints:
		gate.open()
		player.global_position = gate.global_position + Vector3(0, 0.3, 2)
		await get_tree().create_timer(2.5).timeout
	check(Egg.has(&"staff_bot_certified"), "walk it through every checkpoint gate and it's certified (%d gates)" % chain.checkpoints.size())
	var _p := proving

	# 12-13. Ledger (own test) and the tower base.
	Egg.set_flag(&"staff_bot_cleared")
	check(use("TowerCrane") and Egg.has(&"tower_base_crushed"), "the Grab Magnet drops a container on the tower's base")
	check((level.get_node("ShippingNav/ControlTower") as Boss).requires_flag == &"tower_base_crushed", "so the tower drops its beacon")

	# Half 2.
	check(use("SupervisorBooth") and Egg.has(&"rigged_part"), "the Staff Bot's clearance opens the supervisor booth")
	check(use("HeatingCoil") and use("CoilCharger") and Egg.has(&"thaw_coil"), "rip out a heating coil and charge it in the kilns")
	check(use("BootBoard") and Egg.has(&"thaw_board"), "solder a boot board")
	Egg.set_flag(&"admin_badge")
	line_giant.beaten = true
	check(use("OverridePanel") and not line_giant.beaten and line_giant.drop_flag == &"override_chip" and line_giant.display_name.ends_with("MK II"), "the badge at the override panel rebuilds the giant as the Mk II")
	Egg.set_flag(&"override_chip")
	var chute: Area3D = level.get_node("LineNav/Section").rooms[-1].get_node("ConveyorHome")
	player.global_position = chute.global_position
	await frames(6)
	check(Egg.has(&"kill_code"), "ride the Line's conveyor down and Dot decodes the kill code")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
