class_name CheckpointGate
extends Gate
## A Proving Grounds checkpoint. It can't be bought: players hold the pad in front of it
## while robots pour in, and it opens when the hold is done. The host counts the hold.

@export var hold_time := 20.0
@export var pad_radius := 5.0

var pad_at := Vector3.ZERO ## World position of the pad (set by the section).
var armed := false ## Only the next checkpoint along counts a hold.
var progress := 0.0 ## 0..1

var _sync_left := 0.0


func get_prompt(_player: Player) -> String:
	if is_open:
		return ""
	if not armed:
		return "Checkpoint  -  locked"
	return "Checkpoint  -  hold the pad to open it (%d%%)" % roundi(progress * 100.0)


func interact(_player: Player) -> bool:
	return false


func players_on_pad() -> int:
	var count := 0
	for p: Player in get_tree().get_nodes_in_group("players"):
		if p.is_targetable() and Vector2(p.global_position.x - pad_at.x, p.global_position.z - pad_at.z).length() <= pad_radius \
				and absf(p.global_position.y - pad_at.y) < 3.0:
			count += 1
	return count


func _physics_process(delta: float) -> void:
	if is_open or not armed or (Net.is_session() and not multiplayer.is_server()):
		return
	if players_on_pad() > 0:
		progress = minf(progress + delta / hold_time, 1.0)
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = 0.5
		_show_progress()
		if Net.is_session():
			_net_progress.rpc(progress, armed)
	if progress >= 1.0:
		open()


@rpc("authority", "unreliable_ordered")
func _net_progress(value: float, is_armed: bool) -> void:
	progress = value
	armed = is_armed
	_show_progress()


func _show_progress() -> void:
	var text := "CHECKPOINT\n%d%%" % roundi(progress * 100.0)
	$Barricade/SignFront.text = text
	$Barricade/SignBack.text = text


func _ready() -> void:
	super._ready()
	_show_progress()
