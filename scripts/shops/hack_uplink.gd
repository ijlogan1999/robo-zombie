class_name HackUplink
extends StaticBody3D
## Sells hack charges. Each charge is one attempt at the hack minigame when you go down.

@export var cost := 200


func get_prompt(player: Player) -> String:
	if player.hack_charges >= player.max_hack_charges:
		return "Hack charges full (%d)" % player.hack_charges
	return "[E] Buy a hack charge (have %d)  -  %d scrap" % [player.hack_charges, cost]


func interact(player: Player) -> bool:
	if player.hack_charges >= player.max_hack_charges or not player.try_spend(cost):
		return false
	return player.add_hack_charge()
