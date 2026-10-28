extends Node
## Plays sound effects from audio/sfx/ by file name. Registered as the "Sfx" autoload.
##
##   Sfx.play(&"buy")                         flat sound: menus, your own gun, HUD
##   Sfx.play_at(&"robot_death", position)    sound out in the world, fades with distance
##
## The sounds are synthesized placeholders (tools/make_placeholder_sfx.py). Drop a real
## .wav or .ogg in with the same name to replace one.

const FOLDER := "res://audio/sfx/"
const MAX_VOICES := 32 ## Oldest sounds get cut off past this, so big fights don't pile up.

var _streams := {}
var _voices: Array[Node] = []


func play(sound: StringName, volume_db := 0.0, pitch_jitter := 0.05) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	_start(player)


func play_at(sound: StringName, at: Vector3, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 6.0
	player.max_distance = 60.0
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.position = at
	_start(player)


## A world sound for everyone in a co-op session. Use it for events that only happen on
## one player's game, like robots (run by the host) or your own body going down.
func broadcast_at(sound: StringName, at: Vector3, volume_db := 0.0) -> void:
	play_at(sound, at, volume_db)
	play_for_others(sound, at, volume_db)


## Like broadcast_at, but not for yourself (your own gunshot is already playing flat).
func play_for_others(sound: StringName, at: Vector3, volume_db := 0.0) -> void:
	if Net.is_session():
		_remote_play_at.rpc(sound, at, volume_db)


@rpc("any_peer", "unreliable")
func _remote_play_at(sound: StringName, at: Vector3, volume_db: float) -> void:
	play_at(sound, at, volume_db)


func _start(player: Node) -> void:
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	_voices.append(player)
	while _voices.size() > MAX_VOICES:
		var oldest: Node = _voices.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_voices = _voices.filter(is_instance_valid)


func _stream(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		var path := FOLDER + sound + ".wav"
		if not ResourceLoader.exists(path):
			path = FOLDER + sound + ".ogg"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
		if _streams[sound] == null:
			push_warning("Sfx: no sound named '%s' in %s" % [sound, FOLDER])
	return _streams[sound]
