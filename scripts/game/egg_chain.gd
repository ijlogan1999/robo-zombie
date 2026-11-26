class_name EggChain
extends Node3D
## Builds and runs the main Easter egg across Kiln, once every section has laid out its
## rooms. Everything is built the same on every player's game (from the layout seeds), so
## co-op games agree on what is where; the host decides what happens.
##
## Half 1 (Clock Out): fuses and the radio (Dot starts talking), the trailer keycard, the
## crane (Scrap King, Grab Magnet), the Kiln Heart, quench tongs and the blank board, the
## hot press and the dip order, etching and soldering the board, assembling the Staff Bot,
## waking it on the Line, stamping it at the Proving Grounds, the Ledger, the tower base,
## and Head Office.
## Half 2 (Overtime): the supervisor booth, the heating coil and thaw coil, the boot board,
## QUOTA's backup body, the Line's Mk II giant, and the kill code.

const DOT_LINES := {
	&"radio_fixed": "DOT: ...IS THIS THING ON? HI! I'M DOT. THE CRANE ROOM'S KEYCARD IS IN ONE OF THE TRAILERS. THEY ONLY OPEN BETWEEN ROUNDS",
	&"crane_keycard": "DOT: GOT IT? OVERLOAD THE CRANE CONTROLS AND THE KING WILL COME TO YOU",
	&"grab_magnet": "DOT: THAT MAGNET CAN PULL THINGS OUT OF TANKS. AND THE KILN MOTHER HAS A HEART WORTH STEALING",
	&"kiln_heart_left": "DOT: TOO HOT TO HOLD. THERE ARE QUENCH TONGS SOMEWHERE IN THE CHASSIS YARD. DRIPPERS LOVE THE MARKED TANK",
	&"quench_tongs": "DOT: TONGS! NOW FISH A BLANK BOARD OUT OF THE DEEP TANK WITH THE MAGNET, THEN FETCH THE HEART",
	&"kiln_heart": "DOT: CAREFUL WITH THAT. THE CHASSIS YARD'S HOT PRESS CAN FORGE A BODY WITH IT",
	&"staff_bot_body": "DOT: A BODY! IT NEEDS CIRCUITS. ETCH THAT BLANK BOARD IN SERVO'S ACID, THEN SOLDER IT IN THE CANOPY",
	&"board_etched": "DOT: BUGS HATE THAT SMELL. RUN IT UP TO THE CANOPY AND SOLDER IT",
	&"staff_bot_circuits": "DOT: BODY AND BRAINS. THERE'S AN EMPTY STAFF RACK IN COLD STORAGE'S CRYO CHAMBER",
	&"staff_bot_assembled": "DOT: IT'S ASLEEP. THE LINE WAKES ALL QUOTA'S WORKERS. PUT IT ON THE BELT",
	&"staff_bot_awake": "DOT: IT'S WALKING! QUOTA ONLY TRUSTS CERTIFIED STAFF. GET IT STAMPED AT EVERY CHECKPOINT ON THE PROVING GROUNDS",
	&"staff_bot_certified": "DOT: CERTIFIED! NOW PUT IT ON THE PAYROLL. QUOTA'S LEDGER IS IN ACCOUNTING",
	&"staff_bot_cleared": "DOT: YOU'RE CLEARED FOR HEAD OFFICE. YOU'LL NEED A SHIP OUT: THE CONTROL TOWER HAS A LANDING BEACON. THE MAGNET CAN DROP A CONTAINER ON ITS BASE",
	&"tower_base_crushed": "DOT: THE TOWER'S BASE IS CRUSHED. TAKE IT DOWN AND GRAB THAT BEACON",
	&"landing_beacon": "DOT: BEACON'S READY. FIGHT QUOTA WHENEVER YOU LIKE. OR... THE SUPERVISOR BOOTH BY THE SPAWN JUST UNLOCKED FOR STAFF",
	&"rigged_part": "DOT: QUOTA KEEPS A BACKUP BODY IN COLD STORAGE. IF YOU BEAT IT HERE, IT JUST MOVES THERE. WE NEED TO CUT ITS UPLOAD LINE",
	&"heating_coil": "DOT: CHARGE THAT COIL IN THE CRUCIBLE'S KILNS",
	&"thaw_coil": "DOT: THAT'LL THAW ANYTHING. SOLDER A BOOT BOARD IN SERVO'S CANOPY TOO",
	&"thaw_board": "DOT: INSTALL BOTH IN COLD STORAGE'S CRYO CHAMBER. THEN... WAKE THE BACKUP. SORRY",
	&"admin_badge": "DOT: AN ADMIN BADGE! THE LINE'S OVERRIDE PANEL WILL TAKE IT",
	&"line_override": "DOT: UH OH. IT'S BUILDING SOMETHING BIGGER. WITH YOUR RIGGED PART INSIDE",
	&"override_chip": "DOT: THAT CHIP IS ENCRYPTED. RIDE THE LINE'S CONVEYOR DOWN AND I'LL DECODE IT",
	&"kill_code": "DOT: GOT IT. THE KILL CODE. TAKE IT AND THE CHIP TO HEAD OFFICE AND CUT QUOTA'S UPLOAD LINE",
}

