class_name DipTank
extends HazardZone
## A tank of coating in the Chassis Yard. Standing in it eats at you slowly; a quick dip is
## survivable. Some tanks catch fire whenever the line dips a hot part into them.
## The host decides when a tank burns and tells everyone.

@export var burns := false
@export var calm_damage := 12.0
@export var burn_damage := 45.0
@export var burn_every := 22.0
@export var burn_time := 6.0
@export var warn_time := 2.0
@export var calm_material: Material
@export var burn_material: Material

var burning := false

var _cycle_left := 0.0
var _surface: MeshInstance3D


func _ready() -> void:
	_surface = get_node_or_null("Surface") as MeshInstance3D
	_cycle_left = burn_every * randf_range(0.5, 1.0)
	_set_burning(false)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not burns or (Net.is_session() and not multiplayer.is_server()):
		return
	_cycle_left -= delta
	if _cycle_left <= 0.0:
		var now := not burning
		_cycle_left = burn_time if now else burn_every
		_set_burning(now)
		if Net.is_session():
			_net_burning.rpc(now)


@rpc("authority", "reliable")
func _net_burning(now: bool) -> void:
	_set_burning(now)


func _set_burning(now: bool) -> void:
	burning = now
	damage_per_second = burn_damage if now else calm_damage
	if _surface:
		_surface.material_override = burn_material if now and burn_material else calm_material
	if now:
		Sfx.play_at(&"bolt_fire", global_position + Vector3.UP, 2.0)
