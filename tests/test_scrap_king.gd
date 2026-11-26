extends Node
## The Scrap King: the crane panel and keycard, the barrier over the pit, dropping onto the
## balcony starts the fight, three bodies, the magnet pull, and the pit opening afterwards.

const LEVEL := preload("res://scenes/levels/heap.tscn")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
	print(("PASS " if ok else "FAIL ") + what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Egg.clear()
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 3
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	var rounds: RoundManager = level.get_node("RoundManager")
	var king: ScrapKing = level.get_node("ScrapKing")
	var player: Player = level.get_node("Player")
	var pit_drop: Passage = level.get_node("PitDrop")
	await level.get_node("NavigationRegion3D").baked
	for i in 5:
		await get_tree().physics_frame

	check(king.stage == ScrapKing.Stage.ASLEEP and not pit_drop.enabled, "he's asleep in the pit and the pit drop is shut")
	# The barrier stops players falling into the pit early.
	player.global_position = Vector3(0, 4.3, 21)
	player.velocity = Vector3(0, 0, -12)
	for i in 30:
		await get_tree().physics_frame
	# (Landing on the balcony also wakes him; that's checked next.)
	check(Vector2(player.global_position.x, player.global_position.z).length() > 17.0, "an invisible fence over the railing keeps players out of the pit")
	check(king.active, "landing on the balcony wakes him")
	player.velocity = Vector3.ZERO

	# Restart cleanly for the panel test.
	king.active = false
	rounds.release(king)
	king._reset()
	player.global_position = king.to_global(king.crane_panel_spot) + Vector3(0, 0.3, 2.0)
	check(king.panel.get_prompt(player).contains("keycard") and not king.panel.interact(player), "the crane controls need a keycard")
	Egg.set_flag(&"crane_keycard")
	check(king.panel.interact(player) and king.crane_broken and Egg.has(&"crane_overloaded"), "with the keycard, overloading the crane snaps it")

	# Drop onto the balcony from the crane window.
	player.global_position = Vector3(0, 9.5, 28.5) # Just over the railing.
	for i in 90:
		await get_tree().physics_frame
		if king.active:
			break
	check(king.active and rounds.is_held(), "dropping from the crane window onto the balcony starts the fight")
	await get_tree().create_timer(king.rise_time + 0.3).timeout
	check(king.stage == ScrapKing.Stage.TANK and king.body.global_position.y > 3.0, "he climbs out as a tank")

	# Magnet: force a pull and check players get dragged.
	var far := king._balcony_point(king._angle + 35.0) + Vector3.UP * 0.3
	player.global_position = far
	player.velocity = Vector3.ZERO
	var before := player.global_position.distance_to(king.body.global_position)
	king._magnet_left = 0.0
	king._pulling_left = -1.0
	await get_tree().create_timer(1.0).timeout
	var after := player.global_position.distance_to(king.body.global_position)
	check(after < before - 1.0, "the magnet drags players in (%.1f -> %.1f m)" % [before, after])

	king.body.take_damage(1e7, Vector3.ZERO, player)
	check(king.stage == ScrapKing.Stage.REBUILD, "killing a body sends him to rebuild")
	await get_tree().create_timer(king.rebuild_time + 0.2).timeout
	check(king.stage == ScrapKing.Stage.SPIDER, "then he comes back as a spider")
	king._move_left = 0.0
	var spider_from := king.body.position
	await get_tree().create_timer(0.8).timeout
	check(king.body.position.y > spider_from.y + 3.0, "the spider leaps across the pit")
	await get_tree().create_timer(1.0).timeout
	king.body.take_damage(1e7, Vector3.ZERO, player)
	await get_tree().create_timer(king.rebuild_time + 0.2).timeout
	check(king.stage == ScrapKing.Stage.FLYER, "and then as a flyer")
	await get_tree().create_timer(1.5).timeout
	check(king.body.position.y > 8.0 and Vector2(king.body.position.x, king.body.position.z).length() < 16.0, "the flyer hovers over the pit")
	king.body.take_damage(1e7, Vector3.ZERO, player)
	check(not king.active and king.beaten and Egg.has(&"grab_magnet"), "beaten after the crane overload, he drops the Grab Magnet")
	await get_tree().process_frame
	check(pit_drop.enabled and king.pit_open and king.get_node_or_null("PitBarrier") == null, "the pit opens: the way down to the Crucible")
	check(not rounds.is_held(), "rounds carry on")

	print("\n%d/%d checks passed" % [checks - fails, checks])
	get_tree().quit(1 if fails else 0)
