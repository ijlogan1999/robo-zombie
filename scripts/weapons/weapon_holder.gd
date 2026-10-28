class_name WeaponHolder
extends Node3D
## Holds and fires the player's weapons: weapon slots, hip-fire, aim down sights, ammo and reloading.
##
## Lives under the player's camera. Shots are instant raycasts from the screen centre;
## anything hit that has a take_damage(amount, position, attacker) method gets damaged.

signal ammo_changed(magazine: int, reserve: int)
signal weapons_changed
signal hit_confirmed(killed: bool)

const MAX_IMPACT_MARKS := 40
const MUZZLE_FLASH_TIME := 0.04
const SWITCH_TIME := 0.35 ## Seconds to bring up a weapon after switching.


## One carried weapon and its ammo.
class WeaponSlot:
	var weapon: WeaponData
	var magazine: int
	var reserve: int

	func _init(data: WeaponData) -> void:
		weapon = data
		magazine = data.magazine_size
		reserve = data.max_reserve


@export var weapon: WeaponData ## The weapon the player starts with.
@export var max_slots := 2 ## A perk will raise this to 3.
## The gun is drawn smaller and closer to the camera so it looks the same but stays
## inside the player's body and doesn't poke through walls.
@export var view_scale := 0.4

## The active weapon's ammo. Other slots keep theirs in `slots` while put away.
var magazine := 0
var reserve := 0
var slots: Array[WeaponSlot] = []
var active_slot := 0
var aim_blend := 0.0 ## 0 = hip, 1 = fully aimed down sights.
var aiming := false ## Aim button held (and allowed). The player cancels sprint, slide and wall-run.
var reloading := false
## Ignore fire/aim while the mouse is free, so the click that recaptures it doesn't shoot.
## Automated tests turn this off because they run without a mouse.
var require_mouse_capture := true

var _player: Player
var _camera: Camera3D
var _view: Node3D
var _flash: Node3D
var _cooldown := 0.0
var _reload_left := 0.0
var _switch_left := 0.0
var _bloom := 0.0
var _kick := 0.0
var _flash_left := 0.0
var _impact_marks: Array[Node3D] = []
var _impact_mesh: SphereMesh


func _ready() -> void:
	_player = owner as Player
	_camera = get_parent() as Camera3D
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.04
	_impact_mesh.height = 0.08
	var impact_material := StandardMaterial3D.new()
	impact_material.albedo_color = Color(0.08, 0.08, 0.08)
	_impact_mesh.material = impact_material
	if weapon:
		slots.append(WeaponSlot.new(weapon))
		_equip_slot(0)


func owns(data: WeaponData) -> bool:
	return _slot_index_of(data) != -1


## Adds a weapon: fills an empty slot, or replaces the one in hand when all slots are full.
## Owning it already just refills its ammo.
func give_weapon(data: WeaponData) -> void:
	if owns(data):
		refill_ammo(data)
		return
	_store_active_ammo()
	if slots.size() < max_slots:
		slots.append(WeaponSlot.new(data))
		_equip_slot(slots.size() - 1)
	else:
		slots[active_slot] = WeaponSlot.new(data)
		_equip_slot(active_slot)


## True if a weapon the player owns is missing any ammo.
func needs_ammo(data: WeaponData) -> bool:
	var index := _slot_index_of(data)
	if index == -1:
		return false
	_store_active_ammo()
	var slot := slots[index]
	return slot.magazine < data.magazine_size or slot.reserve < data.max_reserve


func refill_ammo(data: WeaponData) -> void:
	var index := _slot_index_of(data)
	if index == -1:
		return
	slots[index].magazine = data.magazine_size
	slots[index].reserve = data.max_reserve
	if index == active_slot:
		magazine = data.magazine_size
		reserve = data.max_reserve
		reloading = false
		ammo_changed.emit(magazine, reserve)


func switch_to(index: int) -> void:
	if index == active_slot or index < 0 or index >= slots.size():
		return
	_store_active_ammo()
	_equip_slot(index)


## Current cone of fire in degrees. Moving, jumping and firing fast all widen it.
func current_spread_degrees() -> float:
	var spread := lerpf(weapon.hip_spread_degrees, weapon.ads_spread_degrees, aim_blend)
	var speed_ratio := clampf(_player.horizontal_speed() / _player.sprint_speed, 0.0, 1.0)
	spread += weapon.moving_spread_degrees * speed_ratio * (1.0 - 0.7 * aim_blend)
	if not _player.is_on_floor():
		spread += weapon.airborne_spread_degrees
	return spread + _bloom


func start_reload() -> void:
	if reloading or magazine >= weapon.magazine_size or reserve <= 0:
		return
	reloading = true
	_reload_left = weapon.reload_time
	Sfx.play(&"reload", -6.0)


