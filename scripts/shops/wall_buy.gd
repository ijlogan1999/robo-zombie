class_name WallBuy
extends StaticBody3D
## A weapon mounted on the wall, Zombies-style. Buy it to carry it (it replaces the gun
## in your hands if both slots are full). Buying one you already own refills its ammo instead.

@export var weapon: WeaponData
@export var cost := 300
@export var ammo_cost := 150


func _ready() -> void:
	if weapon:
		# Show the actual gun on the board.
		$Display.add_child(weapon.view_scene.instantiate())
		$Sign.text = "%s\n%d" % [weapon.display_name.to_upper(), cost]


func get_prompt(player: Player) -> String:
	var guns := player.weapon_holder
	if not guns.owns(weapon):
		return "[E] Buy %s  -  %d scrap" % [weapon.display_name, cost]
	if guns.needs_ammo(weapon):
		return "[E] Refill %s ammo  -  %d scrap" % [weapon.display_name, ammo_cost]
	return "%s ammo full" % weapon.display_name


func interact(player: Player) -> bool:
	var guns := player.weapon_holder
	if not guns.owns(weapon):
		if not player.try_spend(cost):
			return false
		guns.give_weapon(weapon)
		return true
	if not guns.needs_ammo(weapon) or not player.try_spend(ammo_cost):
		return false
	guns.refill_ammo(weapon)
	return true
