class_name WeaponData
extends Resource
## Stats for one weapon type. Each gun is a .tres file that uses this script,
## so new guns are made by duplicating one and changing numbers in the Inspector.

@export var display_name := "Weapon"
@export var view_scene: PackedScene ## First-person model. Needs a "Muzzle" node with a "Flash" child.
@export var fire_sound: StringName = &"rivet_shot" ## A file name in audio/sfx/.

@export_group("Damage")
@export var damage := 20.0
@export var pellets := 1 ## Above 1 for shotguns: each pellet deals full damage.
@export var max_range := 100.0

@export_group("Firing")
@export var rounds_per_minute := 450.0
@export var automatic := true

@export_group("Ammo")
@export var magazine_size := 30
@export var max_reserve := 210
@export var reload_time := 1.8

@export_group("Accuracy")
@export var hip_spread_degrees := 2.5
@export var ads_spread_degrees := 0.35
@export var moving_spread_degrees := 2.0 ## Added at full sprint speed, mostly ignored while aiming.
@export var airborne_spread_degrees := 3.0
@export var spread_per_shot_degrees := 0.5 ## Bloom added by each shot.
@export var max_bloom_degrees := 3.0
@export var bloom_recovery := 8.0 ## Degrees of bloom recovered per second.

@export_group("Recoil")
@export var recoil_pitch_degrees := 0.8
@export var recoil_yaw_degrees := 0.3 ## Random left or right.
@export var ads_recoil_multiplier := 0.6

@export_group("Aiming")
@export var ads_fov := 60.0
@export var ads_time := 0.18 ## Seconds from hip to fully aimed.
@export var ads_move_speed_multiplier := 0.6
@export var hip_position := Vector3(0.22, -0.2, -0.45)
@export var ads_position := Vector3(0.0, -0.085, -0.32)
