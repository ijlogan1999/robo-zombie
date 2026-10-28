class_name HackMinigame
extends Control
## The hacking puzzle a downed player plays to jump into a new body.
##
## A cursor sweeps back and forth along a signal bar. Press fire or jump while it's
## inside the green window to lock a node. Each lock makes the window smaller and the
## cursor faster. Lock every node before time runs out; miss too often and the hack fails.
## Perks and augments will tune these numbers later (easier puzzle, more time).

signal finished(success: bool)

const LOCK_COLOR := Color(0.3, 1.0, 0.5)
const MISS_COLOR := Color(1.0, 0.35, 0.3)
const BAR_COLOR := Color(0.05, 0.12, 0.15, 0.9)
const TEXT_COLOR := Color(0.6, 0.95, 1.0)

@export var nodes_to_lock := 3
@export var allowed_misses := 2 ## One more miss than this fails the hack.
@export var time_limit := 12.0
@export var start_window := 0.22 ## Window width as a share of the bar.
@export var window_shrink := 0.75 ## The window's width is multiplied by this after each lock.
@export var start_speed := 0.9 ## Bar lengths per second.
@export var speed_growth := 1.25
@export var bar_size := Vector2(560, 34)
## Ignore input while false. Automated tests turn this off and call press() directly.
var read_input := true

var running := false
var locked := 0
var misses := 0
var time_left := 0.0
var cursor := 0.0 ## 0 = left end of the bar, 1 = right end.
var window_start := 0.0
var window_width := 0.0

var _direction := 1.0
var _speed := 0.0
var _flash_left := 0.0
var _flash_color := Color.WHITE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func start() -> void:
	running = true
	locked = 0
	misses = 0
	time_left = time_limit
	cursor = 0.0
	_direction = 1.0
	_speed = start_speed
	window_width = start_window
	_place_window()
	show()


func stop() -> void:
	running = false
	hide()


## True when a press right now would lock a node.
func cursor_in_window() -> bool:
	return cursor >= window_start and cursor <= window_start + window_width


func press() -> void:
	if not running:
		return
	if cursor_in_window():
		locked += 1
		_flash(LOCK_COLOR)
		Sfx.play(&"hack_lock", -4.0, 0.0)
		if locked >= nodes_to_lock:
			_finish(true)
			return
		window_width *= window_shrink
		_speed *= speed_growth
		_place_window()
	else:
		misses += 1
		_flash(MISS_COLOR)
		Sfx.play(&"hack_miss", -4.0, 0.0)
		if misses > allowed_misses:
			_finish(false)


func _process(delta: float) -> void:
	_flash_left -= delta
	if not running:
		return
	time_left -= delta
	if time_left <= 0.0:
		_finish(false)
		return
	cursor += _direction * _speed * delta
	if cursor >= 1.0 or cursor <= 0.0:
		cursor = clampf(cursor, 0.0, 1.0)
		_direction = -_direction
	if read_input and (Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("jump")):
		press()
	queue_redraw()


func _place_window() -> void:
	# Keep the new window away from the cursor so a lock never comes for free.
	for attempt in 8:
		window_start = _rng.randf_range(0.03, 0.97 - window_width)
		if absf(window_start + window_width / 2.0 - cursor) > 0.25:
			break


func _flash(color: Color) -> void:
	_flash_color = color
	_flash_left = 0.25


func _finish(success: bool) -> void:
	running = false
	hide()
	Sfx.play(&"hack_success" if success else &"hack_fail", -2.0, 0.0)
	finished.emit(success)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var origin := size / 2.0 - bar_size / 2.0 + Vector2(0, 40)
	var bar := Rect2(origin, bar_size)

	draw_string(font, origin + Vector2(0, -52), "HACKING INTO A NEW BODY", HORIZONTAL_ALIGNMENT_CENTER, bar_size.x, 30, TEXT_COLOR)
	draw_string(font, origin + Vector2(0, -16), "Press LMB or SPACE when the signal is in the green window",
			HORIZONTAL_ALIGNMENT_CENTER, bar_size.x, 16, TEXT_COLOR * Color(1, 1, 1, 0.8))

	draw_rect(bar.grow(4), _flash_color if _flash_left > 0.0 else TEXT_COLOR * Color(1, 1, 1, 0.4), false, 2.0)
	draw_rect(bar, BAR_COLOR)
	draw_rect(Rect2(origin + Vector2(window_start * bar_size.x, 0), Vector2(window_width * bar_size.x, bar_size.y)),
			LOCK_COLOR * Color(1, 1, 1, 0.55))
	var x := origin.x + cursor * bar_size.x
	draw_rect(Rect2(x - 3, origin.y - 8, 6, bar_size.y + 16), Color.WHITE)

	# Node lights, misses left and the timer under the bar.
	var below := origin + Vector2(0, bar_size.y + 34)
	for i in nodes_to_lock:
		var center := below + Vector2(14 + i * 34, -6)
		draw_circle(center, 11, LOCK_COLOR if i < locked else BAR_COLOR)
		draw_arc(center, 11, 0, TAU, 24, LOCK_COLOR, 2.0)
	var misses_left := allowed_misses - misses
	draw_string(font, below + Vector2(0, 0), "Misses left: %d     %.1f s" % [misses_left, maxf(time_left, 0.0)],
			HORIZONTAL_ALIGNMENT_RIGHT, bar_size.x, 18, MISS_COLOR if misses_left == 0 else TEXT_COLOR)
