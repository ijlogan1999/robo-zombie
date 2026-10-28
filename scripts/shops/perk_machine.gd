class_name PerkMachine
extends StaticBody3D
## Sells one perk, Zombies-style. Each player can install each perk once.
## The perk's effect lives in Player.apply_perk(), keyed by perk_id.

@export var perk_id: StringName = &"reinforced_chassis"
@export var perk_name := "Reinforced Chassis"
@export var description := "+75 max health"
@export var cost := 250


func _ready() -> void:
	$Sign.text = perk_name.to_upper()


func get_prompt(player: Player) -> String:
	if player.has_perk(perk_id):
		return "%s installed" % perk_name
	return "[E] %s (%s)  -  %d scrap" % [perk_name, description, cost]


func interact(player: Player) -> bool:
	if player.has_perk(perk_id) or not player.try_spend(cost):
		return false
	player.apply_perk(perk_id)
	return true
