extends CanvasLayer
## Round number, robots left, break status, round banners and the Warden's health bar.
## Shared by all players.

const BANNER_TIME := 2.5

var _banner_left := 0.0

@onready var _rounds: RoundManager = get_parent()
@onready var _round_label: Label = $RoundNumber
@onready var _remaining_label: Label = $Remaining
@onready var _banner: Label = $Banner
@onready var _warden_panel: Control = $WardenPanel
@onready var _warden_name: Label = $WardenPanel/Name
@onready var _warden_bar: ProgressBar = $WardenPanel/Health


func _ready() -> void:
	_rounds.round_started.connect(_on_round_started)
	_rounds.round_ended.connect(_on_round_ended)
	_rounds.remaining_changed.connect(_on_remaining_changed)
	_rounds.warden_summoned.connect(_on_warden_summoned)
	var section := get_tree().get_first_node_in_group("section") as Section
	if section:
		section.room_opened.connect(func(room: Room) -> void: _show_banner("%s OPENED" % room.display_name.to_upper()))
	_round_label.text = ""
	_remaining_label.text = ""
	_warden_panel.visible = false


func _process(delta: float) -> void:
	_banner_left -= delta
	_banner.visible = _banner_left > 0.0

	match _rounds.phase:
		RoundManager.Phase.BREAK:
			if _rounds.round_number > 0:
				_remaining_label.text = "Break: press the NEXT ROUND button"
		RoundManager.Phase.COUNTDOWN:
			_remaining_label.text = "Round %d in %d" % [_rounds.round_number + 1, ceili(_rounds.countdown_left)]

	var warden := _rounds.warden
	_warden_panel.visible = is_instance_valid(warden) and not warden.gone
	if _warden_panel.visible:
		_warden_bar.max_value = warden.health.max_health
		_warden_bar.value = warden.health.health
		_warden_name.text = "THE WARDEN  -  UNSTOPPABLE" if warden.unstoppable else "THE WARDEN"


func _on_round_started(number: int) -> void:
	_round_label.text = str(number)
	_show_banner("ROUND %d" % number)
	Sfx.play(&"round_start", -2.0, 0.0)


func _on_round_ended(number: int) -> void:
	_show_banner("ROUND %d COMPLETE" % number)
	Sfx.play(&"round_end", -2.0, 0.0)


func _on_remaining_changed(remaining: int) -> void:
	_remaining_label.text = "Robots left: %d" % remaining


func _on_warden_summoned(warden: Warden) -> void:
	_show_banner("THE WARDEN IS COMING FOR THE BUTTON")
	warden.destroyed.connect(func() -> void: _show_banner("THE WARDEN IS DOWN... FOR NOW"))
	warden.returned.connect(func() -> void: _show_banner("THE WARDEN RETURNS - UNSTOPPABLE"))


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner_left = BANNER_TIME
