extends Node3D
class_name CityBuilder

## Procedural city for the web-swinging POC.
## Layer 1 = ground (walkable), layer 2 = buildings (webbable).

signal night_changed(is_night: bool)

const GROUND_LAYER := 1
const BUILDING_LAYER := 2
const SWITCH_LAYER := 8

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
const NIGHT_LIT_EXTRA := 0.16
const NIGHT_SUN_ENERGY := 0.14
const DAY_SUN_ENERGY := 1.1
const NIGHT_SUN_COLOR := Color(0.55, 0.63, 0.95)
const NIGHT_SKY_TOP := Color(0.012, 0.02, 0.05)
const NIGHT_SKY_HORIZON := Color(0.05, 0.06, 0.1)
const NIGHT_GROUND_BOTTOM := Color(0.02, 0.025, 0.04)
const NIGHT_GROUND_HORIZON := Color(0.05, 0.06, 0.1)
const DAY_SKY_TOP := Color(0.28, 0.42, 0.62)
const DAY_SKY_HORIZON := Color(0.62, 0.65, 0.72)
const DAY_GROUND_BOTTOM := Color(0.58, 0.61, 0.68)
const DAY_GROUND_HORIZON := Color(0.62, 0.65, 0.72)
const NIGHT_FOG_COLOR := Color(0.03, 0.04, 0.07)
const DAY_FOG_COLOR := Color(0.62, 0.67, 0.75)
const NIGHT_FOG_DENSITY := 0.0024
const DAY_FOG_DENSITY := 0.0018
const BACKDROP_NIGHT_SCALE := 0.15
const WINDOW_WARM := Color(1.0, 0.72, 0.42)
const NIGHT_WALL_SCALE := 0.32
const NIGHT_WINDOW_ALBEDO := Color(0.42, 0.36, 0.28)
const NEON_GREEN := Color(0.25, 1.0, 0.6)
const NEON_PURPLE := Color(0.66, 0.3, 1.0)
const NEON_TRIM_CHANCE := 0.12
const NEON_STRIP_CHANCE := 0.07
const NEON_WINDOW_CHANCE := 0.18
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

var is_night := false

var _rng := RandomNumberGenerator.new()
var _facade_records: Array[Dictionary] = []
var _facade_mats: Array[Dictionary] = []
var _backdrop_mats: Array[StandardMaterial3D] = []
var _sun: DirectionalLight3D
var _sky: Sky
var _procedural_sky_mat: ProceduralSkyMaterial
var _night_sky_mat: ShaderMaterial
var _sky_mat: ProceduralSkyMaterial
var _env: Environment
var _neon_nodes: Array[GeometryInstance3D] = []
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
		_facade_records.append(_make_facade_pair(color, 0.35, Color.WHITE))
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.2, 0.21, 0.23)
	_roof_mat.roughness = 0.95
	_ac_mat = StandardMaterial3D.new()
	_ac_mat.albedo_color = Color(0.55, 0.56, 0.6)
	_ac_mat.roughness = 0.7
	_tank_mat = StandardMaterial3D.new()
	_tank_mat.albedo_color = Color(0.45, 0.42, 0.4)
	_tank_mat.roughness = 0.8


## Facade texture set for one palette: day albedo, night albedo (darker base,
## more lit windows) and an emission mask that lights the night-lit windows.
func _make_facade_pair(base: Color, lit_chance: float, color: Color) -> Dictionary:
	var plan := PackedByteArray()
	plan.resize(WINDOW_COLS * WINDOW_ROWS)
	for i in plan.size():
		var roll := _rng.randf()
		if roll < lit_chance:
			plan[i] = 1
		elif roll < lit_chance + NIGHT_LIT_EXTRA:
			plan[i] = 3
	return {
		"day": _raster_facade(base, plan, false, false),
		"night": _raster_facade(base * NIGHT_WALL_SCALE, plan, true, false, NIGHT_WINDOW_ALBEDO),
		"mask": _raster_facade(Color.BLACK, plan, true, true),
		"color": color,
		"landmark": false,
	}


