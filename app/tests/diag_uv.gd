extends SceneTree

func _init() -> void:
	var city := CityBuilder.new()
	city.name = "DiagCity"
	root.add_child(city)
	await process_frame
	await process_frame
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_"):
			continue
		var mesh := mi.mesh as Mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var tan = arrays[Mesh.ARRAY_TANGENT]
			print(mi.name, " surf ", s, " tangents null: ", tan == null,
				" size: ", -1 if tan == null else tan.size())
		break
	quit()