@export var heap_path: NodePath = ^"../NavigationRegion3D/Section"
@export var crucible_path: NodePath = ^"../CrucibleNav/Section"
@export var chassis_path: NodePath = ^"../ChassisNav/Section"
@export var servo_path: NodePath = ^"../ServoNav/Section"
@export var cold_path: NodePath = ^"../ColdNav/Section"
@export var line_path: NodePath = ^"../LineNav/Section"
@export var proving_path: NodePath = ^"../ProvingNav/Section"
@export var shipping_path: NodePath = ^"../ShippingNav/Section"
@export var giant_path: NodePath = ^"../LineNav/LineGiant"
@export var tower_path: NodePath = ^"../ShippingNav/ControlTower"
@export var bug_scene: PackedScene
@export var tong_kills := 3 ## Dripper kills by the marked tank before the tongs drop for sure.

var stations := {} ## Name -> EggStation.
var dip_order: Array[EggStation] = []
var dip_done := 0
var staff_bot: StaffBot
var stamped := {} ## CheckpointGate -> true.
var checkpoints: Array[Node] = []

var _rng := RandomNumberGenerator.new()
var _tong_spot: Node3D
var _tong_kills := 0
var _sleeping_bot: Node3D


func _ready() -> void:
	add_to_group("egg_chain")
	Egg.flag_set.connect(_on_flag)
	_build.call_deferred()


func _build() -> void:
	var heap := get_node(heap_path) as Section
	_rng.seed = heap.used_seed * 7919 + 17
	_build_heap(heap)
	_build_crucible(get_node(crucible_path) as Section)
	_build_chassis(get_node(chassis_path) as Section)
	_build_servo(get_node(servo_path) as Section)
	_build_cold(get_node(cold_path) as Section)
	_build_line(get_node(line_path) as Section)
	_build_proving(get_node(proving_path) as Section)
	_build_shipping(get_node(shipping_path) as Section)
	if multiplayer.is_server():
		get_tree().node_added.connect(_on_node_added)


func say(text: String) -> void:
	if Net.is_session() and not multiplayer.is_server():
		return
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds:
		rounds.announce(text)


# --- Per section --------------------------------------------------------------------------

