class_name Player
extends CharacterBody3D
## First-person player: walk, sprint, jump, crouch, slide and a light wall-run.
##
## Only the player's multiplayer authority reads input and moves the body, so the
## same scene works for the local player and, later, for co-op teammates.
## Tuning values are exported: select the Player in the editor to tweak them live.

enum State { GROUND, AIR, SLIDE, WALL_RUN }
## ALIVE: playing. DOWNED: body destroyed, waiting for a hack or a teammate.
## HACKING: playing the hack minigame. OUT: signal lost until the next round starts.
enum Life { ALIVE, DOWNED, HACKING, OUT }

signal scrap_changed(amount: int)
signal perks_changed
signal life_changed(life: Life)
signal hack_charges_changed(charges: int)

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var max_pitch_degrees := 89.0
@export var base_fov := 80.0
@export var fast_fov := 88.0 ## FOV while sprinting or sliding.
@export var ads_sensitivity_scale := 0.7 ## Mouse sensitivity multiplier while aiming down sights.

@export_group("Ground movement")
@export var walk_speed := 6.0
@export var sprint_speed := 9.5
@export var crouch_speed := 3.5
@export var ground_acceleration := 60.0
@export var ground_deceleration := 45.0
@export var air_acceleration := 12.0
@export var jump_velocity := 5.2
@export var gravity_scale := 1.6 ## Above 1 for snappier, less floaty jumps.

@export_group("Slide")
@export var slide_min_start_speed := 7.0 ## Must be moving at least this fast to slide.
@export var slide_start_boost := 2.5
@export var slide_friction := 7.0
@export var slide_end_speed := 4.0
@export var slide_slope_acceleration := 14.0 ## Extra speed gained sliding downhill.

@export_group("Wall-run")
@export var wall_run_min_speed := 6.0
@export var wall_run_speed := 9.5
@export var wall_run_max_time := 1.1
@export var wall_run_gravity := 4.0
@export var wall_detach_push := 4.0 ## Sideways push when jumping off. No upward boost.
@export var wall_run_camera_tilt_degrees := 8.0

@export_group("Downed")
@export var bleed_out_time := 30.0 ## How long a downed body waits for a teammate before the signal is lost.
@export var starting_hack_charges := 2
@export var max_hack_charges := 5
@export var revive_health_fraction := 0.5 ## Share of max health you get back up with.
@export var revive_hold_time := 3.0 ## Seconds a teammate holds interact to revive you.
@export var revive_grace_time := 2.0 ## Can't be damaged for this long after getting up.
@export var downed_eye_height := 0.45

@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 1.0
@export var eye_below_top := 0.15
@export var height_change_speed := 12.0

var state := State.AIR
var scrap := 0 ## This player's own wallet. Pickups pay every player (see ScrapPickup).
var perks: Array[StringName] = []
var life := Life.ALIVE
var hack_charges := 0
var hack_tried := false ## Each time you go down you get one hack attempt.
var bleed_out_left := 0.0
var use_sound := &"" ## Reviving plays its own sound.

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _capsule: CapsuleShape3D
var _current_height := 1.8
var _crouching := false
var _wall_normal := Vector3.ZERO
var _last_wall_normal := Vector3.ZERO
var _wall_run_time := 0.0
var _movement_fov := 80.0
var _spawn_transform: Transform3D
var _grace_left := 0.0
var _net_position := Vector3.ZERO ## Where this player's own game last said the body is.
var _net_has_state := false

@onready var health: HealthComponent = $HealthComponent
@onready var weapon_holder: WeaponHolder = $Head/Camera3D/WeaponHolder
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _hud: CanvasLayer = $HUD
@onready var _debug_label: Label = $HUD/Debug
@onready var _hack: HackMinigame = $HUD/HackMinigame


