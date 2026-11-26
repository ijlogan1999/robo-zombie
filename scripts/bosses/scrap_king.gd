class_name ScrapKing
extends Boss
## The Heap's boss. He lives down in the pit, sorting junk with the magnet crane. Dropping
## onto the balcony around the pit (from the crane control window upstairs) wakes him: he
## climbs up with a magnet arm and fights on the balcony.
##
## He's a core that keeps building bodies out of junk: a tank, then a spider that leaps
## across the pit, then a flyer that hovers over it and dives. Each body dies to gunfire;
## in between, the core sinks into the pit and pulls a new body together.
##
## Egg: overloading the crane controls (needs the keycard) breaks the crane, and he rips the
## magnet arm off it. Beaten that way, he drops the Grab Magnet. Either way, beating him
## opens the pit: the one-way drop to the Crucible.

enum Stage { ASLEEP, RISING, TANK, SPIDER, FLYER, REBUILD, DEAD }

@export var pit_drop: NodePath ## A Passage into the Crucible, closed until he's beaten.
@export var balcony_height := 4.0
@export var balcony_inner := 18.0
@export var balcony_outer := 29.5
@export var crane_panel_spot := Vector3(0, 8, 31.5) ## In the crane control room, by the window.

@export_group("Bodies")
@export var tank_health := 2000.0
@export var spider_health := 1600.0
@export var flyer_health := 1400.0
@export var rise_time := 2.5
@export var rebuild_time := 3.0
@export var tank_speed := 2.0
@export var spider_speed := 5.0
@export var shell_damage := 25.0
@export var shell_interval := 2.5
@export var shell_speed := 16.0
@export var leap_interval := 6.0
@export var leap_time := 1.5
@export var slam_damage := 40.0
@export var slam_reach := 5.0
@export var flyer_height := 12.0
@export var bomb_interval := 1.5
@export var bomb_damage := 15.0
@export var dive_interval := 8.0

@export_group("Magnet")
@export var magnet_interval := 9.0
@export var magnet_time := 1.5
@export var magnet_reach := 20.0
@export var magnet_pull := 4.0
@export var swipe_damage := 30.0
@export var swipe_reach := 5.0

var stage := Stage.ASLEEP
var body: CharacterBody3D
var crane_broken := false
var panel: StaticBody3D
var pit_open := false

var _body_hp := 0.0
var _body_max := 1.0
var _next_stage := Stage.TANK
var _stage_left := 0.0
var _angle := 90.0 ## Where he stands on the balcony, in degrees.
var _shell_left := 0.0
var _magnet_left := 0.0
var _pulling_left := -1.0
var _move_left := 0.0 ## Leap or dive cooldown.
var _jump_from := Vector3.ZERO
var _jump_to := Vector3.ZERO
var _jump_left := -1.0
var _body_root: Node3D
var _crane_arm: Node3D
var _barrier: StaticBody3D
var _trigger: Area3D


func _ready() -> void:
	super._ready()
	_build_crane()
	_build_body()
	_build_barrier()
	_build_trigger()
	_build_panel()
	_reset()


# --- Fight --------------------------------------------------------------------------------

func _begin() -> void:
	_body_root.visible = true
	body.position = Vector3(0, -20, 0)
	_go(Stage.RISING)


func _fight(delta: float) -> void:
	_stage_left -= delta
	match stage:
		Stage.RISING:
			var t := 1.0 - maxf(_stage_left, 0.0) / rise_time
			var top := _balcony_point(_angle)
			body.position = Vector3(0, -20, 0).lerp(top, t)
			if _stage_left <= 0.0:
				_go(_next_stage)
		Stage.REBUILD:
			body.position = body.position.lerp(Vector3(0, balcony_height + 2.0, 0), 2.0 * delta)
			if _stage_left <= 0.0:
				_go(_next_stage)
		Stage.TANK, Stage.SPIDER:
			_fight_ground(delta)
		Stage.FLYER:
			_fight_flyer(delta)
	if stage in [Stage.TANK, Stage.SPIDER, Stage.FLYER]:
		_magnet(delta)
	bar_value = _body_hp
	bar_max = _body_max