func _build_heap(heap: Section) -> void:
	var landing := heap.rooms[0]
	var button := landing.get_node("NextRoundButton") as Node3D
	var radio := _station("Radio", button.global_position + landing.global_basis.x * 2.5, Vector3(1.0, 0.8, 0.6), Color(0.35, 0.3, 0.25))
	radio.needs = [&"fuse_0", &"fuse_1", &"fuse_2"]
	radio.sets = &"radio_fixed"
	radio.action_text = "[E] Fit the fuses and fix the radio"
	radio.missing_text = "A dead radio. Its fuses are missing"
	radio.done_text = "Dot's radio"
	var rooms: Array = heap.rooms.slice(1)
	_shuffle(rooms)
	for i in 3:
		var room: Room = rooms[i % rooms.size()]
		var spots := room.spawn_points()
		var spot: Node3D = spots[_rng.randi_range(0, spots.size() - 1)] if not spots.is_empty() else room
		var fuse := _station("Fuse%d" % i, spot.global_position + Vector3(1.2, 0, 1.2), Vector3(0.3, 0.3, 0.3), Color(0.9, 0.75, 0.2), true)
		fuse.sets = StringName("fuse_%d" % i)
		fuse.action_text = "[E] Pick up a fuse"
		fuse.hide_when_done = true
	var trailers: Room = null
	for room in heap.rooms:
		if room.has_node("TrailerStep1"):
			trailers = room
	var step: Node3D = trailers.get_node("TrailerStep%d" % _rng.randi_range(0, 2)) if trailers else landing
	var card := _station("Keycard", step.global_position + Vector3.UP * 0.6, Vector3(0.5, 0.1, 0.35), Color(0.2, 0.6, 1.0), true)
	card.sets = &"crane_keycard"
	card.action_text = "[E] Take the keycard"
	card.only_in_break = true
	card.break_text = "A locked trailer. It opens between rounds"
	card.hide_when_done = true
	var booth := _station("SupervisorBooth", button.global_position - landing.global_basis.x * 2.5, Vector3(1.2, 2.2, 1.2), Color(0.3, 0.32, 0.38))
	booth.needs = [&"staff_bot_cleared"]
	booth.sets = &"rigged_part"
	booth.action_text = "[E] Badge into the supervisor booth"
	booth.missing_text = "Supervisor booth. Staff only"
	booth.done_text = "The booth's terminal is open"


func _build_crucible(crucible: Section) -> void:
	var kilns: Room = null
	for room in crucible.rooms:
		if room.has_node("KilnMouth1"):
			kilns = room
			break
	var mouth := (kilns.get_node("KilnMouth1") if kilns else crucible.rooms[0]) as Node3D
	var heart := _station("KilnHeart", mouth.global_position, Vector3(1.0, 1.0, 1.0), Color(1.0, 0.45, 0.1), true)
	heart.needs = [&"kiln_heart_left", &"quench_tongs"]
	heart.sets = &"kiln_heart"
	heart.action_text = "[E] Pull the Kiln Heart out with the tongs"
	heart.missing_text = "Something glows deep in the kiln. Too hot to touch"
	heart.hidden_until = &"kiln_heart_left"
	heart.hide_when_done = true
	var other := (kilns.get_node("KilnMouth2") if kilns else crucible.rooms[0]) as Node3D
	var charge := _station("CoilCharger", other.global_position, Vector3(1.0, 1.0, 1.0), Color(0.6, 0.25, 0.1))
	charge.needs = [&"heating_coil"]
	charge.sets = &"thaw_coil"
	charge.action_text = "[E] Charge the heating coil in the kiln"
	charge.hidden_until = &"heating_coil"
	charge.done_text = "Thaw coil charged"


