extends NavigationRegion3D
## Bakes the walkable area (navmesh) from the level geometry under this node when the level loads.
## Shuffled room layouts will need a fresh navmesh every run, so baking at load time is the default.
##
## Godot's automatic geometry parsing doesn't pick up CSG blocks, so their meshes are gathered here.

signal baked


func _ready() -> void:
	# CSG shapes build their meshes at the end of their first frame, so wait for that before baking.
	await get_tree().process_frame
	await get_tree().physics_frame
	bake_now()


func bake_now() -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	for node in find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if not csg.is_root_shape():
			continue # Child shapes are already merged into their root's mesh.
		var meshes := csg.get_meshes()
		if meshes.size() >= 2 and meshes[1] is Mesh:
			source.add_faces((meshes[1] as Mesh).get_faces(), csg.global_transform)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	if navigation_mesh.get_polygon_count() == 0:
		push_warning("Navmesh bake produced no walkable area (%d source vertices)" % source.get_vertices().size())
	NavigationServer3D.region_set_navigation_mesh(get_rid(), navigation_mesh)
	baked.emit()
