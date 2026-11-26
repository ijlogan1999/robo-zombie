extends StaticBody3D
## Whatever starts a boss fight: a bell, a lever, a switch.

var boss: Boss
var prompt := "[E] Start the fight"


func get_prompt(_player: Player) -> String:
	if boss == null or not boss.can_start():
		return ""
	return prompt


func interact(_player: Player) -> bool:
	return boss != null and boss.start()
