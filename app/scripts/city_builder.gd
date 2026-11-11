extends Node3D
class_name CityBuilder

## Procedural city for the web-swinging POC.
## Layer 1 = ground (walkable), layer 2 = buildings (webbable).

const GROUND_LAYER := 1
const BUILDING_LAYER := 2

const GRID_SIZE := 15
const SPACING := 17.0
const CITY_SEED := 20261110
const GROUND_SIZE := 1200.0
const MIN_ROOF_CLEARANCE := 2.5
const FACADE_W := 256
const FACADE_H := 512
const WINDOW_COLS := 8
const WINDOW_ROWS := 24
const POWERUP_COUNT := 14
const AIR_POWERUP_COUNT := 8
const LANDMARK_COLORS := [
	Color(0.82, 0.62, 0.22),
	Color(0.18, 0.62, 0.58),
	Color(0.72, 0.24, 0.34),
	Color(0.28, 0.3, 0.72),
]
const LANDMARK_MIN_HEIGHT := 38.0
const LANDMARK_MAX_HEIGHT := 52.0
const BEACON_RANGE := 34.0

@export var build_roof_hud := true

var spawn_point := Vector3(0.0, 30.0, 0.0)
var building_count := 0
var landmark_count := 0

var _rng := RandomNumberGenerator.new()
var _textures: Array[ImageTexture] = []
var _roof_mat: StandardMaterial3D
var _ac_mat: StandardMaterial3D
var _tank_mat: StandardMaterial3D
var roof_spots: Array[Vector3] = []
var _building_boxes: Array[Dictionary] = []


func _ready() -> void:
	_rng.seed = CITY_SEED
	_build_materials()
	_build_ground()
	_build_buildings()
	_build_powerups()
	_build_light_rig()
	_build_backdrop()


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
	_ac_mat = StandardMaterial3D.new()
	_ac_mat.albedo_color = Color(0.55, 0.56, 0.6)
	_ac_mat.roughness = 0.7
	_tank_mat = StandardMaterial3D.new()
	_tank_mat.albedo_color = Color(0.45, 0.42, 0.4)
	_tank_mat.roughness = 0.8


func _make_facade_texture(base: Color, lit_chance := 0.35) -> ImageTexture:
	var img := Image.create(FACADE_W, FACADE_H, false, Image.FORMAT_RGB8)
	img.fill(base)
	for i in 3000:
		var shade := _rng.randf_range(-0.05, 0.05)
		var c := base * (1.0 + shade)
		img.set_pixel(_rng.randi() % FACADE_W, _rng.randi() % FACADE_H, c)
	var margin_x := 20.0
	var margin_top := 24.0
	var margin_bottom := 16.0
	var cell_w := (FACADE_W - margin_x * 2.0) / WINDOW_COLS
	var cell_h := (FACADE_H - margin_top - margin_bottom) / WINDOW_ROWS
	for row in WINDOW_ROWS:
		for col in WINDOW_COLS:
			var x0 := int(margin_x + col * cell_w + cell_w * 0.22)
			var y0 := int(margin_top + row * cell_h + cell_h * 0.24)
			var w := int(cell_w * 0.56)
			var h := int(cell_h * 0.52)
			var lit := _rng.randf() < lit_chance
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

	var landmark_slots := {
		Vector2i(2, 3): true,
		Vector2i(12, 4): true,
		Vector2i(3, 12): true,
		Vector2i(11, 12): true,
	}

	for gx in GRID_SIZE:
		for gz in GRID_SIZE:
			if landmark_slots.has(Vector2i(gx, gz)):
				continue
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
			roof_spots.append(pos + Vector3(0.0, height + 0.5, 0.0))
			_building_boxes.append({
				"pos": pos,
				"w": width,
				"d": depth,
				"h": height,
			})
			if dist_to_center < SPACING:
				spawn_building = building

	for i in landmark_slots.size():
		var slot: Vector2i = landmark_slots.keys()[i]
		var pos := Vector3(
			(float(slot.x) - half) * SPACING,
			0.0,
			(float(slot.y) - half) * SPACING
		)
		var height := _rng.randf_range(LANDMARK_MIN_HEIGHT, LANDMARK_MAX_HEIGHT)
		var width := _rng.randf_range(12.0, 15.0)
		var depth := _rng.randf_range(12.0, 15.0)
		var color: Color = LANDMARK_COLORS[i % LANDMARK_COLORS.size()]
		var tower := _make_landmark(pos, width, depth, height, color)
		root.add_child(tower)
		building_count += 1
		landmark_count += 1
		roof_spots.append(pos + Vector3(0.0, height + 0.5, 0.0))
		_building_boxes.append({
			"pos": pos,
			"w": width,
			"d": depth,
			"h": height,
		})

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
	_add_roof_prop(building, width, depth, height)

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


