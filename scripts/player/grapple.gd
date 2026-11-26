class_name Grapple
extends Node3D
## The grapple: found at the end of the Proving Grounds, one per player. Aim at a grapple
## anchor (a yellow ring) within range and press the grapple key: the line zips you to it.
## Fixed anchors only. It's never needed to get anywhere, it just makes trips faster.
##
## Only the player's own game runs it; the body's position syncs as usual.

const ANCHOR_GROUP := &"grapple_anchors"

@export var reach := 25.0
@export var cooldown := 4.0
@export var speed := 22.0
@export var max_time := 1.6
@export var aim_cone := 0.93 ## Dot product with the camera's forward.

var player: Player
var target: Node3D
var _cooldown_left := 0.0
var _time_left := 0.0
var _rope: MeshInstance3D


func _ready() -> void:
	_rope = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = 1.0
	_rope.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rope.material_override = mat
	_rope.top_level = true
	_rope.visible = false
	add_child(_rope)


func ready_in() -> float:
	return maxf(_cooldown_left, 0.0)


## The anchor the player is aiming at, if one is in reach and in sight.
func aimed_anchor() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var best: Node3D = null
	var best_dot := aim_cone
	for anchor: Node3D in get_tree().get_nodes_in_group(ANCHOR_GROUP):
		var to := anchor.global_position - from
		if to.length() > reach or to.length() < 1.0:
			continue
		var dot := forward.dot(to.normalized())
		if dot <= best_dot:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, anchor.global_position)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(anchor.global_position) > 1.0:
			continue
		best = anchor
		best_dot = dot
	return best


func fire() -> bool:
	if target or _cooldown_left > 0.0:
		return false
	var anchor := aimed_anchor()
	if anchor == null:
		return false
	target = anchor
	_time_left = max_time
	_cooldown_left = cooldown
	player.grappling = true
	Sfx.play_at(&"bolt_fire", player.global_position, -6.0)
	return true


func release() -> void:
	if target == null:
		return
	target = null
	player.grappling = false
	_rope.visible = false
	# Stop at the anchor (don't fly past it), with a little hop up over the edge.
	player.velocity = Vector3(player.velocity.x * 0.25, maxf(player.velocity.y * 0.25, 3.5), player.velocity.z * 0.25)


func _physics_process(delta: float) -> void:
	_cooldown_left -= delta
	if player == null or not player.is_multiplayer_authority():
		return
	if target == null:
		if Input.is_action_just_pressed("grapple") and player.life == Player.Life.ALIVE:
			fire()
		return
	_time_left -= delta
	var to := target.global_position + Vector3.DOWN * 0.8 - player.global_position
	if to.length() < 1.6 or _time_left <= 0.0 or player.life != Player.Life.ALIVE or Input.is_action_just_pressed("jump"):
		release()
		return
	player.velocity = to.normalized() * speed
	var hand := player.global_position + Vector3.UP * 1.2
	var span := target.global_position - hand
	_rope.visible = true
	_rope.global_position = hand + span / 2.0
	_rope.global_basis = Basis(Quaternion(Vector3.UP, span.normalized())).scaled(Vector3(1, span.length(), 1))