func _ready() -> void:
	# Each player needs its own capsule so crouching doesn't resize everyone's.
	_capsule = (_collision.shape as CapsuleShape3D).duplicate()
	_collision.shape = _capsule
	_current_height = stand_height
	_movement_fov = base_fov
	_spawn_transform = global_transform
	add_to_group("players")
	health.died.connect(_on_died)
	hack_charges = starting_hack_charges
	hack_charges_changed.emit(hack_charges) # The HUD is ready before the player, so tell it.
	_hack.finished.connect(_on_hack_finished)

	var is_local := is_multiplayer_authority()
	_camera.current = is_local
	_hud.visible = is_local
	_body_mesh.visible = not is_local
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := mouse_sensitivity * lerpf(1.0, ads_sensitivity_scale, weapon_holder.aim_blend)
		rotate_y(-event.relative.x * sensitivity)
		_head.rotate_x(-event.relative.y * sensitivity)
		var max_pitch := deg_to_rad(max_pitch_degrees)
		_head.rotation.x = clampf(_head.rotation.x, -max_pitch, max_pitch)
	elif event is InputEventMouseButton and event.pressed:
		# Clicking back into the game recaptures the mouse. Esc is handled by the pause menu.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_puppet_process(delta)
		return
	_grace_left -= delta
	if life != Life.ALIVE:
		_downed_process(delta)
		_send_state()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if state != State.WALL_RUN and not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta

	match state:
		State.GROUND:
			_ground_move(delta, wish_dir, input_dir)
		State.SLIDE:
			_slide_move(delta)
		State.AIR:
			_air_move(delta, wish_dir)
		State.WALL_RUN:
			_wall_run_move(delta)

	move_and_slide()
	if is_on_wall():
		_wall_normal = get_wall_normal()

	_resolve_state(input_dir)
	_update_body_height(delta)
	_update_camera(delta)
	_debug_label.text = "%s   %.1f m/s" % [State.keys()[state], _horizontal_velocity().length()]
	_send_state()


func _ground_move(delta: float, wish_dir: Vector3, input_dir: Vector2) -> void:
	if Input.is_action_just_pressed("jump") and _can_stand():
		velocity.y = jump_velocity
		_crouching = false
		_set_state(State.AIR)
		return
	if Input.is_action_just_pressed("crouch") and not weapon_holder.aiming \
			and _horizontal_velocity().length() >= slide_min_start_speed:
		_start_slide()
		return

	_crouching = Input.is_action_pressed("crouch") or not _can_stand()
	var moving_forward := input_dir.y < -0.1
	var target_speed := walk_speed
	if _crouching:
		target_speed = crouch_speed
	elif Input.is_action_pressed("sprint") and moving_forward and not weapon_holder.aiming:
		target_speed = sprint_speed
	if weapon_holder.weapon:
		target_speed *= lerpf(1.0, weapon_holder.weapon.ads_move_speed_multiplier, weapon_holder.aim_blend)

	var rate := ground_acceleration if wish_dir != Vector3.ZERO else ground_deceleration
	_set_horizontal_velocity(_horizontal_velocity().move_toward(wish_dir * target_speed, rate * delta))


func _start_slide() -> void:
	var horizontal := _horizontal_velocity()
	_set_horizontal_velocity(horizontal.normalized() * (horizontal.length() + slide_start_boost))
	_crouching = true
	_set_state(State.SLIDE)


