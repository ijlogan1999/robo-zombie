extends Node
## Manual check that Steam starts and a lobby can be hosted. Needs Steam running and a window
## (not headless). Run: godot --path . res://tests/steam_smoke.tscn
func _ready() -> void:
	print("steam_ready=", Net.steam_ready)
	if not Net.steam_ready:
		get_tree().quit(1)
		return
	print("logged in as ", Steam.getPersonaName())
	Net.peers_changed.connect(func() -> void:
		print("PASS hosted Steam lobby ", Net.steam_lobby_id, " peers=", Net.peers, " name=", Net.player_name(1))
		Net.leave()
		get_tree().quit(0))
	Net.steam_lobby_failed.connect(func(r: String) -> void:
		print("FAIL ", r)
		get_tree().quit(1))
	Net.host_steam()
	await get_tree().create_timer(15.0).timeout
	print("FAIL timed out waiting for the lobby")
	get_tree().quit(1)