func _build_chassis(chassis: Section) -> void:
	_tong_spot = _first_in_group(chassis, "marked_tank")
	if _tong_spot:
		var tongs := _station("QuenchTongs", _tong_spot.global_position + Vector3.UP * 0.3, Vector3(0.9, 0.15, 0.3), Color(0.5, 0.5, 0.55), true)
		tongs.sets = &"quench_tongs"
		tongs.action_text = "[E] Take the quench tongs"
		tongs.hidden_until = &"tongs_dropped"
		tongs.hide_when_done = true
	var magnet := _find_named(chassis, "MagnetSpot")
	if magnet:
		var board := _station("BlankBoard", magnet.global_position + Vector3.UP * 0.5, Vector3(0.8, 0.8, 0.8), Color(0.2, 0.5, 0.25))
		board.needs = [&"grab_magnet"]
		board.sets = &"blank_board"
		board.action_text = "[E] Fish a blank board out with the Grab Magnet"
		board.missing_text = "Something's stuck at the bottom. Too deep to reach"
		board.done_text = "Empty hook"
	var press_spot := _first_in_group(chassis, "hot_press")
	if press_spot:
		var press := _station("HotPress", press_spot.global_position, Vector3(1.4, 1.2, 1.0), Color(0.6, 0.3, 0.2))
		press.needs = [&"kiln_heart"]
		press.sets = &"staff_body_pressed"
		press.action_text = "[E] Forge a body in the press with the Kiln Heart"
		press.missing_text = "The hot press is cold"
		press.done_text = "Forged. Now the dips"
	var tanks: Array = chassis.find_children("*", "DipTank", true, false)
	tanks.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))
	_shuffle(tanks)
	for i in mini(3, tanks.size()):
		var tank: Node3D = tanks[i]
		var hook := _station("Dip%d" % i, _tank_edge(tank, 1.0), Vector3(0.6, 1.6, 0.6), Color(0.85, 0.7, 0.2))
		hook.needs = [&"staff_body_pressed"]
		hook.sets = &""
		hook.action_text = "[E] Dip the body in %s" % _room_name(tank)
		hook.hidden_until = &"staff_body_pressed"
		hook.check = func() -> String: return "Dipped" if Egg.has(&"staff_bot_body") else ""
		hook.used.connect(_on_dip.bind(hook))
		dip_order.append(hook)
	_shuffle(dip_order)
	if not tanks.is_empty():
		var coil := _station("HeatingCoil", _tank_edge(tanks[0], -1.0), Vector3(0.8, 0.5, 0.8), Color(0.8, 0.35, 0.1))
		coil.needs = [&"staff_bot_cleared"]
		coil.sets = &"heating_coil"
		coil.action_text = "[E] Rip the heating coil out of the tank"
		coil.missing_text = ""
		coil.hide_when_done = true


func _build_servo(servo: Section) -> void:
	var etch_spot := _first_in_group(servo, "etch_pool")
	if etch_spot:
		var etch := _station("Etch", etch_spot.global_position, Vector3(1.0, 1.0, 1.0), Color(0.4, 0.9, 0.3))
		etch.needs = [&"blank_board"]
		etch.sets = &"board_etched"
		etch.action_text = "[E] Etch the blank board in the acid"
		etch.missing_text = "An etching rack over the acid"
		etch.done_text = "Etched"
		etch.used.connect(_on_etched.bind(etch))
	var solder_spot := _first_in_group(servo, "solder_station")
	if solder_spot:
		var solder := _station("Solder", solder_spot.global_position, Vector3(1.0, 1.0, 1.0), Color(0.75, 0.75, 0.8))
		solder.needs = [&"board_etched"]
		solder.sets = &"staff_bot_circuits"
		solder.action_text = "[E] Solder the Staff Bot's circuits"
		solder.missing_text = "A soldering bench"
		solder.done_text = "Circuits soldered"
		var boot := _station("BootBoard", solder_spot.global_position + Vector3(1.6, 0, 0), Vector3(0.8, 0.8, 0.8), Color(0.3, 0.7, 0.9))
		boot.needs = [&"rigged_part"]
		boot.sets = &"thaw_board"
		boot.action_text = "[E] Solder a boot board"
		boot.hidden_until = &"rigged_part"
		boot.done_text = "Boot board soldered"


func _build_cold(cold: Section) -> void:
	var rack := _first_in_group(cold, "staff_rack")
	if rack == null:
		return
	var assemble := _station("StaffRack", rack.global_position + Vector3.UP * 0.2, Vector3(1.2, 1.8, 0.8), Color(0.45, 0.5, 0.55))
	assemble.needs = [&"staff_bot_body", &"staff_bot_circuits"]
	assemble.sets = &"staff_bot_assembled"
	assemble.action_text = "[E] Assemble the Staff Bot on the rack"
	assemble.missing_text = "An empty staff rack"
	assemble.done_text = ""
	_sleeping_bot = Node3D.new()
	_sleeping_bot.name = "SleepingStaffBot"
	add_child(_sleeping_bot)
	_sleeping_bot.global_position = rack.global_position
	for part in StaffBot.build_body():
		_sleeping_bot.add_child(part)
	_sleeping_bot.visible = false


