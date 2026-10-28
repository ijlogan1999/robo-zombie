extends CanvasLayer
## Shown when the run ends: how far you got, and a button to start a new run.
## Keeps working while the game is paused behind it. In co-op the host starts the next run.

const SHOW_DELAY := 2.0 ## Let the last moment play out before the screen comes up.

@onready var _rounds: RoundManager = get_parent()
@onready var _panel: Control = $Panel
@onready var _summary: Label = $Panel/Summary
@onready var _restart: Button = $Panel/Restart


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_rounds.run_over.connect(_on_run_over)
	_restart.pressed.connect(restart)

	var menu := _restart.duplicate() as Button
	menu.text = "Main menu"
	menu.position.y += 64
	_panel.add_child(menu)
	menu.pressed.connect(func() -> void:
		Net.leave()
		get_tree().paused = false
		get_tree().change_scene_to_file(Net.MENU_SCENE))


func _on_run_over(round_number: int) -> void:
	await get_tree().create_timer(SHOW_DELAY).timeout
	_summary.text = "You made it to round %d" % round_number if round_number > 0 else "You didn't survive round 1"
	if Net.is_session() and not multiplayer.is_server():
		_restart.text = "Waiting for the host..."
		_restart.disabled = true
	_panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_restart.grab_focus()


func restart() -> void:
	get_tree().paused = false
	if Net.is_session():
		Net.start_game() # A new layout for everyone.
	else:
		get_tree().reload_current_scene()