func _physics_process(delta: float) -> void:
	if weapon == null or not is_multiplayer_authority():
		return
	# No shooting while downed. The gun is put away and comes back up on revive.
	if _player.life != Player.Life.ALIVE:
		if visible:
			visible = false
			aiming = false
			aim_blend = 0.0
			reloading = false
		return
	if not visible:
		visible = true
		_switch_left = SWITCH_TIME
		rotation.x = -0.9
	_cooldown = maxf(_cooldown - delta, 0.0)
	_bloom = move_toward(_bloom, 0.0, weapon.bloom_recovery * delta)
	_handle_switch_input()

	var mouse_captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_mouse_capture
	var switching := _switch_left > 0.0
	aiming = mouse_captured and Input.is_action_pressed("aim") and not reloading and not switching
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta / weapon.ads_time)

	if switching:
		_switch_left -= delta
		return
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return
	if Input.is_action_just_pressed("reload"):
		start_reload()
		return

	var trigger := Input.is_action_pressed("fire") if weapon.automatic else Input.is_action_just_pressed("fire")
	if trigger and mouse_captured and _cooldown <= 0.0:
		if magazine > 0:
			_fire()
		elif reserve > 0:
			start_reload()
		elif Input.is_action_just_pressed("fire"):
			Sfx.play(&"empty")


func _handle_switch_input() -> void:
	if Input.is_action_just_pressed("slot_1"):
		switch_to(0)
	elif Input.is_action_just_pressed("slot_2"):
		switch_to(1)
	elif Input.is_action_just_pressed("slot_3"):
		switch_to(2)
	elif Input.is_action_just_pressed("weapon_next") and slots.size() > 1:
		switch_to((active_slot + 1) % slots.size())


func _process(delta: float) -> void:
	if weapon == null:
		return
	# Gun position: slides from hip to sights, kicks back on each shot, dips while reloading.
	# After a switch it starts lowered and rises into place.
	_kick = move_toward(_kick, 0.0, 0.5 * delta)
	# Teammates' guns are seen from outside, so they stay full size.
	var size := view_scale if is_multiplayer_authority() else 1.0
	position = (weapon.hip_position.lerp(weapon.ads_position, aim_blend) + Vector3(0.0, 0.0, _kick)) * size
	scale = Vector3.ONE * size
	var reload_dip := -0.6 if reloading else 0.0
	rotation.x = lerpf(rotation.x, reload_dip, 10.0 * delta)

	if _flash:
		_flash_left -= delta
		_flash.visible = _flash_left > 0.0


func _equip_slot(index: int) -> void:
	active_slot = index
	var slot := slots[index]
	if _view:
		_view.queue_free()
	weapon = slot.weapon
	magazine = slot.magazine
	reserve = slot.reserve
	_view = weapon.view_scene.instantiate()
	add_child(_view)
	_flash = _view.get_node_or_null("Muzzle/Flash")
	reloading = false
	_cooldown = 0.0 # The raise time is the only wait; the last gun's fire delay doesn't carry over.
	_switch_left = SWITCH_TIME
	rotation.x = -0.9
	Sfx.play(&"switch", -8.0)
	ammo_changed.emit(magazine, reserve)
	weapons_changed.emit()


func _store_active_ammo() -> void:
	if slots.is_empty():
		return
	slots[active_slot].magazine = magazine
	slots[active_slot].reserve = reserve


func _slot_index_of(data: WeaponData) -> int:
	for i in slots.size():
		if slots[i].weapon == data:
			return i
	return -1


func _fire() -> void:
	magazine -= 1
	_cooldown = 60.0 / weapon.rounds_per_minute
	Sfx.play(weapon.fire_sound, -4.0)
	Sfx.play_for_others(weapon.fire_sound, global_position, -4.0)

	var spread := current_spread_degrees()
	for i in weapon.pellets:
		_fire_ray(spread)
	_bloom = minf(_bloom + weapon.spread_per_shot_degrees, weapon.max_bloom_degrees)

	var recoil_scale := lerpf(1.0, weapon.ads_recoil_multiplier, aim_blend)
	_player.apply_recoil(
		deg_to_rad(weapon.recoil_pitch_degrees) * recoil_scale,
		deg_to_rad(randf_range(-weapon.recoil_yaw_degrees, weapon.recoil_yaw_degrees)) * recoil_scale
	)
	_kick = 0.05
	_flash_left = MUZZLE_FLASH_TIME
	ammo_changed.emit(magazine, reserve)


func _fire_ray(spread_degrees: float) -> void:
	# Pick a random direction inside the cone, weighted evenly across its area.
	var view_basis := _camera.global_transform.basis
	var angle := deg_to_rad(spread_degrees) * sqrt(randf())
	var around := randf() * TAU
	var offset := (view_basis.x * cos(around) + view_basis.y * sin(around)) * tan(angle)
	var direction := (-view_basis.z + offset).normalized()

	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * weapon.max_range)
	query.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	_spawn_impact_mark(hit.position)
	var target: Object = hit.collider
	if target and target.has_method("take_damage") and not target is Player: # No friendly fire.
		var killed: bool = target.take_damage(weapon.damage, hit.position, _player)
		hit_confirmed.emit(killed)


func _spawn_impact_mark(at: Vector3) -> void:
	var mark := MeshInstance3D.new()
	mark.mesh = _impact_mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mark)
	mark.global_position = at
	_impact_marks.append(mark)
	if _impact_marks.size() > MAX_IMPACT_MARKS:
		var oldest: Node3D = _impact_marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _finish_reload() -> void:
	var taken := mini(weapon.magazine_size - magazine, reserve)
	magazine += taken
	reserve -= taken
	reloading = false
	ammo_changed.emit(magazine, reserve)