func _end(dropped: bool) -> void:
	_go_local(Stage.DEAD)
	_body_root.visible = false
	_open_pit()
	if dropped:
		_crane_arm.visible = false


func _reset() -> void:
	_go_local(Stage.ASLEEP)
	_angle = 90.0
	body.position = Vector3(0, -22, 0)
	_body_root.visible = true


func _go(new_stage: Stage) -> void:
	_go_local(new_stage)
	if Net.is_session() and multiplayer.is_server():
		_net_stage.rpc(new_stage)


func _go_local(new_stage: Stage) -> void:
	stage = new_stage
	var scale := health_scale()
	match stage:
		Stage.RISING:
			_stage_left = rise_time
			_next_stage = Stage.TANK
			phase_name = "CLIMBING OUT"
		Stage.TANK:
			_start_body(tank_health * scale, "TANK")
		Stage.SPIDER:
			_start_body(spider_health * scale, "SPIDER")
		Stage.FLYER:
			_start_body(flyer_health * scale, "FLYER")
		Stage.REBUILD:
			_stage_left = rebuild_time
			phase_name = "REBUILDING"
			_jump_left = -1.0
		Stage.ASLEEP, Stage.DEAD:
			phase_name = ""
	_shape_body()
	# Asleep in the pit or beaten, he mustn't block anyone dropping through it.
	(body.get_node("Shape") as CollisionShape3D).set_deferred("disabled", stage == Stage.ASLEEP or stage == Stage.DEAD)


func _start_body(hp: float, label: String) -> void:
	_body_max = hp
	_body_hp = hp
	phase_name = label
	_shell_left = shell_interval
	_magnet_left = magnet_interval * 0.5
	_pulling_left = -1.0
	_move_left = leap_interval if stage == Stage.SPIDER else dive_interval
	_jump_left = -1.0


## Weapons hit his body (see boss_body.gd). Bodies only take damage while fighting.
func _body_take_damage(amount: float) -> bool:
	if not active or not stage in [Stage.TANK, Stage.SPIDER, Stage.FLYER]:
		return false
	_body_hp -= amount
	if _body_hp > 0.0:
		return false
	_body_hp = 0.0
	match stage:
		Stage.TANK:
			_next_stage = Stage.SPIDER
		Stage.SPIDER:
			_next_stage = Stage.FLYER
		Stage.FLYER:
			finish()
			return true
	_announce("THE SCRAP KING PULLS A NEW BODY OUT OF THE JUNK")
	_go(Stage.REBUILD)
	return true


# --- Ground bodies: tank and spider -------------------------------------------------------

func _fight_ground(delta: float) -> void:
	var target := _nearest_player(body.global_position)
	if _jump_left >= 0.0:
		_jump_left -= delta
		var t := 1.0 - maxf(_jump_left, 0.0) / leap_time
		body.position = _jump_from.lerp(_jump_to, t) + Vector3.UP * sin(t * PI) * 10.0
		if _jump_left <= 0.0:
			_jump_left = -1.0
			_angle = rad_to_deg(atan2(_jump_to.z, _jump_to.x))
			_slam(body.global_position, slam_reach, slam_damage)
		return
	if target:
		var want := rad_to_deg(atan2(target.global_position.z - global_position.z, target.global_position.x - global_position.x))
		var speed := tank_speed if stage == Stage.TANK else spider_speed
		var step := rad_to_deg(speed * delta / _mid_radius())
		var diff := angle_difference(deg_to_rad(_angle), deg_to_rad(want))
		if absf(rad_to_deg(diff)) > 6.0:
			_angle += clampf(rad_to_deg(diff), -step, step)
		_face(target.global_position)
	body.position = _balcony_point(_angle)

	if stage == Stage.TANK:
		_shell_left -= delta
		if _shell_left <= 0.0 and target:
			_shell_left = shell_interval
			_shoot(target, shell_damage, 2.5)
	else:
		_move_left -= delta
		if _move_left <= 0.0 and target:
			_move_left = leap_interval
			_jump_from = body.position
			var a := deg_to_rad(rad_to_deg(atan2(target.global_position.z, target.global_position.x)))
			_jump_to = Vector3(cos(a) * _mid_radius(), balcony_height, sin(a) * _mid_radius())
			_jump_left = leap_time


