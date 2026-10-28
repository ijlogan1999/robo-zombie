class_name Warden
extends CharacterBody3D
## The factory's enforcer. When a break drags on, he drops in and walks to the
## next-round button to press it himself.
##
## Shoot him and he chases whoever shot him instead, buying time, until he loses
## interest. Destroy him and he comes back unstoppable and heads straight for the button.

enum Mode { TO_BUTTON, ANGRY, DONE }

signal destroyed
signal returned

@export var walk_speed := 3.0
@export var unstoppable_speed := 4.5
@export var chase_speed := 5.5 ## Slower than a sprint, so he can be kited.
@export var turn_speed := 5.0
@export var anger_duration := 8.0 ## He keeps chasing this long after the last hit.
@export var press_range := 2.6
@export var press_time := 1.0
@export var drop_height := 15.0
@export var respawn_delay := 5.0
@export var repath_interval := 0.3

@export_group("Slam attack")
@export var slam_range := 3.2
@export var slam_reach := 4.2 ## The slam still lands if the target is this close when it finishes.
@export var slam_damage := 45.0
@export var slam_windup := 0.8
@export var slam_cooldown := 2.0

var button: Node3D
var spawn_point: Node3D
var mode := Mode.TO_BUTTON
var unstoppable := false
var anger_target: Node3D
var gone := false ## True while destroyed and waiting to come back.

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anger_left := 0.0
var _press_left := -1.0
var _windup_left := -1.0
var _cooldown_left := 0.0
var _repath_left := 0.0
var _eye_material: StandardMaterial3D

@onready var health: HealthComponent = $HealthComponent
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _meshes: Node3D = $Meshes


func _ready() -> void:
	_eye_material = ($Meshes/Eye as MeshInstance3D).get_active_material(0).duplicate()
	$Meshes/Eye.material_override = _eye_material
	health.died.connect(_on_died)
	if not multiplayer.is_server():
		# A co-op copy of the host's Warden: let this game's HUD know he's here.
		var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
		if rounds:
			rounds.warden = self
			rounds.warden_summoned.emit(self)


## Co-op copies follow the host's Warden: show or hide him and pass on his comebacks.
func _process(_delta: float) -> void:
	if multiplayer.is_server():
		return
	if _meshes.visible == gone:
		_meshes.visible = not gone
		if gone:
			destroyed.emit()
		else:
			returned.emit()
	if unstoppable and _eye_material.emission_energy_multiplier < 4.0:
		_eye_material.albedo_color = Color(1.0, 0.95, 0.85)
		_eye_material.emission = Color(1.0, 0.95, 0.85)
		_eye_material.emission_energy_multiplier = 4.0


## Places him high above his spawn point so he falls into the arena.
func drop_in() -> void:
	global_position = spawn_point.global_position + Vector3.UP * drop_height
	velocity = Vector3.ZERO
	Sfx.broadcast_at(&"warden_groan", spawn_point.global_position, 4.0) # The design calls for low noises, never words.


## Called when the next round starts.
func leave() -> void:
	queue_free()


func take_damage(amount: float, hit_position: Vector3, attacker: Node = null) -> bool:
	if gone or unstoppable:
		return false
	if not multiplayer.is_server():
		_net_take_damage.rpc_id(1, amount, hit_position, attacker.get_path() if attacker else NodePath())
		return false
	if attacker is Player:
		anger_target = attacker
		_anger_left = anger_duration
		if mode != Mode.ANGRY:
			mode = Mode.ANGRY
			_press_left = -1.0
	return health.take_damage(amount)


@rpc("any_peer", "reliable")
func _net_take_damage(amount: float, hit_position: Vector3, attacker_path: NodePath) -> void:
	take_damage(amount, hit_position, get_node_or_null(attacker_path))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or gone:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown_left -= delta
	match mode:
		Mode.TO_BUTTON:
			_go_to_button(delta)
		Mode.ANGRY:
			_chase(delta)
		Mode.DONE:
			_set_horizontal_velocity(Vector3.ZERO)
	move_and_slide()


func _go_to_button(delta: float) -> void:
	if _press_left >= 0.0:
		_press_left -= delta
		_set_horizontal_velocity(Vector3.ZERO)
		if _press_left < 0.0:
			button.press(self)
			mode = Mode.DONE
		return
	var to_button := _flat(button.global_position - global_position)
	if to_button.length() <= press_range and is_on_floor():
		_press_left = press_time
		_set_horizontal_velocity(Vector3.ZERO)
		return
	_walk_toward(button.global_position, unstoppable_speed if unstoppable else walk_speed, delta)


func _chase(delta: float) -> void:
	_anger_left -= delta
	if _anger_left <= 0.0 or not is_instance_valid(anger_target) \
			or (anger_target.has_method("is_targetable") and not anger_target.is_targetable()):
		# Lost interest: back to the job.
		anger_target = null
		_windup_left = -1.0
		_eye_material.emission_energy_multiplier = 2.0
		mode = Mode.TO_BUTTON
		return

	var to_target := _flat(anger_target.global_position - global_position)
	if _windup_left >= 0.0:
		_windup_left -= delta
		_set_horizontal_velocity(Vector3.ZERO)
		_face(to_target, delta)
		if _windup_left < 0.0:
			_finish_slam()
	elif to_target.length() <= slam_range and _cooldown_left <= 0.0:
		_windup_left = slam_windup
		_eye_material.emission_energy_multiplier = 8.0
		_set_horizontal_velocity(Vector3.ZERO)
	else:
		_walk_toward(anger_target.global_position, chase_speed, delta)


func _finish_slam() -> void:
	_cooldown_left = slam_cooldown
	_eye_material.emission_energy_multiplier = 2.0
	Sfx.broadcast_at(&"warden_slam", global_position, 2.0)
	if is_instance_valid(anger_target) and anger_target.has_method("take_damage") \
			and global_position.distance_to(anger_target.global_position) <= slam_reach:
		anger_target.take_damage(slam_damage, global_position, self)


func _walk_toward(destination: Vector3, speed: float, delta: float) -> void:
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = repath_interval
		_agent.target_position = destination
	var direction := Vector3.ZERO
	if not _agent.is_navigation_finished():
		direction = _flat(_agent.get_next_path_position() - global_position).normalized()
	_set_horizontal_velocity(direction * speed)
	_face(direction, delta)


func _on_died() -> void:
	gone = true
	anger_target = null
	_windup_left = -1.0
	_meshes.visible = false
	_collision.set_deferred("disabled", true)
	destroyed.emit()
	get_tree().create_timer(respawn_delay).timeout.connect(_come_back)


func _come_back() -> void:
	# Back for good: can't be hurt or distracted, and walks faster.
	unstoppable = true
	gone = false
	health.reset()
	_meshes.visible = true
	_collision.set_deferred("disabled", false)
	_eye_material.albedo_color = Color(1.0, 0.95, 0.85)
	_eye_material.emission = Color(1.0, 0.95, 0.85)
	_eye_material.emission_energy_multiplier = 4.0
	if mode != Mode.DONE:
		mode = Mode.TO_BUTTON
	drop_in()
	returned.emit()


func _face(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta)


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _set_horizontal_velocity(horizontal: Vector3) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