func _make_landmark(pos: Vector3, width: float, depth: float, height: float, color: Color) -> Node3D:
	var building := _make_building(pos, width, depth, height)
	building.name = "Landmark%02d" % landmark_count
	building.add_to_group("landmarks")

	var facade := building.get_node("Mesh") as MeshInstance3D
	var mat := facade.material_override as StandardMaterial3D
	mat.albedo_texture = _make_facade_texture(color.lightened(0.3), 0.85)
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = color * 0.25
	mat.emission_energy_multiplier = 0.6

	var antenna := MeshInstance3D.new()
	antenna.name = "Antenna"
	var antenna_mesh := CylinderMesh.new()
	antenna_mesh.top_radius = 0.08
	antenna_mesh.bottom_radius = 0.16
	antenna_mesh.height = 5.0
	antenna.mesh = antenna_mesh
	var antenna_mat := StandardMaterial3D.new()
	antenna_mat.albedo_color = Color(0.75, 0.76, 0.8)
	antenna_mat.metallic = 0.6
	antenna_mat.roughness = 0.35
	antenna.material_override = antenna_mat
	antenna.position = Vector3(0.0, height + 0.5 + 2.5, 0.0)
	building.add_child(antenna)

	var beacon_pos := Vector3(0.0, height + 0.5 + 5.3, 0.0)
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.45
	beacon_mesh.height = 0.9
	beacon.mesh = beacon_mesh
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = color.lightened(0.35)
	beacon.material_override = beacon_mat
	beacon.position = beacon_pos
	building.add_child(beacon)

	var light := OmniLight3D.new()
	light.name = "BeaconLight"
	light.light_color = color.lightened(0.3)
	light.light_energy = 2.5
	light.omni_range = BEACON_RANGE
	light.position = beacon_pos
	building.add_child(light)

	return building


func _add_roof_prop(building: Node3D, width: float, depth: float, height: float) -> void:
	var roll := _rng.randf()
	var prop := MeshInstance3D.new()
	var x := _rng.randf_range(-(width * 0.5 - 1.6), width * 0.5 - 1.6)
	var z := _rng.randf_range(-(depth * 0.5 - 1.6), depth * 0.5 - 1.6)
	if roll < 0.18:
		prop.name = "AcUnit"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.4, 0.7, 1.1)
		prop.mesh = mesh
		prop.material_override = _ac_mat
		prop.position = Vector3(x, height + 0.5 + 0.35, z)
	elif roll < 0.3:
		prop.name = "WaterTank"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.55
		mesh.bottom_radius = 0.6
		mesh.height = 1.1
		prop.mesh = mesh
		prop.material_override = _tank_mat
		prop.position = Vector3(x, height + 0.5 + 0.55, z)
	else:
		return
	building.add_child(prop)