# --- Flyer --------------------------------------------------------------------------------

func _fight_flyer(delta: float) -> void:
	var target := _nearest_player(body.global_position)
	if _jump_left >= 0.0:
		# Diving at a player and climbing back out.
		_jump_left -= delta
		var t := 1.0 - maxf(_jump_left, 0.0) / leap_time
		var down := t < 0.5
		body.position = _jump_from.lerp(_jump_to, t * 2.0) if down else _jump_to.lerp(_jump_from, (t - 0.5) * 2.0)
		if not down and _jump_left + delta >= leap_time * 0.5 and _jump_left < leap_time * 0.5:
			_slam(body.global_position, slam_reach - 0.5, slam_damage)
		if _jump_left <= 0.0:
			_jump_left = -1.0
		return
	_angle += 20.0 * delta
	var hover := Vector3(cos(deg_to_rad(_angle)) * 10.0, flyer_height, sin(deg_to_rad(_angle)) * 10.0)
	body.position = body.position.lerp(hover, 2.0 * delta)
	if target:
		_face(target.global_position)
	_shell_left -= delta
	if _shell_left <= 0.0 and target:
		_shell_left = bomb_interval
		_shoot(target, bomb_damage, 1.5)
	_move_left -= delta
	if _move_left <= 0.0 and target:
		_move_left = dive_interval
		_jump_from = body.position
		_jump_to = to_local(target.global_position) + Vector3.UP * 1.5
		_jump_left = leap_time


# --- Magnet arm ---------------------------------------------------------------------------

## Every so often the magnet hums and drags players in, then he swipes at anyone close.
func _magnet(delta: float) -> void:
	if _pulling_left >= 0.0:
		_pulling_left -= delta
		for player: Player in get_tree().get_nodes_in_group("players"):
			if not player.is_targetable():
				continue
			var to := body.global_position - player.global_position
			to.y = 0.0
			if to.length() <= magnet_reach and to.length() > 2.0:
				player.pull(to.normalized() * magnet_pull)
		if _pulling_left < 0.0:
			_slam(body.global_position, swipe_reach, swipe_damage)
		return
	_magnet_left -= delta
	if _magnet_left <= 0.0:
		_magnet_left = magnet_interval
		_pulling_left = magnet_time
		Sfx.broadcast_at(&"gate_open", body.global_position, 2.0)


# --- Shared -------------------------------------------------------------------------------

func _balcony_point(angle: float) -> Vector3:
	var a := deg_to_rad(angle)
	return Vector3(cos(a) * _mid_radius(), balcony_height, sin(a) * _mid_radius())


func _mid_radius() -> float:
	return (balcony_inner + balcony_outer) / 2.0


func _face(at: Vector3) -> void:
	var flat := at - body.global_position
	body.rotation.y = atan2(-flat.x, -flat.z)


func _shoot(target: Node3D, damage: float, size: float) -> void:
	var from := body.global_position + Vector3.UP * 2.5 - body.global_transform.basis.z * 3.0
	var aim := (target.global_position + Vector3.UP - from).normalized() * shell_speed
	_fire(from, aim, damage, size, true)
	if Net.is_session():
		_net_fire.rpc(from, aim, size)


func _fire(from: Vector3, aim: Vector3, damage: float, size: float, real: bool) -> void:
	var bolt: BoltProjectile = preload("res://scenes/enemies/bolt_projectile.tscn").instantiate()
	bolt.harmless = not real
	bolt.scale = Vector3.ONE * size
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.launch(aim, damage, self)


func _slam(at: Vector3, reach: float, damage: float) -> void:
	Sfx.broadcast_at(&"robot_swing", at + Vector3.UP, 4.0)
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_targetable() and player.global_position.distance_to(at) <= reach:
			player.take_damage(damage, at, self)


