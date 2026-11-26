class_name GrappleAnchor
extends Marker3D
## Something the grapple can latch onto: a yellow ring on a post, beam or tower.


func _ready() -> void:
	add_to_group(Grapple.ANCHOR_GROUP)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.55
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	ring.rotation.x = PI / 2.0
	add_child(ring)
