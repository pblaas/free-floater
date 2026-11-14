extends SceneTree

func _init() -> void:
	var city := CityBuilder.new()
	city.name = "DiagCity"
	root.add_child(city)
	await process_frame
	city.set_mode(CityBuilder.Mode.TWILIGHT)
	await process_frame
	var found := false
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_") or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat.emission_enabled:
			found = true
			print("mesh: ", mi.name)
			print("  albedo tex: ", mat.albedo_texture)
			print("  emission tex: ", mat.emission_texture)
			if mat.emission_texture != null:
				var img := mat.emission_texture.get_image()
				print("  emission img size: ", img.get_size(), " format: ", img.get_format())
				var path := "user://diag_mask.png"
				img.save_png(path)
				print("  saved mask to: ", ProjectSettings.globalize_path(path))
			break
	if not found:
		print("no emitting facade mesh found")
	quit()