func _announce(text: String) -> void:
	var rounds := _rounds()
	if rounds:
		rounds.announce(text)


## Beaten (with or without the drop): the barrier over the pit comes down for good.
func _open_pit() -> void:
	pit_open = true
	if is_instance_valid(_barrier):
		_barrier.queue_free()
	var drop := get_node_or_null(pit_drop)
	if drop:
		drop.enabled = true


func _pack() -> Array:
	return [bar_max, bar_value, phase_name, body.position, body.rotation.y]


func _unpack(state: Array) -> void:
	super._unpack(state)
	body.position = state[3]
	body.rotation.y = state[4]


# --- Players dropping onto the balcony start the fight --------------------------------------

func _on_trigger_body_entered(entered: Node3D) -> void:
	if not entered is Player or (Net.is_session() and not multiplayer.is_server()):
		return
	var flat := Vector2(entered.global_position.x - global_position.x, entered.global_position.z - global_position.z)
	if flat.length() < balcony_inner or not can_start():
		return
	start()


## The crane panel: with the keycard, overloading it snaps the crane, and the King will
## rip the magnet arm off when he climbs out. That's the egg step his drop needs.
func get_panel_prompt() -> String:
	if crane_broken or not can_start():
		return ""
	if not Egg.has(&"crane_keycard"):
		return "Crane controls  -  locked (needs a keycard)"
	return "[E] Overload the crane controls"


func use_panel() -> bool:
	if crane_broken or not Egg.has(&"crane_keycard"):
		return false
	if Net.is_session() and not multiplayer.is_server():
		_net_use_panel.rpc_id(1)
		return true
	Egg.set_flag(&"crane_overloaded")
	_break_crane()
	if Net.is_session():
		_net_crane_broken.rpc()
	_announce("THE CRANE SNAPS. THE SCRAP KING IS COMING FOR THE ARM")
	return true


func _break_crane() -> void:
	crane_broken = true
	_crane_arm.rotation.z = 0.6
	_crane_arm.position.y -= 6.0


@rpc("any_peer", "reliable")
func _net_use_panel() -> void:
	use_panel()


@rpc("authority", "reliable")
func _net_crane_broken() -> void:
	_break_crane()


@rpc("authority", "reliable")
func _net_stage(new_stage: Stage) -> void:
	_go_local(new_stage)


@rpc("authority", "unreliable")
func _net_fire(from: Vector3, aim: Vector3, size: float) -> void:
	_fire(from, aim, 0.0, size, false)


# --- Building (greybox) -------------------------------------------------------------------

func _build_crane() -> void:
	var gantry := _box(self, Vector3(2, 2, 70), Color(0.55, 0.45, 0.15))
	gantry.position = Vector3(0, 22, 0)
	for z in [-34.0, 34.0]:
		var leg := _box(self, Vector3(2, 22, 2), Color(0.55, 0.45, 0.15))
		leg.position = Vector3(0, 11, z)
	_crane_arm = Node3D.new()
	_crane_arm.name = "CraneArm"
	add_child(_crane_arm)
	_crane_arm.position = Vector3(0, 21, 4)
	var cable := _box(_crane_arm, Vector3(0.2, 30, 0.2), Color(0.15, 0.15, 0.15))
	cable.position.y = -15
	var magnet := _box(_crane_arm, Vector3(4, 1, 4), Color(0.35, 0.35, 0.4))
	magnet.position.y = -30


func _build_body() -> void:
	body = CharacterBody3D.new()
	body.name = "King"
	body.add_to_group(&"boss_body")
	body.set_script(preload("res://scripts/bosses/boss_body.gd"))
	body.set("boss", self)
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	shape.shape = box
	shape.position.y = 2
	body.add_child(shape)
	_body_root = Node3D.new()
	_body_root.name = "Look"
	body.add_child(_body_root)


