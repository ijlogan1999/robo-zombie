extends CanvasLayer
## The local player's on-screen info: crosshair, hit marker, weapon name and ammo.

const HIT_MARKER_TIME := 0.12
const LOW_AMMO_COLOR := Color(1.0, 0.35, 0.3)
const DAMAGE_FLASH_ALPHA := 0.35
const STATUS_TIME := 2.0
const REFUSED_FLASH_TIME := 0.4

var _hit_marker_left := 0.0
var _status_left := 0.0
var _refused_left := 0.0

@onready var _weapons: WeaponHolder = owner.get_node("Head/Camera3D/WeaponHolder")
@onready var _health: HealthComponent = owner.get_node("HealthComponent")
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _shield_bar: ProgressBar = $ShieldBar
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _status: Label = $Status
@onready var _player: Player = owner
@onready var _interactor: Interactor = owner.get_node("Head/Camera3D/Interactor")
@onready var _scrap: Label = $Scrap
@onready var _perks: Label = $Perks
@onready var _prompt: Label = $Prompt
@onready var _crosshair: Label = $Crosshair
@onready var _hit_marker: Label = $HitMarker
@onready var _ammo: Label = $Ammo
@onready var _weapon_name: Label = $WeaponName
@onready var _slots: Label = $Slots
@onready var _hack_charges: Label = $HackCharges
@onready var _downed_info: Label = $DownedInfo


func _ready() -> void:
	_weapons.ammo_changed.connect(_on_ammo_changed)
	_weapons.hit_confirmed.connect(_on_hit_confirmed)
	_weapons.weapons_changed.connect(_on_weapons_changed)
	_on_ammo_changed(_weapons.magazine, _weapons.reserve)
	_on_weapons_changed()
	_health.changed.connect(_on_health_changed)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_on_health_changed()
	_player.scrap_changed.connect(_on_scrap_changed)
	_player.perks_changed.connect(_on_perks_changed)
	_interactor.refused.connect(func() -> void: _refused_left = REFUSED_FLASH_TIME)
	_player.hack_charges_changed.connect(_on_hack_charges_changed)
	_player.life_changed.connect(_on_life_changed)
	_on_scrap_changed(_player.scrap)
	_on_perks_changed()
	_on_hack_charges_changed(_player.hack_charges)


func _process(delta: float) -> void:
	_crosshair.visible = _weapons.aim_blend < 0.5
	_hit_marker_left -= delta
	_hit_marker.visible = _hit_marker_left > 0.0
	_status_left -= delta
	_status.visible = _status_left > 0.0
	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta)

	var prompt := _interactor.prompt()
	if prompt != "" and _interactor.hold_progress > 0.0:
		var filled := roundi(_interactor.hold_progress * 20)
		prompt += "\n" + "|".repeat(filled) + ".".repeat(20 - filled)
	_prompt.visible = prompt != ""
	_prompt.text = prompt
	_update_downed_info()
	_refused_left -= delta
	_prompt.modulate = LOW_AMMO_COLOR if _refused_left > 0.0 else Color.WHITE
	if _weapons.reloading:
		_ammo.text = "RELOADING"


func _on_ammo_changed(magazine: int, reserve: int) -> void:
	var weapon := _weapons.weapon
	_weapon_name.text = weapon.display_name if weapon else ""
	_ammo.text = "%d / %d" % [magazine, reserve]
	var low := weapon != null and magazine <= weapon.magazine_size / 4
	_ammo.modulate = LOW_AMMO_COLOR if low else Color.WHITE


func _on_health_changed() -> void:
	_health_bar.max_value = _health.max_health
	_health_bar.value = _health.health
	_shield_bar.max_value = maxf(_health.max_shields, 1.0)
	_shield_bar.value = _health.shields


## Lists carried weapons by slot number, with the one in hand in brackets.
func _on_weapons_changed() -> void:
	var entries: PackedStringArray = []
	for i in _weapons.slots.size():
		var weapon_name := _weapons.slots[i].weapon.display_name
		entries.append(("[%d %s]" if i == _weapons.active_slot else "%d %s") % [i + 1, weapon_name])
	_slots.text = "   ".join(entries)


func _on_scrap_changed(amount: int) -> void:
	_scrap.text = "SCRAP  %d" % amount


func _on_perks_changed() -> void:
	var names: PackedStringArray = []
	for id in _player.perks:
		names.append(String(id).capitalize())
	_perks.text = "PERKS: " + ", ".join(names) if not names.is_empty() else ""


func _on_damaged(_amount: float) -> void:
	_damage_flash.color.a = DAMAGE_FLASH_ALPHA
	Sfx.play(&"player_hurt", -4.0)


func _on_died() -> void:
	_damage_flash.color.a = 0.8


func _on_hack_charges_changed(charges: int) -> void:
	_hack_charges.text = "HACK CHARGES  %d" % charges


func _on_life_changed(life: Player.Life) -> void:
	_crosshair.visible = life == Player.Life.ALIVE
	if life == Player.Life.ALIVE and _player.health.health < _player.health.max_health:
		_status.text = "BACK ONLINE"
		_status.modulate = Color(0.3, 1.0, 0.5)
		_status_left = STATUS_TIME


func _update_downed_info() -> void:
	var life := _player.life
	_downed_info.visible = life == Player.Life.DOWNED or life == Player.Life.OUT
	if life == Player.Life.ALIVE:
		return
	_crosshair.visible = false
	if life == Player.Life.OUT:
		_downed_info.text = "SIGNAL LOST\nYou'll be back in a new body when the next round starts."
		return
	if life != Player.Life.DOWNED:
		return
	var lines := PackedStringArray(["BODY DESTROYED"])
	if _player.can_self_revive():
		lines.append("[E] Hack into a new body  (%d hack charge%s)" % [_player.hack_charges, "" if _player.hack_charges == 1 else "s"])
	elif _player.hack_tried:
		lines.append("Hack failed")
	else:
		lines.append("No hack charges left")
	lines.append("Teammates can revive you  -  signal lost in %d s" % ceili(_player.bleed_out_left))
	_downed_info.text = "\n".join(lines)


func _on_hit_confirmed(killed: bool) -> void:
	_hit_marker_left = HIT_MARKER_TIME * (2.0 if killed else 1.0)
	Sfx.play(&"kill" if killed else &"hit", -8.0 if killed else -12.0)
	_hit_marker.modulate = LOW_AMMO_COLOR if killed else Color.WHITE
