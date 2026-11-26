class_name Passage
extends Area3D
## A one-way trip: a conveyor chute, a drop. A player who steps in lands at the arrival.
## Each player's own game moves its own player, so this works the same in co-op.

@export var arrival_id: StringName
@export var enabled := true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or not body is Player or not body.is_multiplayer_authority():
		return
	Arrival.send.call_deferred(body, arrival_id)
