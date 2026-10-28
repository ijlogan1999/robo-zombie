extends Node
## Section layouts, gates, spawns, the pause menu, robot spreading and the gun view.

const LEVEL := preload("res://scenes/levels/junkyard.tscn")
const SCRAPPER := preload("res://scenes/enemies/scrapper.tscn")

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
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	return level


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var orders := {}
	var valid := true
	for s in range(1, 16):
		var level := make_level(s)
		var section: Section = level.get_node("NavigationRegion3D/Section")
		var names := []
		for room in section.rooms:
			names.append(room.display_name)
		valid = valid and section.rooms.size() == 5 and names.has("Trade Post") and section.gates.size() == 4
		for i in 4:
			valid = valid and section.gates[i].name == "Gate%d" % i and section.gates[i].cost == 100 + 50 * i
			valid = valid and level.has_node("NavigationRegion3D/Section/Room%d" % i)
		orders[str(names)] = true
		level.free()
	check(valid, "15 layouts: 5 rooms, Trade Post in, gates Gate0-3 cost 100-250, rooms named Room0-4")
	check(orders.size() >= 6, "layouts vary (%d orders)" % orders.size())

	var level := make_level(99)
	var section: Section = level.get_node("NavigationRegion3D/Section")
	var player: Player = level.get_node("Player")
	await level.get_node("NavigationRegion3D").baked
	for i in 3:
		await get_tree().physics_frame
	check(get_tree().get_nodes_in_group(Room.SPAWN_GROUP).size() == 4, "only the landing pad spawns robots at first")
	player.add_scrap(100)
	check(section.gates[0].interact(player) and section.gates[0].is_open, "first gate opens for 100 scrap")
	await get_tree().create_timer(0.7).timeout
	check(get_tree().get_nodes_in_group(Room.SPAWN_GROUP).size() == 8, "opening it adds the next room's spawns")

	# Gun view is scaled down for the local player.
	var holder := player.weapon_holder
	check(is_equal_approx(holder.scale.x, holder.view_scale) and holder.position.length() < 0.25, "gun drawn small and close (no wall clipping)")

	# Robots standing on top of each other spread apart.
	var a: Robot = SCRAPPER.instantiate()
	var b: Robot = SCRAPPER.instantiate()
	var spawned := level.get_node("Spawned")
	a.position = Vector3(-8, 0.2, -10)
	b.position = Vector3(-8.1, 0.2, -10)
	spawned.add_child(a, true)
	spawned.add_child(b, true)
	await get_tree().create_timer(1.5).timeout
	check(a.global_position.distance_to(b.global_position) > 1.0, "two robots on one spot spread apart (%.2f m)" % a.global_position.distance_to(b.global_position))
	a.queue_free()
	b.queue_free()

	# Pause menu
	var menu := level.get_node("RoundManager/PauseMenu")
	menu.open()
	check(get_tree().paused and menu._panel.visible, "Esc menu pauses solo play")
	menu.close()
	check(not get_tree().paused and not menu._panel.visible, "resume unpauses")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
