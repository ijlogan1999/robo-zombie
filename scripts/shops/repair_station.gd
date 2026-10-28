class_name RepairStation
extends StaticBody3D
## Repair bay terminal: trades scrap for health. Health never regenerates on its own,
## so this is one of the dependable ways to recover.

@export var repair_amount := 50.0
@export var cost := 40


func get_prompt(player: Player) -> String:
	if player.health.health >= player.health.max_health:
		return "Chassis fully repaired"
	return "[E] Repair %d health  -  %d scrap" % [repair_amount, cost]


func interact(player: Player) -> bool:
	if player.health.health >= player.health.max_health or not player.try_spend(cost):
		return false
	player.health.heal(repair_amount)
	return true
