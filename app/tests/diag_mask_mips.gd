extends SceneTree

func _init() -> void:
	var city := CityBuilder.new()
	city.name = "DiagCity"
	root.add_child(city)
	await process_frame
	await process_frame
	city.set_night(true)
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_"):
			continue
		var mat := mi.material_override as StandardMaterial3D
		var mask := mat.emission_texture as ImageTexture
		var img := mask.get_image()
		print("has mips: ", img.has_mipmaps(), " mip count: ", img.get_mipmap_count())
		for level in [1, 2, 3, 4, 6, 8]:
			if level > img.get_mipmap_count():
				break
			var mip: Image = img.get_image_from_mipmap(level)
			var cx := mip.get_width() / 2
			var cy := mip.get_height() / 2
			print("  mip ", level, " size ", mip.get_size(),
				" center px ", mip.get_pixel(cx, cy),
				" corner px ", mip.get_pixel(0, 0))
		break
	quit()