func _build_line(line: Section) -> void:
	var intake := line.rooms[0]
	var belt := intake.get_node_or_null("Belt") as Node3D
	var at := belt.global_position + Vector3.UP * 0.4 if belt else intake.global_position
	var send := _station("LineSend", at + intake.global_basis.x * 2.0, Vector3(0.8, 1.2, 0.8), Color(0.85, 0.7, 0.2))
	send.needs = [&"staff_bot_assembled"]
	send.sets = &"staff_bot_on_line"
	send.action_text = "[E] Send the Staff Bot down the line"
	send.missing_text = ""
	var end := line.rooms[line.rooms.size() - 1]
	var panel_box := end.get_node_or_null("OverridePanel") as Node3D
	var panel := _station("OverridePanel", panel_box.global_position if panel_box else end.global_position, Vector3(1.2, 1.4, 0.6), Color(0.6, 0.15, 0.15))
	panel.needs = [&"admin_badge"]
	panel.sets = &"line_override"
	panel.action_text = "[E] Swipe the admin badge"
	panel.missing_text = "OVERRIDE  -  admins only"
	panel.done_text = "Override engaged"
	var chute := end.get_node_or_null("ConveyorHome") as Area3D
	if chute:
		chute.body_entered.connect(func(body: Node3D) -> void:
			if body is Player and Egg.has(&"override_chip"):
				Egg.set_flag(&"kill_code"))


func _build_proving(proving: Section) -> void:
	checkpoints = proving.find_children("*", "CheckpointGate", true, false)


func _build_shipping(shipping: Section) -> void:
	var tower := get_node_or_null(tower_path) as Node3D
	if tower == null or shipping.rooms.size() < 2:
		return
	var crane := _station("TowerCrane", tower.global_position + Vector3(9, 0, 9), Vector3(1.2, 1.6, 0.8), Color(0.85, 0.7, 0.2))
	crane.needs = [&"grab_magnet"]
	crane.sets = &"tower_base_crushed"
	crane.action_text = "[E] Hook the Grab Magnet to the crane and drop a container"
	crane.missing_text = "A container crane. Its magnet is missing"
	crane.done_text = "The tower's base is crushed"


# --- Steps --------------------------------------------------------------------------------

func _on_flag(flag: StringName) -> void:
	if DOT_LINES.has(flag) and (Egg.has(&"radio_fixed") or flag == &"radio_fixed"):
		say(DOT_LINES[flag])
	match flag:
		&"staff_body_pressed":
			var names := PackedStringArray()
			for hook in dip_order:
				names.append(hook.action_text.trim_prefix("[E] Dip the body in ").to_upper())
			say("DOT: DIP IT IN THIS ORDER: %s" % ", THEN ".join(names))
		&"staff_bot_assembled":
			if _sleeping_bot:
				_sleeping_bot.visible = true
		&"staff_bot_on_line":
			if _sleeping_bot:
				_sleeping_bot.visible = false
		&"staff_bot_awake":
			_spawn_staff_bot()
		&"tower_base_crushed":
			_crush_tower_base()
		&"line_override":
			_upgrade_giant()


func _on_node_added(node: Node) -> void:
	if node is Dripper and not Egg.has(&"tongs_dropped"):
		(node as Robot).died.connect(_on_dripper_died)


func _on_dripper_died(robot: Robot) -> void:
	if _tong_spot == null or Egg.has(&"tongs_dropped"):
		return
	var d := Vector2(robot.global_position.x - _tong_spot.global_position.x, robot.global_position.z - _tong_spot.global_position.z).length()
	if d > 9.0:
		return
	_tong_kills += 1
	if _tong_kills >= tong_kills or randf() < 0.3:
		Egg.set_flag(&"tongs_dropped")
		say("SOMETHING CLATTERS OUT OF THE MARKED TANK")


func _on_dip(_player: Player, hook: EggStation) -> void:
	if dip_order[dip_done] != hook:
		dip_done = 0
		say("DOT: WRONG TANK! THE COATING'S RUINED. START THE DIPS AGAIN")
		return
	dip_done += 1
	if dip_done >= dip_order.size():
		Egg.set_flag(&"staff_bot_body")
	else:
		say("DOT: GOOD. %d OF %d" % [dip_done, dip_order.size()])


func _on_etched(_player: Player, etch: EggStation) -> void:
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds == null or bug_scene == null:
		return
	for i in 5:
		rounds.spawn_add(bug_scene, etch.global_position + Vector3(randf_range(-6, 6), 0.3, randf_range(-6, 6)))