func _raster_facade(
	base: Color,
	plan: PackedByteArray,
	night_lit: bool,
	mask_only: bool,
	lit_color := Color(1.0, 0.85, 0.55)
) -> ImageTexture:
	var img := Image.create(FACADE_W, FACADE_H, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK if mask_only else base)
	if not mask_only:
		for i in 3000:
			var shade := _rng.randf_range(-0.05, 0.05)
			img.set_pixel(_rng.randi() % FACADE_W, _rng.randi() % FACADE_H, base * (1.0 + shade))
	var margin_x := 20.0
	var margin_top := 24.0
	var margin_bottom := 16.0
	var cell_w := (FACADE_W - margin_x * 2.0) / WINDOW_COLS
	var cell_h := (FACADE_H - margin_top - margin_bottom) / WINDOW_ROWS
	for row in WINDOW_ROWS:
		for col in WINDOW_COLS:
			var lit := plan[row * WINDOW_COLS + col] == 1 \
				or (night_lit and plan[row * WINDOW_COLS + col] == 3)
			var x0 := int(margin_x + col * cell_w + cell_w * 0.22)
			var y0 := int(margin_top + row * cell_h + cell_h * 0.24)
			var w := int(cell_w * 0.56)
			var h := int(cell_h * 0.52)
			var win := Color.BLACK
			if lit:
				win = Color.WHITE if mask_only else lit_color
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
			var building := _make_building(pos, width, depth, height, _facade_records[_rng.randi() % _facade_records.size()])
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
		if i == 0:
			_spawn_day_switch(tower, pos, width, height)
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


func _make_building(pos: Vector3, width: float, depth: float, height: float, rec: Dictionary, allow_neon := true) -> Node3D:
	var building := Node3D.new()
	building.name = "Building%03d" % building_count
	building.position = pos

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, depth)
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = rec["day"]
	var tint := _rng.randf_range(0.85, 1.05)
	mat.albedo_color = Color(tint, tint, tint)
	mat.roughness = 0.85
	mesh_instance.material_override = mat
	var neon_win := Color(0.0, 0.0, 0.0)
	if allow_neon:
		_spawn_neon(building, width, depth, height)
		if _rng.randf() < NEON_WINDOW_CHANCE:
			neon_win = NEON_GREEN if _rng.randf() < 0.5 else NEON_PURPLE
	_facade_mats.append({"mat": mat, "rec": rec, "neon": neon_win})
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
	var rec := _make_facade_pair(color.lightened(0.3), 0.85, color)
	rec["landmark"] = true
	var building := _make_building(pos, width, depth, height, rec, false)
	building.name = "Landmark%02d" % landmark_count
	building.add_to_group("landmarks")

	var facade := building.get_node("Mesh") as MeshInstance3D
	var mat := facade.material_override as StandardMaterial3D
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	_apply_facade_mode(mat, rec)

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


## Green/purple neon accents, visible only at night: a glowing band around
## some rooflines or vertical strips along building corners.
func _spawn_neon(building: Node3D, width: float, depth: float, height: float) -> void:
	var roll := _rng.randf()
	var neon := NEON_GREEN if _rng.randf() < 0.5 else NEON_PURPLE
	if roll < NEON_TRIM_CHANCE:
		_add_neon_trim(building, width, depth, height, neon)
	elif roll < NEON_TRIM_CHANCE + NEON_STRIP_CHANCE:
		_add_neon_strips(building, width, depth, height, neon)


func _neon_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


func _add_neon_trim(building: Node3D, width: float, depth: float, height: float, color: Color) -> void:
	var trim := MeshInstance3D.new()
	trim.name = "NeonTrim"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width + 0.25, 0.16, depth + 0.25)
	trim.mesh = mesh
	trim.material_override = _neon_mat(color)
	trim.position = Vector3(0.0, height + 0.28, 0.0)
	trim.visible = false
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	building.add_child(trim)
	_neon_nodes.append(trim)


func _add_neon_strips(building: Node3D, width: float, depth: float, height: float, color: Color) -> void:
	var mat := _neon_mat(color)
	for corner in 4:
		var strip := MeshInstance3D.new()
		strip.name = "NeonStrip%d" % corner
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, height, 0.09)
		strip.mesh = mesh
		strip.material_override = mat
		var sx := (width * 0.5 - 0.045) * (1.0 if corner % 2 == 0 else -1.0)
		var sz := (depth * 0.5 - 0.045) * (1.0 if corner < 2 else -1.0)
		strip.position = Vector3(sx, height * 0.5, sz)
		strip.visible = false
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		building.add_child(strip)
		_neon_nodes.append(strip)


func _spawn_day_switch(landmark: Node3D, pos: Vector3, width: float, height: float) -> void:
	var sw := DaySwitch.new()
	sw.name = "DaySwitch"
	sw.position = pos + Vector3(width * 0.28, height + 0.5, width * 0.28)
	sw.toggled.connect(_on_switch_toggled)
	add_child(sw)


