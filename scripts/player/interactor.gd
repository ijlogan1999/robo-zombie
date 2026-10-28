class_name Interactor
extends RayCast3D
## Finds the interactable the player is looking at and uses it when they press interact.
##
## Anything can be interactable: it just needs get_prompt(player) -> String and
## interact(player) -> bool (false = refused, for example not enough scrap).
## Add get_hold_time(player) -> float to make interact a hold instead of a press (revives).

signal refused

var focused: Node
var hold_progress := 0.0 ## 0 to 1 while holding interact on something that needs a hold.

var _player: Player
var _held_for := 0.0


func _ready() -> void:
	_player = owner as Player
	add_exception(_player)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var hit: Object = get_collider() if is_colliding() and _player.life == Player.Life.ALIVE else null
	var now_focused := hit as Node if hit and hit.has_method("interact") else null
	if now_focused != focused:
		_held_for = 0.0
	focused = now_focused
	hold_progress = 0.0
	if focused == null or focused.get_prompt(_player) == "":
		_held_for = 0.0
		return

	var hold_time: float = focused.get_hold_time(_player) if focused.has_method("get_hold_time") else 0.0
	if hold_time <= 0.0:
		if Input.is_action_just_pressed("interact"):
			_use()
		return
	_held_for = _held_for + delta if Input.is_action_pressed("interact") else 0.0
	hold_progress = clampf(_held_for / hold_time, 0.0, 1.0)
	if _held_for >= hold_time:
		_held_for = 0.0
		_use()


func _use() -> void:
	if not focused.interact(_player):
		Sfx.play(&"refuse", -4.0)
		refused.emit()
		return
	# Interactables can name their own sound in a use_sound property ("" for none).
	var sound: Variant = focused.get("use_sound")
	if sound == null:
		sound = &"buy"
	if sound != &"":
		Sfx.play(sound, -4.0)


## Text to show on screen for whatever the player is looking at, or "" for nothing.
func prompt() -> String:
	return focused.get_prompt(_player) if focused else ""
