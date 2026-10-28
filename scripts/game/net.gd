extends Node
## Co-op sessions: hosting, joining and starting a run. Registered as the "Net" autoload.
##
## Host-based: the host's game runs the robots, rounds, gates and scrap. Each player's
## own game runs their movement, guns, health and wallet, and tells the host about it.
## Players can only join from the lobby, not in the middle of a run.
##
## Two ways to connect: by IP address (ENet, for LAN and the automated tests), or
## through Steam (GodotSteam add-on): the host makes a friends-only Steam lobby and
## friends join from their friends list or an invite. Steam relays the traffic, so
## nobody needs to forward ports.

signal peers_changed
signal joined
signal join_failed
signal session_ended(reason: String)
signal steam_lobby_failed(reason: String)
signal steam_join_started ## Joining a friend's Steam lobby from a Steam invite.

## Valve's shared test app ("Spacewar"). Swap in the game's own ID once it has a Steam page.
const STEAM_APP_ID := 480

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const GAME_SCENE := "res://scenes/levels/junkyard.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var peers: Array[int] = [] ## Everyone in the session, host (1) first.
var layout_seed := 0 ## Shared so every player builds the same rooms.
var in_game := false
var steam_ready := false ## Steam is running and logged in, so Steam hosting can be used.
var steam_lobby_id := 0 ## The Steam lobby we're in, or 0.


func _ready() -> void:
	_init_steam()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: joined.emit())
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(func() -> void: _end_session("The host left the game."))


## True when playing with others (hosting or joined). Solo play has no session.
func is_session() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func host(port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	peers.assign([1])
	peers_changed.emit()
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


## Makes a friends-only Steam lobby. The session starts once Steam confirms it (lobby_created).
func host_steam() -> void:
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)


func join_steam(lobby_id: int) -> void:
	Steam.joinLobby(lobby_id)


## Opens Steam's overlay to invite friends to the lobby.
func invite_friends() -> void:
	if steam_lobby_id:
		Steam.activateGameOverlayInviteDialog(steam_lobby_id)


## A player's display name: their Steam name in a Steam session.
func player_name(id: int) -> String:
	var peer := multiplayer.multiplayer_peer as SteamMultiplayerPeer
	if peer:
		var steam_id := peer.get_steam_id_for_peer_id(id)
		if steam_id:
			return Steam.getFriendPersonaName(steam_id)
	return "Host" if id == 1 else "Player %d" % id


func leave() -> void:
	if is_session():
		multiplayer.multiplayer_peer.close()
	if steam_lobby_id:
		Steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers.clear()
	in_game = false


## Host only: picks the layout and takes everyone into the game.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	if steam_lobby_id:
		Steam.setLobbyJoinable(steam_lobby_id, false) # No joining mid-run.
	var new_seed := randi() % 2_000_000_000 + 1
	_start.rpc(new_seed, peers)


@rpc("authority", "call_local", "reliable")
func _start(new_seed: int, peer_list: Array) -> void:
	layout_seed = new_seed
	peers.assign(peer_list)
	in_game = true
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


@rpc("authority", "reliable")
func _set_peers(peer_list: Array) -> void:
	peers.assign(peer_list)
	peers_changed.emit()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if in_game or peers.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id) # No joining mid-run.
		return
	peers.append(id)
	_set_peers.rpc(peers)
	peers_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not peers.has(id):
		return
	peers.erase(id)
	peers_changed.emit()
	if multiplayer.is_server():
		_set_peers.rpc(peers)
	if in_game:
		get_tree().call_group("game_level", "remove_peer", id)


func _on_connection_failed() -> void:
	leave()
	join_failed.emit()


func _end_session(reason: String) -> void:
	var was_in_game := in_game
	leave()
	session_ended.emit(reason)
	if was_in_game:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE)


func _init_steam() -> void:
	# Headless copies are the automated tests; they use IP connections only.
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists("Steam"):
		return
	var result: Dictionary = Steam.steamInitEx(STEAM_APP_ID, true)
	steam_ready = result.get("status", -1) == Steam.STEAM_API_INIT_RESULT_OK
	if not steam_ready:
		print("Steam not available: ", result.get("verbal", ""))
		return
	Steam.lobby_created.connect(_on_steam_lobby_created)
	Steam.lobby_joined.connect(_on_steam_lobby_joined)
	Steam.join_requested.connect(_on_steam_join_requested)
	# Launched by accepting an invite while the game was closed: Steam adds +connect_lobby <id>.
	var args := OS.get_cmdline_args()
	var at := args.find("+connect_lobby")
	if at != -1 and at + 1 < args.size():
		join_steam.call_deferred(int(args[at + 1]))


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != Steam.RESULT_OK:
		steam_lobby_failed.emit("Steam couldn't create a lobby (error %d)." % result)
		return
	steam_lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "name", "%s's game" % Steam.getPersonaName())
	var peer := SteamMultiplayerPeer.new()
	var error := peer.host_with_lobby(lobby_id)
	if error != OK:
		leave()
		steam_lobby_failed.emit("Couldn't host through Steam (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer
	peers.assign([1])
	peers_changed.emit()


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		return # Our own lobby; hosting is handled in _on_steam_lobby_created.
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		steam_lobby_failed.emit("Couldn't join that game. It may be full or already running.")
		return
	steam_lobby_id = lobby_id
	var peer := SteamMultiplayerPeer.new()
	var error := peer.connect_to_lobby(lobby_id)
	if error != OK:
		leave()
		steam_lobby_failed.emit("Couldn't connect through Steam (error %d)." % error)
		return
	multiplayer.multiplayer_peer = peer


## A friend clicked "Join game" in Steam while our game was already open.
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	if in_game:
		return
	leave()
	join_steam(lobby_id)
	steam_join_started.emit()
