extends Node
## Renders a few views of the Heap to PNGs for checking the layout by eye.
## Run: godot --rendering-driver opengl3 --path . res://tools/screenshot_heap.tscn -- --out=/some/dir

const LEVEL := preload("res://scenes/levels/heap.tscn")


func _ready() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var level: Node3D = LEVEL.instantiate()
	level.get_node("NavigationRegion3D/Section").layout_seed = 7
	level.get_node("RoundManager").first_break_time = 9999.0
	add_child(level)
	var section: RingSection = level.get_node("NavigationRegion3D/Section")
	for gate in section.gates:
		gate.open()
	level.get_node("Player").queue_free()
	var cam := Camera3D.new()
	cam.far = 1000.0
	add_child(cam)
	cam.current = true
	var views := {
		"overhead": [Vector3(0, 150, 60), Vector3(0, 0, 0)],
		"angle": [Vector3(90, 70, 110), Vector3(0, 0, 0)],
		"spawn": [section.slot_center(0) + Vector3(0, 1.7, 8), section.slot_center(0) + Vector3(0, 1.5, -10)],
		"stairs": [section.slot_center(4) + Vector3(12, 1.7, 8), section.ring_point(270, 40, 4)],
		"upper": [section.slot_center(9) + Vector3(0, 1.7, 0), Vector3(0, 4, 0)],
		"crucible_top": [Vector3(0, -173, 30), Vector3(0, -200, 0)],
		"crucible_floor": [Vector3(0, -198.3, 0), Vector3(40, -199, 20)],
		"crucible_edge": [Vector3(-55, -190, 0), Vector3(0, -200, 0)],
	}
	var dome: DomeSection = level.get_node("CrucibleNav/Section")
	for gate in dome.gates:
		gate.open()
	for i in 30:
		await get_tree().process_frame
	for key in views:
		cam.global_position = views[key][0]
		cam.look_at(views[key][1])
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("heap_%s.png" % key))
		print("saved ", key)
	var king: ScrapKing = level.get_node("ScrapKing")
	king.start()
	for i in 200:
		await get_tree().physics_frame
	await _shot(cam, Vector3(0, 10, 30), king.body.global_position + Vector3.UP * 2, out.path_join("king_tank.png"))
	king.body.take_damage(1e7, Vector3.ZERO)
	for i in 200:
		await get_tree().physics_frame
	await _shot(cam, Vector3(0, 10, 30), king.body.global_position + Vector3.UP * 2, out.path_join("king_spider.png"))
	# The Kiln Mother mid-fight: the Ladle pouring, then the kiln awake.
	var boss: KilnMother = level.get_node("KilnMother")
	boss.start()
	for i in 200:
		await get_tree().physics_frame
	await _shot(cam, Vector3(14, -193, 14), Vector3(0, -188, -4), out.path_join("boss_ladle.png"))
	for valve in boss.valves:
		valve.take_damage(1e6, valve.global_position)
	boss._set_door(true)
	await _shot(cam, Vector3(9, -195, 3), boss.kiln.global_position + Vector3.UP * 2, out.path_join("boss_kiln.png"))
	boss.kiln_core.take_damage(1e7, Vector3.ZERO)
	await _shot(cam, Vector3(9, -195, 3), boss.golem.global_position + Vector3.UP * 3, out.path_join("boss_golem.png"))
	get_tree().quit()


func _shot(cam: Camera3D, from: Vector3, at: Vector3, path: String) -> void:
	cam.global_position = from
	cam.look_at(at)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