func _slide_move(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and _can_stand():
		# Slide-jump keeps your momentum.
		velocity.y = jump_velocity
		_crouching = false
		_set_state(State.AIR)
		return

	var horizontal := _horizontal_velocity()
	if is_on_floor():
		var floor_normal := get_floor_normal()
		var downhill := Vector3(floor_normal.x, 0.0, floor_normal.z)
		horizontal += downhill * slide_slope_acceleration * delta
	var speed := maxf(horizontal.length() - slide_friction * delta, 0.0)
	_set_horizontal_velocity(horizontal.normalized() * speed)


func _air_move(delta: float, wish_dir: Vector3) -> void:
	if wish_dir == Vector3.ZERO:
		return
	# Air control can steer, but never pushes you faster than you already are.
	var horizontal := _horizontal_velocity()
	var max_speed := maxf(horizontal.length(), walk_speed)
	_set_horizontal_velocity(horizontal.move_toward(wish_dir * max_speed, air_acceleration * delta))


func _wall_run_move(delta: float) -> void:
	_wall_run_time += delta
	if Input.is_action_just_pressed("jump"):
		velocity += _wall_normal * wall_detach_push
		_end_wall_run()
		return

	var along_wall := _horizontal_velocity().slide(_wall_normal).normalized() * wall_run_speed
	# A slight pull into the wall keeps the body touching it.
	_set_horizontal_velocity(along_wall - _wall_normal * 0.5)
	velocity.y = move_toward(velocity.y, -2.0, wall_run_gravity * delta)


func _resolve_state(input_dir: Vector2) -> void:
	var on_floor := is_on_floor()
	match state:
		State.GROUND:
			if not on_floor:
				_set_state(State.AIR)
		State.SLIDE:
			if not on_floor:
				_set_state(State.AIR)
			elif _horizontal_velocity().length() < slide_end_speed or not Input.is_action_pressed("crouch") \
					or weapon_holder.aiming:
				_set_state(State.GROUND)
		State.AIR:
			if on_floor:
				_last_wall_normal = Vector3.ZERO
				var keep_sliding := _crouching and Input.is_action_pressed("crouch") and not weapon_holder.aiming
				_set_state(State.SLIDE if keep_sliding else State.GROUND)
			elif _can_start_wall_run(input_dir):
				_start_wall_run()
		State.WALL_RUN:
			if on_floor:
				_last_wall_normal = Vector3.ZERO
				_set_state(State.GROUND)
			elif not is_on_wall() or _wall_run_time >= wall_run_max_time or input_dir.y > -0.1 \
					or weapon_holder.aiming:
				_end_wall_run()


func _can_start_wall_run(input_dir: Vector2) -> bool:
	if not is_on_wall() or input_dir.y > -0.1 or weapon_holder.aiming:
		return false
	var normal := get_wall_normal()
	if absf(normal.y) > 0.2:
		return false # Not a vertical wall.
	if _last_wall_normal != Vector3.ZERO and normal.dot(_last_wall_normal) > 0.9:
		return false # Can't run the same wall twice without landing.
	return _horizontal_velocity().slide(normal).length() >= wall_run_min_speed


func _start_wall_run() -> void:
	_wall_normal = get_wall_normal()
	_last_wall_normal = _wall_normal
	_wall_run_time = 0.0
	velocity.y = maxf(velocity.y, 0.0)
	_set_state(State.WALL_RUN)


func _end_wall_run() -> void:
	_set_state(State.AIR)


func _set_state(new_state: State) -> void:
	state = new_state
	if state == State.SLIDE:
		_crouching = true


func _can_stand() -> bool:
	if _current_height >= stand_height - 0.01:
		return true
	return not test_move(global_transform, Vector3.UP * (stand_height - _current_height))


func _update_body_height(delta: float) -> void:
	var target := crouch_height if (_crouching or state == State.SLIDE) else stand_height
	_current_height = move_toward(_current_height, target, height_change_speed * delta)
	_capsule.height = _current_height
	_collision.position.y = _current_height / 2.0
	_head.position.y = _current_height - eye_below_top


func _update_camera(delta: float) -> void:
	var tilt := 0.0
	if state == State.WALL_RUN:
		# Lean away from the wall.
		var side := _wall_normal.dot(global_transform.basis.x)
		tilt = -deg_to_rad(wall_run_camera_tilt_degrees) * signf(side)
	_camera.rotation.z = lerpf(_camera.rotation.z, tilt, 10.0 * delta)

	var going_fast := state == State.SLIDE or _horizontal_velocity().length() > walk_speed + 1.0
	_movement_fov = lerpf(_movement_fov, fast_fov if going_fast else base_fov, 8.0 * delta)
	var aim_fov := weapon_holder.weapon.ads_fov if weapon_holder.weapon else base_fov
	_camera.fov = lerpf(_movement_fov, aim_fov, weapon_holder.aim_blend)


## Called by robots and hazards. Returns true if the hit took the player down.
## In co-op, damage is passed on to the game that owns this player.
func take_damage(amount: float, _from_position: Vector3, _attacker: Node = null) -> bool:
	if not is_multiplayer_authority():
		_net_take_damage.rpc_id(get_multiplayer_authority(), amount)
		return false
	if life != Life.ALIVE or _grace_left > 0.0:
		return false
	return health.take_damage(amount)


## Healing from the round manager (round-end repair). Passed on like damage.
func restore_health(amount: float) -> void:
	if not is_multiplayer_authority():
		_net_restore_health.rpc_id(get_multiplayer_authority(), amount)
		return
	health.heal(amount)


## Robots and the Warden only go after players who are up.
func is_targetable() -> bool:
	return life == Life.ALIVE


## True while this player can still get back up without a teammate.
func can_self_revive() -> bool:
	return life == Life.HACKING or (life == Life.DOWNED and hack_charges > 0 and not hack_tried)


func add_hack_charge() -> bool:
	if hack_charges >= max_hack_charges:
		return false
	hack_charges += 1
	hack_charges_changed.emit(hack_charges)
	_send_status()
	return true


## Uses a charge to start the hack minigame. Only works once per down.
func start_hack() -> bool:
	if life != Life.DOWNED or hack_tried or hack_charges <= 0:
		return false
	hack_charges -= 1
	hack_tried = true
	hack_charges_changed.emit(hack_charges)
	_set_life(Life.HACKING)
	_hack.start()
	return true


## Gets back up: from a successful hack or a teammate's revive.
func revive() -> void:
	if life == Life.ALIVE:
		return
	_hack.stop()
	health.revive(revive_health_fraction)
	_grace_left = revive_grace_time
	Sfx.broadcast_at(&"revive", global_position)
	_crouching = true # Get up from the floor instead of popping up.
	state = State.AIR
	_set_life(Life.ALIVE)


# Teammates interact with a downed player to revive them (hold, like Zombies).
func get_prompt(player: Player) -> String:
	if player == self or not _is_revivable():
		return ""
	return "[Hold E] Revive teammate"


func get_hold_time(_player: Player) -> float:
	return revive_hold_time


func interact(player: Player) -> bool:
	if player == self or not _is_revivable():
		return false
	if is_multiplayer_authority():
		revive()
	else:
		_net_revive.rpc_id(get_multiplayer_authority())
	return true


func _is_revivable() -> bool:
	return life == Life.DOWNED or life == Life.HACKING


## Pickups (run by the host) pay every player; each wallet lives in its owner's game.
func add_scrap(amount: int) -> void:
	if not is_multiplayer_authority():
		_net_add_scrap.rpc_id(get_multiplayer_authority(), amount)
		return
	scrap += amount
	scrap_changed.emit(scrap)


# --- Co-op sync. Each player's own game sends its body's state to everyone else. ---

func _send_state() -> void:
	if Net.is_session():
		_net_state.rpc(global_position, rotation.y, _head.rotation.x, _current_height)


func _send_status() -> void:
	if Net.is_session() and is_multiplayer_authority():
		_net_status.rpc(life, hack_charges, hack_tried)


@rpc("authority", "unreliable_ordered")
func _net_state(at: Vector3, yaw: float, pitch: float, height: float) -> void:
	_net_position = at
	rotation.y = yaw
	_head.rotation.x = pitch
	_current_height = height
	_net_has_state = true


@rpc("authority", "reliable")
func _net_status(new_life: Life, charges: int, tried: bool) -> void:
	hack_charges = charges
	hack_tried = tried
	if new_life == life:
		return
	life = new_life
	visible = life != Life.OUT
	_collision.set_deferred("disabled", life == Life.OUT)
	weapon_holder.visible = life == Life.ALIVE
	life_changed.emit(life)
	get_tree().call_group("round_manager", "check_team")


@rpc("any_peer", "reliable")
func _net_take_damage(amount: float) -> void:
	take_damage(amount, Vector3.ZERO)


@rpc("any_peer", "reliable")
func _net_restore_health(amount: float) -> void:
	restore_health(amount)


@rpc("any_peer", "reliable")
func _net_add_scrap(amount: int) -> void:
	add_scrap(amount)


@rpc("any_peer", "reliable")
func _net_revive() -> void:
	if _is_revivable():
		revive()


## A teammate's body in this game: follows what their game sends.
func _puppet_process(delta: float) -> void:
	if not _net_has_state:
		return
	if global_position.distance_to(_net_position) > 4.0:
		global_position = _net_position # Too far behind (respawn, lag spike): snap.
	else:
		global_position = global_position.lerp(_net_position, minf(1.0, 20.0 * delta))
	_capsule.height = _current_height
	_collision.position.y = _current_height / 2.0
	_head.position.y = maxf(_current_height - eye_below_top, downed_eye_height)
	_body_mesh.scale.y = _current_height / stand_height
	_body_mesh.position.y = _current_height / 2.0


## Spends scrap if the player can afford it. Returns false (and spends nothing) if not.
func try_spend(amount: int) -> bool:
	if scrap < amount:
		return false
	scrap -= amount
	scrap_changed.emit(scrap)
	return true


func has_perk(id: StringName) -> bool:
	return id in perks


## Installs a perk and applies its effect. Perk machines call this after payment.
func apply_perk(id: StringName) -> void:
	if has_perk(id):
		return
	perks.append(id)
	match id:
		&"reinforced_chassis":
			health.max_health += 75.0
			health.heal(75.0)
		_:
			push_warning("Unknown perk: %s" % id)
	perks_changed.emit()


func _on_died() -> void:
	hack_tried = false
	bleed_out_left = bleed_out_time
	Sfx.broadcast_at(&"downed", global_position)
	_set_life(Life.DOWNED)


func _on_hack_finished(success: bool) -> void:
	if life != Life.HACKING:
		return
	if success:
		revive()
	else:
		_set_life(Life.DOWNED) # Teammates can still revive you until you bleed out.


func _set_life(new_life: Life) -> void:
	life = new_life
	life_changed.emit(life)
	_send_status()
	# The round manager ends the run if nobody is left who can get back up.
	get_tree().call_group("round_manager", "check_team")


## The body lies on the floor. The player can still look around.
func _downed_process(delta: float) -> void:
	if life == Life.OUT:
		return
	if not is_on_floor():
		velocity.y -= _gravity * gravity_scale * delta
	_set_horizontal_velocity(_horizontal_velocity().move_toward(Vector3.ZERO, ground_deceleration * delta))
	move_and_slide()

	_crouching = true
	_current_height = move_toward(_current_height, crouch_height, height_change_speed * delta)
	_capsule.height = _current_height
	_collision.position.y = _current_height / 2.0
	_head.position.y = move_toward(_head.position.y, downed_eye_height, 3.0 * delta)
	_camera.rotation.z = lerpf(_camera.rotation.z, 0.35, 4.0 * delta)
	_camera.fov = lerpf(_camera.fov, base_fov, 8.0 * delta)
	_debug_label.text = Life.keys()[life]

	if life == Life.DOWNED:
		if Input.is_action_just_pressed("interact"):
			start_hack()
		bleed_out_left -= delta
		if bleed_out_left <= 0.0:
			_lose_signal()


## Out until the next round starts, then back in a fresh body.
func _lose_signal() -> void:
	_hack.stop()
	visible = false
	_collision.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds and not rounds.round_started.is_connected(_on_round_started_while_out):
		rounds.round_started.connect(_on_round_started_while_out, CONNECT_ONE_SHOT)
	_set_life(Life.OUT)


func _on_round_started_while_out(_round_number: int) -> void:
	if life != Life.OUT:
		return
	# Come back next to a teammate who is still up, or at the start if there isn't one.
	var spot := _spawn_transform
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player != self and player.life == Life.ALIVE:
			spot = player.global_transform.translated(player.global_transform.basis.x * 1.5)
			break
	global_transform = spot
	velocity = Vector3.ZERO
	visible = true
	_collision.set_deferred("disabled", false)
	health.reset()
	_grace_left = revive_grace_time
	state = State.AIR
	_set_life(Life.ALIVE)


## Kicks the view up (and randomly sideways) when a gun fires. Angles in radians.
func apply_recoil(pitch: float, yaw: float) -> void:
	var max_pitch := deg_to_rad(max_pitch_degrees)
	_head.rotation.x = clampf(_head.rotation.x + pitch, -max_pitch, max_pitch)
	rotate_y(yaw)


func horizontal_speed() -> float:
	return _horizontal_velocity().length()


func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _set_horizontal_velocity(horizontal: Vector3) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
