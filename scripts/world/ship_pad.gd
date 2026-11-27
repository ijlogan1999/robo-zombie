class_name ShipPad
extends Node3D
## A landing pad in the Shipping Bay. Now and then a cargo ship comes down on it and later
## takes off again. The pad's lights flash first; while the ship is landing or lifting off,
## its rocket exhaust burns anything under it. Parked, the ship is cover.
##
## The host times the visits and tells everyone; each game's exhaust hurts its own player.

enum State { IDLE, WARN, LANDING, PARKED, LIFTING }

@export var exhaust_radius := 5.0
@export var exhaust_damage := 45.0 ## Per second.
@export var idle_min := 20.0
@export var idle_max := 40.0
@export var warn_time := 3.0
@export var move_time := 4.0
@export var parked_time := 12.0
@export var sky_height := 45.0
@export var park_height := 1.0

var state := State.IDLE

var _left := 0.0
var _ship: AnimatableBody3D
var _exhaust: HazardZone
var _plume: MeshInstance3D
var _lights: Array[MeshInstance3D] = []
var _blink := 0.0


func _ready() -> void:
	add_to_group(&"ship_pads")
	_build()
	_left = randf_range(idle_min * 0.3, idle_max * 0.6)
	_place(sky_height)
	_ship.visible = false


func _physics_process(delta: float) -> void:
	_blink += delta
	var flash := state == State.WARN or state == State.LANDING or state == State.LIFTING
	for light in _lights:
		light.visible = not flash or int(_blink * 6.0) % 2 == 0
	match state:
		State.LANDING:
			_place(maxf(_ship.position.y - (sky_height - park_height) / move_time * delta, park_height))
		State.LIFTING:
			_place(minf(_ship.position.y + (sky_height - park_height) / move_time * delta, sky_height))
	if Net.is_session() and not multiplayer.is_server():
		return
	_left -= delta
	if _left > 0.0:
		return
	match state:
		State.IDLE:
			_go(State.WARN)
		State.WARN:
			_go(State.LANDING)
		State.LANDING:
			_go(State.PARKED)
		State.PARKED:
			_go(State.LIFTING)
		State.LIFTING:
			_go(State.IDLE)


func _go(new_state: State) -> void:
	if Net.is_session() and multiplayer.is_server():
		_net_state.rpc(new_state)
	set_state(new_state)


func set_state(new_state: State) -> void:
	state = new_state
	var burning := state == State.LANDING or state == State.LIFTING
	_exhaust.monitoring = burning
	_exhaust.damage_per_second = exhaust_damage if burning else 0.0
	_plume.visible = burning
	_ship.visible = state != State.IDLE and state != State.WARN
	match state:
		State.IDLE:
			_left = randf_range(idle_min, idle_max)
			_place(sky_height)
		State.WARN:
			_left = warn_time
		State.LANDING:
			_left = move_time
			_place(sky_height)
			Sfx.play_at(&"bolt_fire", global_position + Vector3.UP * 10.0, 6.0)
		State.PARKED:
			_left = parked_time
			_place(park_height)
		State.LIFTING:
			_left = move_time
			Sfx.play_at(&"bolt_fire", global_position + Vector3.UP * 4.0, 6.0)


func _place(height: float) -> void:
	_ship.position.y = height
	var gap := maxf(height, 0.5)
	_plume.position.y = gap / 2.0
	(_plume.mesh as CylinderMesh).height = gap


func _build() -> void:
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = exhaust_radius + 1.0
	disc.bottom_radius = exhaust_radius + 1.0
	disc.height = 0.06
	pad.mesh = disc
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.25, 0.25, 0.27)
	pad.material_override = pad_mat
	pad.position.y = 0.03
	add_child(pad)
	for i in 6:
		var a := TAU * i / 6.0
		var light := MeshInstance3D.new()
		var bulb := BoxMesh.new()
		bulb.size = Vector3(0.4, 0.15, 0.4)
		light.mesh = bulb
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.3, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.3, 0.1)
		mat.emission_energy_multiplier = 2.0
		light.material_override = mat
		light.position = Vector3(cos(a), 0, sin(a)) * (exhaust_radius + 0.6) + Vector3.UP * 0.1
		add_child(light)
		_lights.append(light)
	_ship = AnimatableBody3D.new()
	_ship.name = "Ship"
	_ship.sync_to_physics = false
	add_child(_ship)
	var hull_shape := CollisionShape3D.new()
	var hull_box := BoxShape3D.new()
	hull_box.size = Vector3(8, 4, 12)
	hull_shape.shape = hull_box
	hull_shape.position.y = 3.0
	_ship.add_child(hull_shape)
	for part in [[Vector3(8, 4, 12), Vector3(0, 3, 0), Color(0.55, 0.58, 0.6)], [Vector3(4, 2, 4), Vector3(0, 6, -3), Color(0.3, 0.32, 0.35)],
			[Vector3(14, 0.5, 3), Vector3(0, 3, 3), Color(0.45, 0.47, 0.5)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[2]
		mesh.material_override = mat
		mesh.position = part[1]
		_ship.add_child(mesh)
	_exhaust = HazardZone.new()
	_exhaust.damage_per_second = 0.0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = exhaust_radius
	cyl.height = 4.0
	shape.shape = cyl
	shape.position.y = 2.0
	_exhaust.add_child(shape)
	add_child(_exhaust)
	_plume = MeshInstance3D.new()
	var plume := CylinderMesh.new()
	plume.top_radius = 1.5
	plume.bottom_radius = exhaust_radius
	plume.height = 1.0
	_plume.mesh = plume
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.55, 0.15, 0.55)
	fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.emission_enabled = true
	_plume.material_override = fire
	_plume.visible = false
	add_child(_plume)


@rpc("authority", "reliable")
func _net_state(new_state: State) -> void:
	set_state(new_state)
