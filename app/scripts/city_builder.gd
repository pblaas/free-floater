extends Node3D
class_name CityBuilder

## Procedural city for the web-swinging POC.
## Layer 1 = ground (walkable), layer 2 = buildings (webbable).

const GROUND_LAYER := 1
const BUILDING_LAYER := 2

const GRID_SIZE := 15
const SPACING := 17.0
const CITY_SEED := 20261110
const GROUND_SIZE := 640.0
const MIN_ROOF_CLEARANCE := 2.5
const FACADE_W := 128
const FACADE_H := 256
const WINDOW_COLS := 5
const WINDOW_ROWS := 12

@export var build_roof_hud := true

var spawn_point := Vector3(0.0, 30.0, 0.0)
var building_count := 0

var _rng := RandomNumberGenerator.new()
var _textures: Array[ImageTexture] = []
var _roof_mat: StandardMaterial3D


func _ready() -> void:
	_rng.seed = CITY_SEED
	_build_materials()
	_build_ground()
	_build_buildings()
	_build_light_rig()


func _build_materials() -> void:
	var palettes := [
		Color(0.32, 0.34, 0.38),
		Color(0.42, 0.40, 0.37),
		Color(0.24, 0.28, 0.34),
		Color(0.36, 0.30, 0.28),
		Color(0.28, 0.33, 0.30),
	]
	for color in palettes:
		_textures.append(_make_facade_texture(color))
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.2, 0.21, 0.23)
	_roof_mat.roughness = 0.95


func _make_facade_texture(base: Color) -> ImageTexture:
	var img := Image.create(FACADE_W, FACADE_H, false, Image.FORMAT_RGB8)
	img.fill(base)
	for i in 600:
		var shade := _rng.randf_range(-0.05, 0.05)
		var c := base * (1.0 + shade)
		img.set_pixel(_rng.randi() % FACADE_W, _rng.randi() % FACADE_H, c)
	var margin_x := 10.0
	var margin_top := 12.0
	var margin_bottom := 8.0
	var cell_w := (FACADE_W - margin_x * 2.0) / WINDOW_COLS
	var cell_h := (FACADE_H - margin_top - margin_bottom) / WINDOW_ROWS
	for row in WINDOW_ROWS:
		for col in WINDOW_COLS:
			var x0 := int(margin_x + col * cell_w + cell_w * 0.22)
			var y0 := int(margin_top + row * cell_h + cell_h * 0.24)
			var w := int(cell_w * 0.56)
			var h := int(cell_h * 0.52)
			var lit := _rng.randf() < 0.35
			var win := Color(1.0, 0.85, 0.55) if lit else Color(0.09, 0.11, 0.15)
			img.fill_rect(Rect2i(x0, y0, w, h), win)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = GROUND_LAYER
	ground.collision_mask = 0
	add_child(ground)

	var plane := MeshInstance3D.new()
	plane.name = "GroundMesh"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.19)
	mat.roughness = 0.95
	plane.material_override = mat
	ground.add_child(plane)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 0.5, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -0.25, 0.0)
	ground.add_child(shape)


func _build_buildings() -> void:
	var root := Node3D.new()
	root.name = "Buildings"
	add_child(root)

	var half := (GRID_SIZE - 1) * 0.5
	var center := Vector3.ZERO
	var spawn_building: Node3D = null

	for gx in GRID_SIZE:
		for gz in GRID_SIZE:
			var pos := Vector3(
				(gx - half) * SPACING + _rng.randf_range(-1.5, 1.5),
				0.0,
				(gz - half) * SPACING + _rng.randf_range(-1.5, 1.5)
			)
			if pos.length() < SPACING * 0.8:
				continue
			var dist_to_center := (pos - center).length()
			var max_dist := half * SPACING
			var center_bias := 1.0 - clampf(dist_to_center / max_dist, 0.0, 1.0)
			var height := _rng.randf_range(12.0, 22.0) + center_bias * _rng.randf_range(10.0, 30.0)
			var width := _rng.randf_range(7.0, 11.0)
			var depth := _rng.randf_range(7.0, 11.0)
			var building := _make_building(pos, width, depth, height)
			root.add_child(building)
			building_count += 1
			if dist_to_center < SPACING:
				spawn_building = building

	if spawn_building == null and building_count > 0:
		spawn_building = root.get_child(0)
	if spawn_building != null:
		var shape := spawn_building.get_node_or_null("Body/Shape") as CollisionShape3D
		var top := 20.0
		if shape != null and shape.shape is BoxShape3D:
			var box := shape.shape as BoxShape3D
			top = box.size.y
		spawn_point = spawn_building.global_position + Vector3(0.0, top + 1.0, 0.0)


func _make_building(pos: Vector3, width: float, depth: float, height: float) -> Node3D:
	var building := Node3D.new()
	building.name = "Building%03d" % building_count
	building.position = pos

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, depth)
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _textures[_rng.randi() % _textures.size()]
	var tint := _rng.randf_range(0.85, 1.05)
	mat.albedo_color = Color(tint, tint, tint)
	mat.roughness = 0.85
	mesh_instance.material_override = mat
	building.add_child(mesh_instance)
	mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)

	var roof_cap := MeshInstance3D.new()
	roof_cap.name = "RoofCap"
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(width + 0.3, 0.5, depth + 0.3)
	roof_cap.mesh = roof_mesh
	roof_cap.material_override = _roof_mat
	roof_cap.position = Vector3(0.0, height + 0.25, 0.0)
	building.add_child(roof_cap)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = BUILDING_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, depth)
	shape.shape = box
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(shape)
	building.add_child(body)

	if build_roof_hud and _rng.randf() < 0.06:
		var roof := MeshInstance3D.new()
		roof.name = "RoofMarker"
		var marker := BoxMesh.new()
		marker.size = Vector3(1.2, 1.2, 1.2)
		roof.mesh = marker
		roof.position = Vector3(0.0, height + 0.6, 0.0)
		var marker_mat := StandardMaterial3D.new()
		marker_mat.albedo_color = Color(0.95, 0.55, 0.1)
		roof.material_override = marker_mat
		building.add_child(roof)

	return building


func _build_light_rig() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.42, 0.62)
	sky_mat.sky_horizon_color = Color(0.62, 0.65, 0.72)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.14)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.64)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.67, 0.75)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.2

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnv"
	world_env.environment = env
	add_child(world_env)
