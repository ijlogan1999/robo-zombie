class_name HealthComponent
extends Node
## Health, shields and armor for anything that can be damaged.
##
## Shields absorb damage first and recharge after a short break from taking damage.
## Health never regenerates on its own; it only comes back through heal().
## Armor removes a fraction of all incoming damage (players only, per the design).

signal changed
signal damaged(amount: float)
signal died

@export var max_health := 100.0
@export var max_shields := 0.0
@export_range(0.0, 0.9) var armor := 0.0 ## Fraction of damage removed. 0.2 = 20% less damage.
@export var shield_regen_delay := 3.0 ## Seconds without damage before shields recharge.
@export var shield_regen_rate := 25.0 ## Shield points per second.

var health := 0.0
var shields := 0.0
var dead := false

var _since_damage := 0.0


func _ready() -> void:
	reset()


func reset() -> void:
	health = max_health
	shields = max_shields
	dead = false
	_since_damage = 0.0
	changed.emit()


## Returns true if this damage killed it.
func take_damage(amount: float) -> bool:
	if dead or amount <= 0.0:
		return false
	amount *= 1.0 - armor
	var absorbed := minf(shields, amount)
	shields -= absorbed
	health = maxf(health - (amount - absorbed), 0.0)
	_since_damage = 0.0
	damaged.emit(amount)
	changed.emit()
	if health <= 0.0:
		dead = true
		died.emit()
	return dead


## Brings a dead component back with a share of its health and full shields.
func revive(health_fraction: float) -> void:
	dead = false
	health = maxf(max_health * health_fraction, 1.0)
	shields = max_shields
	_since_damage = 0.0
	changed.emit()


func heal(amount: float) -> void:
	if dead:
		return
	health = minf(health + amount, max_health)
	changed.emit()


func _process(delta: float) -> void:
	if dead or shields >= max_shields:
		return
	_since_damage += delta
	if _since_damage >= shield_regen_delay:
		shields = minf(shields + shield_regen_rate * delta, max_shields)
		changed.emit()
