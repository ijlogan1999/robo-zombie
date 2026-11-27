class_name GrapplePickup
extends StaticBody3D
## The grapple on its rack at the end of the Proving Grounds. Each player takes their own.


func get_prompt(player: Player) -> String:
	return "" if player.has_grapple() else "[E] Take a grapple  (Q to fire at yellow anchors)"


func interact(player: Player) -> bool:
	if player.has_grapple():
		return false
	player.give_grapple()
	Sfx.play_at(&"gate_open", global_position, -4.0)
	return true