## Swaps the junk meshes for the current body.
func _shape_body() -> void:
	for child in _body_root.get_children():
		child.queue_free()
	var junk := Color(0.45, 0.36, 0.26)
	var core := _box(_body_root, Vector3(1.2, 1.2, 1.2), Color(0.2, 0.8, 1.0), true)
	core.position = Vector3(0, 2.6, -1.2)
	var shape := body.get_node("Shape") as CollisionShape3D
	var box := shape.shape as BoxShape3D
	match stage:
		Stage.TANK, Stage.RISING:
			box.size = Vector3(4.5, 3.5, 5)
			shape.position.y = 1.75
			var hull := _box(_body_root, Vector3(4.5, 2.4, 5), junk)
			hull.position.y = 1.2
			var turret := _box(_body_root, Vector3(2.4, 1.2, 2.4), junk)
			turret.position.y = 3.0
			var barrel := _box(_body_root, Vector3(0.5, 0.5, 3), junk)
			barrel.position = Vector3(0, 3.0, -2.6)
		Stage.SPIDER:
			box.size = Vector3(3, 2.5, 3)
			shape.position.y = 2.5
			var thorax := _box(_body_root, Vector3(3, 1.8, 3), junk)
			thorax.position.y = 2.5
			for i in 6:
				var a := TAU * i / 6.0
				var leg := _box(_body_root, Vector3(0.3, 0.3, 3.5), junk)
				leg.position = Vector3(cos(a) * 2.5, 1.4, sin(a) * 2.5)
				leg.rotation = Vector3(0.6, -a + PI / 2.0, 0)
		Stage.FLYER:
			box.size = Vector3(4, 1.5, 4)
			shape.position.y = 2.5
			var frame := _box(_body_root, Vector3(4, 1, 4), junk)
			frame.position.y = 2.5
			for x in [-2.5, 2.5]:
				for z in [-2.5, 2.5]:
					var rotor := _box(_body_root, Vector3(2, 0.1, 0.3), Color(0.2, 0.2, 0.2))
					rotor.position = Vector3(x, 3.2, z)
	# The magnet arm: his own once he's taken it off the crane.
	if stage in [Stage.TANK, Stage.SPIDER, Stage.FLYER]:
		var arm := _box(_body_root, Vector3(0.6, 0.6, 4), Color(0.35, 0.35, 0.4))
		arm.position = Vector3(2.6, 2.8, -1.5)
		var magnet := _box(_body_root, Vector3(1.8, 0.5, 1.8), Color(0.6, 0.1, 0.1))
		magnet.position = Vector3(2.6, 2.4, -3.5)


func _build_barrier() -> void:
	# An invisible fence over the railing so nobody falls into the pit before he's beaten.
	_barrier = StaticBody3D.new()
	_barrier.name = "PitBarrier"
	add_child(_barrier)
	var pieces := 24
	for i in pieces:
		var a := TAU * (i + 0.5) / pieces
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0 * PI * balcony_inner / pieces + 0.5, 10, 0.5)
		shape.shape = box
		shape.position = Vector3(cos(a) * (balcony_inner - 0.3), balcony_height + 5.0, sin(a) * (balcony_inner - 0.3))
		shape.rotation.y = -a + PI / 2.0
		_barrier.add_child(shape)


func _build_trigger() -> void:
	_trigger = Area3D.new()
	_trigger.name = "BalconyTrigger"
	add_child(_trigger)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = balcony_outer
	cylinder.height = 2.5
	shape.shape = cylinder
	shape.position.y = balcony_height + 1.25
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_trigger_body_entered)


func _build_panel() -> void:
	panel = StaticBody3D.new()
	panel.name = "CranePanel"
	panel.set_script(preload("res://scripts/bosses/crane_panel.gd"))
	panel.set("king", self)
	add_child(panel)
	panel.position = crane_panel_spot
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.4, 0.8)
	shape.shape = box
	shape.position.y = 0.7
	panel.add_child(shape)
	var desk := _box(panel, Vector3(1.6, 1.0, 0.8), Color(0.3, 0.3, 0.32))
	desk.position.y = 0.5
	var lever := _box(panel, Vector3(0.15, 0.6, 0.15), Color(0.9, 0.2, 0.15), true)
	lever.position = Vector3(0.4, 1.3, 0)


