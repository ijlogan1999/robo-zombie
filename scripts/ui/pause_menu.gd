extends CanvasLayer
## Esc menu: resume, leave to the main menu, or quit.
## Solo pauses the game. In co-op the game keeps running (others are still playing).

var _panel: Control


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")

	_panel = ColorRect.new()
	(_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP # Clicks here don't reach the game.
	_panel.visible = false
	add_child(_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	var title := Label.new()
	title.text = "PAUSED" if not Net.is_session() else "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)
	_add_button(column, "Resume", close)
	_add_button(column, "Main menu", _on_main_menu)
	_add_button(column, "Quit", func() -> void: get_tree().quit())


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _panel.visible:
		close()
	else:
		open()


func open() -> void:
	var rounds := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rounds and rounds.phase == RoundManager.Phase.OVER:
		return # The run-over screen is up instead.
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.is_session():
		get_tree().paused = true


func close() -> void:
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not Net.is_session():
		get_tree().paused = false


func _on_main_menu() -> void:
	Net.leave()
	get_tree().paused = false
	get_tree().change_scene_to_file(Net.MENU_SCENE)