func _on_switch_toggled(switch_is_night: bool) -> void:
	set_night(switch_is_night)


## Swap the whole city between day and night: sun/sky/fog, window emission
## on every facade, and dimmed unshaded backdrop silhouettes.
func set_night(night: bool) -> void:
	if is_night == night:
		return
	is_night = night
	_apply_night_lighting()
	for entry in _facade_mats:
		_apply_facade_mode(entry["mat"] as StandardMaterial3D, entry["rec"] as Dictionary, entry["neon"] as Color)
	for mat in _backdrop_mats:
		mat.albedo_color = (mat.get_meta("base") as Color) * (BACKDROP_NIGHT_SCALE if night else 1.0)
	for node in _neon_nodes:
		node.visible = night
	if _sky != null:
		_sky.sky_material = _night_sky_mat if night else _procedural_sky_mat
	night_changed.emit(night)


func toggle_night() -> void:
	set_night(not is_night)


func _apply_facade_mode(mat: StandardMaterial3D, rec: Dictionary, neon := Color(0.0, 0.0, 0.0)) -> void:
	if is_night:
		mat.albedo_texture = rec["night"]
		mat.emission_enabled = true
		mat.emission_texture = rec["mask"]
		if rec["landmark"]:
			mat.emission = (rec["color"] as Color).lightened(0.2)
			mat.emission_energy_multiplier = 1.7
		elif neon.r + neon.g + neon.b > 0.01:
			mat.emission = neon
			mat.emission_energy_multiplier = 1.05
		else:
			mat.emission = WINDOW_WARM
			mat.emission_energy_multiplier = 0.75
	else:
		mat.albedo_texture = rec["day"]
		mat.emission_texture = null
		if rec["landmark"]:
			mat.emission_enabled = true
			mat.emission = (rec["color"] as Color) * 0.25
			mat.emission_energy_multiplier = 0.6
		else:
			mat.emission_enabled = false


func _apply_night_lighting() -> void:
	if _sun != null:
		_sun.light_energy = NIGHT_SUN_ENERGY if is_night else DAY_SUN_ENERGY
		_sun.light_color = NIGHT_SUN_COLOR if is_night else Color(1.0, 1.0, 1.0)
	if _sky_mat != null:
		_sky_mat.sky_top_color = NIGHT_SKY_TOP if is_night else DAY_SKY_TOP
		_sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON if is_night else DAY_SKY_HORIZON
		_sky_mat.ground_bottom_color = NIGHT_GROUND_BOTTOM if is_night else DAY_GROUND_BOTTOM
		_sky_mat.ground_horizon_color = NIGHT_GROUND_HORIZON if is_night else DAY_GROUND_HORIZON
	if _env != null:
		_env.fog_light_color = NIGHT_FOG_COLOR if is_night else DAY_FOG_COLOR
		_env.fog_density = NIGHT_FOG_DENSITY if is_night else DAY_FOG_DENSITY


func _add_roof_prop(building: Node3D, width: float, depth: float, height: float) -> void:
	var roll := _rng.randf()
	var x := _rng.randf_range(-(width * 0.5 - 1.6), width * 0.5 - 1.6)
	var z := _rng.randf_range(-(depth * 0.5 - 1.6), depth * 0.5 - 1.6)
	if roll >= 0.3:
		return
	var prop := MeshInstance3D.new()
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
	mat.set_meta("base", color)
	_backdrop_mats.append(mat)

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
	var base := Color(0.55, 0.58, 0.66)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = base
	mat.set_meta("base", base)
	_backdrop_mats.append(mat)

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
	sun.light_energy = DAY_SUN_ENERGY
	sun.shadow_enabled = true
	add_child(sun)
	_sun = sun

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = DAY_SKY_TOP
	sky_mat.sky_horizon_color = DAY_SKY_HORIZON
	sky_mat.ground_bottom_color = DAY_GROUND_BOTTOM
	sky_mat.ground_horizon_color = DAY_GROUND_HORIZON
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_light_color = DAY_FOG_COLOR
	env.fog_density = DAY_FOG_DENSITY
	env.fog_sky_affect = 0.2
	var night_mat := ShaderMaterial.new()
	night_mat.shader = load("res://assets/shaders/night_sky.gdshader")
	_sky = sky
	_procedural_sky_mat = sky_mat
	_night_sky_mat = night_mat
	_sky_mat = sky_mat
	_env = env

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnv"
	world_env.environment = env
	add_child(world_env)
