extends Node

var _frame := 0
var _city: CityBuilder
var _mat: StandardMaterial3D
var _mi: MeshInstance3D
var _mask: Texture2D
var _quad: MeshInstance3D
var _quad2: MeshInstance3D


func _ready() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(scene)
	_city = scene.get_node("City")
	_city.set_night(true)
	_city.set_process(false)
	for child in _city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_"):
			continue
		if _mi == null:
			_mi = mi
			_mat = mi.material_override
			_mask = _mat.emission_texture
		else:
			mi.visible = false
	var cam := Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	var spawn: Vector3 = _city.spawn_point
	cam.global_position = spawn + Vector3(8.0, 2.0, 6.0)
	cam.look_at(spawn + Vector3(17.0, -6.0, 0.0), Vector3.UP)
	cam.make_current()

	# duplicate of the same merged mesh, placed close to the camera
	var close := MeshInstance3D.new()
	close.mesh = _mi.mesh
	close.material_override = _mat
	close.position = spawn + Vector3(9.0, -1.5, 6.0)
	close.scale = Vector3(0.15, 0.15, 0.15)
	add_child(close)

	# quad with the same material, same scene
	_quad = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3, 3)
	_quad.mesh = pm
	_quad.material_override = _mat
	_quad.position = spawn + Vector3(9.0, 0.0, 3.0)
	add_child(_quad)
	# quad with a FRESH ImageTexture of the same mask image
	var fresh := ImageTexture.create_from_image((_mask as ImageTexture).get_image())
	var mat2: StandardMaterial3D = _mat.duplicate()
	mat2.emission_texture = fresh
	_quad2 = MeshInstance3D.new()
	_quad2.mesh = pm
	_quad2.material_override = mat2
	_quad2.position = spawn + Vector3(9.0, 0.0, -3.0)
	add_child(_quad2)
	print("ready mask=", _mask, " fresh=", fresh)


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		30:
			_snap("em_a_all_mask")
		32:
			# mips, but no anisotropy
			_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		60:
			_snap("em_m_mips_noaniso")
		62:
			_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		90:
			_snap("em_n_mips_nearest")
		92:
			_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_mat.anisotropic_filtering_level = 2
		120:
			_snap("em_o_mips_aniso2")
	if _frame >= 124:
		get_tree().quit(0)


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://captures/%s.png" % name)
	print("saved ", name)
