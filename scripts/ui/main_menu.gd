extends Control
## Title screen: play solo, host a co-op game (by IP or through Steam), or join one by IP.
## Steam games are joined from the Steam friends list or an invite, not from this menu.
##
## Two copies on one PC for testing: start one and press Host, start another and press
## Join with the address 127.0.0.1. Command-line shortcuts (after a lone "--"):
##   --host            host straight away
##   --join=IP         join straight away
##   --autostart=N     as host, start the run once N players are in the lobby
##   --net-test=ROLE   run the automated co-op checks (tests/net_probe.gd)

var _status: Label
var _lobby: Label
var _address: LineEdit
var _start: Button
var _invite: Button
var _menu_buttons: Array[Button] = []
var _autostart := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Net.peers_changed.connect(_on_peers_changed)
	Net.joined.connect(func() -> void: _status.text = "Connected. Waiting for the host to start...")
	Net.join_failed.connect(func() -> void: _show_menu("Couldn't connect."))
	Net.session_ended.connect(func(reason: String) -> void: _show_menu(reason))
	Net.steam_lobby_failed.connect(func(reason: String) -> void: _show_menu(reason))
	Net.steam_join_started.connect(_on_steam_join_started)
	_read_command_line()


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.07, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	var title := Label.new()
	title.text = "ROBO ZOMB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2))
	column.add_child(title)

	_menu_buttons.append(_button(column, "Play solo", _on_solo))
	var steam_host := _button(column, "Host on Steam", _on_host_steam)
	if not Net.steam_ready:
		steam_host.disabled = true
		steam_host.tooltip_text = "Steam isn't running or isn't logged in."
	else:
		_menu_buttons.append(steam_host)
	_menu_buttons.append(_button(column, "Host co-op (IP)", _on_host))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host's IP address"
	column.add_child(_address)
	_menu_buttons.append(_button(column, "Join co-op (IP)", _on_join))
	_invite = _button(column, "Invite Steam friends", func() -> void: Net.invite_friends())
	_invite.visible = false
	_start = _button(column, "Start run", func() -> void: Net.start_game())
	_start.visible = false
	_button(column, "Quit", func() -> void: get_tree().quit())

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status)
	_lobby = Label.new()
	_lobby.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_lobby)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _on_solo() -> void:
	Net.leave()
	get_tree().change_scene_to_file(Net.GAME_SCENE)


func _on_host() -> void:
	var error := Net.host()
	if error != OK:
		_status.text = "Couldn't host (error %d). Is another copy already hosting?" % error
		return
	_hide_menu()
	_start.visible = true
	_status.text = "Hosting on port %d. Friends join with your IP address." % Net.DEFAULT_PORT


func _on_host_steam() -> void:
	_hide_menu()
	_status.text = "Creating a Steam lobby..."
	Net.host_steam()


func _on_steam_join_started() -> void:
	_hide_menu()
	_status.text = "Joining your friend's game through Steam..."


func _on_join() -> void:
	var error := Net.join(_address.text.strip_edges())
	if error != OK:
		_status.text = "Couldn't start connecting (error %d)." % error
		return
	_hide_menu()
	_status.text = "Connecting to %s..." % _address.text


func _hide_menu() -> void:
	for button in _menu_buttons:
		button.disabled = true
	_address.editable = false


func _show_menu(message: String) -> void:
	for button in _menu_buttons:
		button.disabled = false
	_address.editable = true
	_start.visible = false
	_invite.visible = false
	_lobby.text = ""
	_status.text = message


func _on_peers_changed() -> void:
	var names := PackedStringArray()
	for id in Net.peers:
		names.append(Net.player_name(id))
	_lobby.text = "In the lobby: " + ", ".join(names)
	if Net.steam_lobby_id and multiplayer.is_server():
		_start.visible = true
		_invite.visible = true
		_status.text = "Steam lobby open. Invite friends, or they can join from your friends list."
	elif Net.steam_lobby_id:
		_status.text = "Connected. Waiting for the host to start..."
	if _autostart > 0 and multiplayer.is_server() and Net.peers.size() >= _autostart:
		Net.start_game.call_deferred()


func _read_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host()
		elif arg.begins_with("--join="):
			_address.text = arg.trim_prefix("--join=")
			_on_join()
		elif arg.begins_with("--autostart="):
			_autostart = int(arg.trim_prefix("--autostart="))
		elif arg.begins_with("--net-test="):
			# The probe follows the player into the game scene and checks co-op from there.
			var probe: Node = load("res://tests/net_probe.gd").new()
			probe.role = arg.trim_prefix("--net-test=")
			get_tree().root.add_child.call_deferred(probe)
