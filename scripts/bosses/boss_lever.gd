extends StaticBody3D
## Whatever starts a boss fight: a bell, a lever, a switch.

var boss: Boss
var prompt := "[E] Start the fight"


func get_prompt(_player: Player) -> String:
	if boss == null:
		return ""
	if boss.has_method("lever_prompt"):
		return boss.lever_prompt(prompt)
	return prompt if boss.can_start() else ""


func interact(_player: Player) -> bool:
	return boss != null and boss.start()
