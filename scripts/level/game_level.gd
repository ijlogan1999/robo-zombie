extends Node3D
## Sets up a run: the shared room layout and one player body per person in the session.
##
## Every player's game builds the same nodes with the same names, so they can talk to each
## other's copies. The level's own Player node belongs to the host (multiplayer authority 1).
## Each other player gets a "Player_<id>" body controlled by their own game.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@export var section_path := NodePath("NavigationRegion3D/Section")


func _enter_tree() -> void:
	add_to_group("game_level")
	if Net.is_session():
		# Before the section's _ready, so it builds the host's layout.
		(get_node(section_path) as Section).layout_seed = Net.layout_seed


func _ready() -> void:
	if not Net.is_session():
		return
	var host_player: Player = $Player
	var offset := 1
	for id in Net.peers:
		if id == 1:
			continue
		var player: Player = PLAYER_SCENE.instantiate()
		player.name = "Player_%d" % id
		player.set_multiplayer_authority(id)
		player.position = host_player.position + host_player.basis.x * 1.5 * offset
		add_child(player)
		offset += 1


## Called by Net when someone leaves mid-run.
func remove_peer(id: int) -> void:
	var player := get_node_or_null("Player_%d" % id)
	if player:
		player.queue_free()
	get_tree().call_group.call_deferred("round_manager", "check_team")
