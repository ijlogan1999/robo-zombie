extends Node
## The Slagger: works the scrap until it notices players, sprays a cone of molten metal,
## leaves puddles, and only spawns in the Crucible.

const LEVEL := preload("res://scenes/levels/heap.tscn")
const SLAGGER := preload("res://scenes/enemies/slagger.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 3
	level.get_node("CrucibleNav/Section").layout_seed = 104
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	var rounds: RoundManager = level.get_node("RoundManager")
	var heap: Section = level.get_node("NavigationRegion3D/Section")
	var dome: Section = level.get_node("CrucibleNav/Section")
	var player: Player = level.get_node("Player")
	await level.get_node("CrucibleNav").baked

	# Only the Crucible's spawn points can roll a Slagger.
	var heap_point: Node = heap.rooms[0].spawn_points()[0]
	var dome_point: Node = dome.rooms[1].spawn_points()[0]
	check(Section.containing(heap_point) == heap and Section.containing(dome_point) == dome, "spawn points know their section")
	var heap_rolls := {}
	var dome_rolls := {}
	for i in 400:
		heap_rolls[rounds.pick_robot_scene(8, heap.spawn_table)] = true
		dome_rolls[rounds.pick_robot_scene(8, dome.spawn_table)] = true
	check(not heap_rolls.has(SLAGGER) and dome_rolls.has(SLAGGER), "Slaggers only roll in the Crucible")

	Arrival.send(player, &"crucible_landing")
	var slagger: Slagger = SLAGGER.instantiate()
	slagger.configure(100.0, 3.0)
	slagger.position = player.global_position + Vector3(0, 0.2, 25)
	level.get_node("Spawned").add_child(slagger, true)
	player.global_position += Vector3(0, 0, -20) # Well out of sight range.
	for i in 30:
		await get_tree().physics_frame
	check(not slagger.aware and slagger.target != player, "it works the scrap and ignores far-off players")
	await get_tree().create_timer(3.0).timeout
	check(_puddles() > 0 or slagger.spraying, "it sprays the scrap (melting it)")

	slagger.take_damage(1.0, slagger.global_position, player)
	await get_tree().create_timer(0.4).timeout
	check(slagger.aware and slagger.target == player, "shooting it turns it on players")

	slagger.global_position = player.global_position + Vector3(0, 0, -3)
	slagger.look_at(player.global_position, Vector3.UP)
	var before: float = player.health.health + player.health.shields
	await get_tree().create_timer(2.2).timeout
	var after: float = player.health.health + player.health.shields
	check(after < before, "its spray burns players in front of it (%.0f -> %.0f)" % [before, after])
	check(_puddles() > 0, "each spray leaves a molten puddle (%d)" % _puddles())

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)


func _puddles() -> int:
	return get_tree().current_scene.find_children("*", "HazardZone", false, false).size()