func _physics_process(_delta: float) -> void:
	if staff_bot == null or Egg.has(&"staff_bot_certified") or (Net.is_session() and not multiplayer.is_server()):
		return
	for gate in checkpoints:
		if stamped.has(gate) or not gate.is_open:
			continue
		if staff_bot.global_position.distance_to(gate.global_position) <= 14.0:
			stamped[gate] = true
			Sfx.broadcast_at(&"gate_open", gate.global_position, 0.0)
			if stamped.size() >= checkpoints.size():
				Egg.set_flag(&"staff_bot_certified")
			else:
				say("STAFF BOT STAMPED  %d / %d" % [stamped.size(), checkpoints.size()])


func _spawn_staff_bot() -> void:
	if staff_bot:
		return
	staff_bot = StaffBot.new()
	staff_bot.name = "StaffBot"
	add_child(staff_bot)
	var giant := get_node_or_null(giant_path) as Node3D
	var leader: Node3D = null
	var best := INF
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		var d := p.global_position.distance_to(giant.global_position) if giant else 0.0
		if d < best:
			best = d
			leader = p
	staff_bot.global_position = (leader.global_position + Vector3(1.5, 0.3, 0)) if leader else global_position


func _crush_tower_base() -> void:
	var tower := get_node_or_null(tower_path) as Node3D
	if tower == null:
		return
	var crate := CSGBox3D.new()
	crate.name = "CrushingContainer"
	crate.size = Vector3(6, 2.6, 2.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.2, 0.15)
	crate.material = mat
	add_child(crate)
	crate.global_position = tower.global_position + Vector3(0, 1.6, 0)
	crate.rotation.z = 0.25


func _upgrade_giant() -> void:
	var giant := get_node_or_null(giant_path) as Boss
	if giant == null:
		return
	giant.beaten = false
	giant.rematch_in = -1
	giant.requires_flag = &"line_override"
	giant.drop_flag = &"override_chip"
	giant.display_name = "THE LINE GIANT MK II"
	giant.drop_text = "THE MK II FALLS APART. AN OVERRIDE CHIP SPARKS IN THE WRECKAGE"
	for prop in ["shoulder_health", "core_health", "head_health"]:
		if prop in giant:
			giant.set(prop, giant.get(prop) * 1.5)


# --- Helpers ------------------------------------------------------------------------------

func _station(station_name: String, at: Vector3, size: Vector3, color: Color, glow := false) -> EggStation:
	var station := EggStation.new()
	station.name = station_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size + Vector3(0.3, 0.3, 0.3) # A little bigger, so it's easy to aim at.
	shape.shape = box
	shape.position.y = size.y / 2.0
	station.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat
	mesh.position.y = size.y / 2.0
	station.add_child(mesh)
	add_child(station)
	station.global_position = at
	stations[station_name] = station
	return station


func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap


func _first_in_group(section: Node, group: String) -> Node3D:
	for n in get_tree().get_nodes_in_group(group):
		if section.is_ancestor_of(n):
			return n as Node3D
	return null


func _find_named(section: Node, node_name: String) -> Node3D:
	var found := section.find_children(node_name, "", true, false)
	return found[0] as Node3D if not found.is_empty() else null


func _room_name(node: Node) -> String:
	var at := node.get_parent()
	while at and not at is Room:
		at = at.get_parent()
	return (at as Room).display_name if at else "the tank"


## A spot just past the edge of a tank's pool, on side `side` (1 or -1) of its x axis.
func _tank_edge(tank: Node3D, side: float) -> Vector3:
	var half := 2.0
	var shape := tank.get_node_or_null("Shape") as CollisionShape3D
	if shape and shape.shape is BoxShape3D:
		half = (shape.shape as BoxShape3D).size.x / 2.0
	var at := tank.global_position + tank.global_basis.x * side * (half + 0.8)
	var room := tank.get_parent()
	while room and not room is Room:
		room = room.get_parent()
	return Vector3(at.x, (room as Node3D).global_position.y if room else at.y, at.z)
