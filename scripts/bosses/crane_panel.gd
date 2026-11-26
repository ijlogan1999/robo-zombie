extends StaticBody3D
## The magnet crane's controls, up in the crane control room. See ScrapKing.

var king: Node ## The ScrapKing.


func get_prompt(_player: Player) -> String:
	return king.get_panel_prompt()


func interact(_player: Player) -> bool:
	return king.use_panel()