func _build_powerups() -> void:
	var container := Node3D.new()
	container.name = "PowerUps"
	add_child(container)
	var kinds := [PowerUp.LOWGRAV, PowerUp.TURBO]
	for i in POWERUP_COUNT:
		if roof_spots.is_empty():
			break
		var spot := roof_spots[_rng.randi() % roof_spots.size()]
		var pickup := PowerUp.new()
		pickup.kind = kinds[i % kinds.size()]
		pickup.spot_kind = "roof"
		pickup.position = spot + Vector3(0.0, 1.1, 0.0)
		container.add_child(pickup)
	for i in AIR_POWERUP_COUNT:
		var pickup := PowerUp.new()
		pickup.kind = kinds[(POWERUP_COUNT + i) % kinds.size()]
		pickup.spot_kind = "air"
		pickup.position = random_air_spot()
		container.add_child(pickup)


func random_roof_spot() -> Vector3:
	if roof_spots.is_empty():
		return Vector3.ZERO
	return roof_spots[_rng.randi() % roof_spots.size()] + Vector3(0.0, 1.1, 0.0)


func random_air_spot() -> Vector3:
	var bounds := (GRID_SIZE - 1) * 0.5 * SPACING
	for attempt in 24:
		var p := Vector3(
			_rng.randf_range(-bounds, bounds),
			_rng.randf_range(14.0, 44.0),
			_rng.randf_range(-bounds, bounds)
		)
		if p.length() < SPACING * 1.2:
			continue
		if not _inside_building(p):
			return p
	return Vector3(0.0, 30.0, 0.0)


func _inside_building(p: Vector3) -> bool:
	for box in _building_boxes:
		var pos: Vector3 = box["pos"]
		if absf(p.x - pos.x) < float(box["w"]) * 0.5 + 0.6 \
				and absf(p.z - pos.z) < float(box["d"]) * 0.5 + 0.6 \
				and p.y < float(box["h"]) + 1.0:
			return true
	return false


func _build_backdrop() -> void:
	_add_backdrop_boxes(
		"SkylineNear", 70, 150.0, 195.0,
		Vector3(7.0, 14.0, 7.0), Vector3(16.0, 48.0, 16.0),
		Color(0.4, 0.43, 0.5)
	)
	_add_backdrop_boxes(
		"SkylineFar", 90, 240.0, 300.0,
		Vector3(9.0, 20.0, 9.0), Vector3(20.0, 62.0, 20.0),
		Color(0.48, 0.51, 0.58)
	)
	_add_backdrop_mountains()


func _add_backdrop_boxes(
	name: String,
	count: int,
	radius_min: float,
	radius_max: float,
	size_min: Vector3,
	size_max: Vector3,
	color: Color
) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.035, 0.035)
		var r := _rng.randf_range(radius_min, radius_max)
		var w := _rng.randf_range(size_min.x, size_max.x)
		var h := _rng.randf_range(size_min.y, size_max.y)
		var d := _rng.randf_range(size_min.z, size_max.z)
		var pos := Vector3(cos(angle) * r, h * 0.5, sin(angle) * r)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, h, d)), pos))
	var instance := MultiMeshInstance3D.new()
	instance.name = name
	instance.multimesh = mm
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _add_backdrop_mountains() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.58, 0.66)

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.06
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var count := 16
	mm.instance_count = count
	for i in count:
		var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.09, 0.09)
		var r := _rng.randf_range(320.0, 400.0)
		var w := _rng.randf_range(90.0, 170.0)
		var h := _rng.randf_range(60.0, 150.0)
		var pos := Vector3(cos(angle) * r, h * 0.5 - 4.0, sin(angle) * r)
		var basis := Basis.from_scale(Vector3(w, h, w * _rng.randf_range(0.7, 1.3)))
		mm.set_instance_transform(i, Transform3D(basis, pos))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Mountains"
	instance.multimesh = mm
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


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
	sky_mat.ground_bottom_color = Color(0.58, 0.61, 0.68)
	sky_mat.ground_horizon_color = Color(0.62, 0.65, 0.72)
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
