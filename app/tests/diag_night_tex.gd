extends SceneTree

func _init() -> void:
	var city := CityBuilder.new()
	city.name = "DiagCity"
	root.add_child(city)
	await process_frame
	city.set_night(true)
	await process_frame
	var saved := 0
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_") or mi.material_override == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		var albedo: Image = (mat.albedo_texture as ImageTexture).get_image()
		var mask: Image = (mat.emission_texture as ImageTexture).get_image()
		albedo.save_png("user://diag_night_albedo.png")
		mask.save_png("user://diag_night_mask.png")
		# sample some wall pixels between windows
		var center := Vector2i(albedo.get_width() / 2, albedo.get_height() / 2)
		print("mesh: ", mi.name)
		print("  albedo size: ", albedo.get_size(), " format: ", albedo.get_format())
		print("  albedo wall pixel (center-ish): ", albedo.get_pixel(center.x, center.y + 40))
		print("  emission enabled: ", mat.emission_enabled, " energy: ", mat.emission_energy_multiplier)
		print("  emission color: ", mat.emission)
		var mc := Vector2i(mask.get_width() / 2, mask.get_height() / 2)
		print("  mask wall pixel: ", mask.get_pixel(mc.x, mc.y + 40), " size: ", mask.get_size())
		saved += 1
		if saved >= 2:
			break
	print("saved diag images")
	quit()
