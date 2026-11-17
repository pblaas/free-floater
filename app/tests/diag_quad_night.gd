extends Node

var _frame := 0


func _ready() -> void:
	var city := CityBuilder.new()
	add_child(city)
	await get_tree().process_frame
	city.set_night(true)
	await get_tree().process_frame

	# night environment copied from the city rig
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.02, 0.03, 0.06)
	sm.sky_horizon_color = Color(0.05, 0.06, 0.1)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.14
	sun.light_color = Color(0.55, 0.63, 0.95)
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# grab the real night facade material
	var mat: StandardMaterial3D = null
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi != null and String(mi.name).begins_with("Facade_"):
			mat = mi.material_override
			break

	var cam := Camera3D.new()
	cam.far = 100.0
	add_child(cam)
	cam.global_position = Vector3(0, 0, 6)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()

	var quad := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(8, 8)
	quad.mesh = mesh
	quad.material_override = mat
	quad.position = Vector3(-4, 0, 0)
	add_child(quad)

	# same material, but UVs spanning 0..2 to test texture repeat
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(1, -4, 0), Vector3(9, -4, 0), Vector3(9, 4, 0), Vector3(1, 4, 0)]
	var uvs := [Vector2(0, 2), Vector2(2, 2), Vector2(2, 0), Vector2(0, 0)]
	for idx in [[0, 3, 2], [0, 2, 1]]:
		for i in idx:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(uvs[i])
			st.add_vertex(corners[i])
	var tiled := MeshInstance3D.new()
	tiled.mesh = st.commit()
	tiled.material_override = mat
	add_child(tiled)
	print("quad test ready")


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://captures/quad_night.png")
		print("saved ", ProjectSettings.globalize_path("user://captures/quad_night.png"))
		get_tree().quit(0)
