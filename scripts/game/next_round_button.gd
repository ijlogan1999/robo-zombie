class_name NextRoundButton
extends StaticBody3D
## The big button that ends a break. Pressing it (player or Warden) starts the
## 10-second countdown to the next round. It glows green while it can be pressed.

const READY_COLOR := Color(0.2, 1.0, 0.35)
const IDLE_COLOR := Color(0.6, 0.1, 0.08)
const COUNTDOWN_COLOR := Color(1.0, 0.7, 0.1)

var use_sound := &"button"
var _rounds: RoundManager
var _cap_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("round_button")
	_cap_material = ($Cap as MeshInstance3D).get_active_material(0).duplicate()
	$Cap.material_override = _cap_material


func get_prompt(_player: Player) -> String:
	var rounds := _get_rounds()
	if rounds == null:
		return ""
	match rounds.phase:
		RoundManager.Phase.BREAK:
			return "[E] Start round %d" % (rounds.round_number + 1) if rounds.can_start_countdown() else ""
		RoundManager.Phase.COUNTDOWN:
			return "Round %d starts in %d" % [rounds.round_number + 1, ceili(rounds.countdown_left)]
	return "Round in progress"


func interact(player: Player) -> bool:
	return press(player)


## Starts the countdown. The Warden calls this too.
func press(by: Node) -> bool:
	var rounds := _get_rounds()
	return rounds != null and rounds.start_countdown(by)


func _process(_delta: float) -> void:
	var rounds := _get_rounds()
	if rounds == null:
		return
	var color := IDLE_COLOR
	if rounds.can_start_countdown():
		color = READY_COLOR
	elif rounds.phase == RoundManager.Phase.COUNTDOWN:
		color = COUNTDOWN_COLOR
	_cap_material.albedo_color = color
	_cap_material.emission = color


func _get_rounds() -> RoundManager:
	if _rounds == null:
		_rounds = get_tree().get_first_node_in_group("round_manager") as RoundManager
	return _rounds
