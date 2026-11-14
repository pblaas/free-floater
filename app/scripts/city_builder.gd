extends Node3D
class_name CityBuilder

## Procedural city for the web-swinging POC.
## Layer 1 = ground (walkable), layer 2 = buildings (webbable).
## Buildings render as merged facade meshes (grouped by palette + tint);
## collision stays per-building so webbing/landing are unchanged.

signal night_changed(is_night: bool)

enum Mode { DAY, NIGHT, TWILIGHT }

const GROUND_LAYER := 1
const BUILDING_LAYER := 2
const SWITCH_LAYER := 8

const GRID_SIZE := 15
const SPACING := 17.0
const CITY_SEED := 20261110
const GROUND_SIZE := 1200.0
const MIN_ROOF_CLEARANCE := 2.5
const FACADE_W := 512
const FACADE_H := 1024
const LANDMARK_FACADE_W := 256
const LANDMARK_FACADE_H := 512
const TILE_COLS := 6
const TILE_ROWS := 4
const TILE_W_METERS := 12.0
const TILE_H_METERS := 12.0
const WINDOW_W_FRAC := 0.84
const WINDOW_H_FRAC := 0.72
const TINT_SHADES := [0.85, 0.95, 1.0, 1.05]
const SETBACK_TALL := 30.0
const SETBACK_MID := 21.0
const POWERUP_COUNT := 14
const AIR_POWERUP_COUNT := 8
const NIGHT_LIT_EXTRA := 0.16
const NIGHT_SUN_ENERGY := 0.14
const DAY_SUN_ENERGY := 1.1
const NIGHT_SUN_COLOR := Color(0.55, 0.63, 0.95)
const DAY_SUN_COLOR := Color(1.0, 0.95, 0.85)
const DAY_AMBIENT_SKY := 0.7
const NIGHT_AMBIENT_SKY := 1.0
const TWILIGHT_AMBIENT_SKY := 0.85
const SHADOW_MAX_DISTANCE := 160.0
const NIGHT_SKY_TOP := Color(0.012, 0.02, 0.05)
const NIGHT_SKY_HORIZON := Color(0.05, 0.06, 0.1)
const NIGHT_GROUND_BOTTOM := Color(0.02, 0.025, 0.04)
const NIGHT_GROUND_HORIZON := Color(0.05, 0.06, 0.1)
const DAY_SKY_TOP := Color(0.28, 0.42, 0.62)
const DAY_SKY_HORIZON := Color(0.62, 0.65, 0.72)
const DAY_GROUND_BOTTOM := Color(0.58, 0.61, 0.68)
const DAY_GROUND_HORIZON := Color(0.62, 0.65, 0.72)
const NIGHT_FOG_COLOR := Color(0.03, 0.04, 0.07)
const DAY_FOG_COLOR := Color(0.56, 0.61, 0.7)
const NIGHT_FOG_DENSITY := 0.0012
const DAY_FOG_DENSITY := 0.0006
const DAY_FOG_HEIGHT := 16.0
const NIGHT_FOG_HEIGHT := 8.0
const DAY_FOG_HEIGHT_DENSITY := 0.022
const NIGHT_FOG_HEIGHT_DENSITY := 0.12
const DAY_FOG_SKY_AFFECT := 0.05
const BACKDROP_NIGHT_SCALE := 0.15
const WINDOW_WARM := Color(1.0, 0.72, 0.42)
const NIGHT_WALL_SCALE := 0.32
const NEON_GREEN := Color(0.25, 1.0, 0.6)
const NEON_PURPLE := Color(0.66, 0.3, 1.0)
const NEON_STRIP_CHANCE := 0.07
const TWILIGHT_LIT_CHANCE := 0.35
const GLASS_DAY := Color(0.3, 0.42, 0.56)
const GLASS_NIGHT := Color(0.015, 0.02, 0.032)
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
var _mode := Mode.DAY

var _rng := RandomNumberGenerator.new()
var _facade_records: Array[Dictionary] = []
var _facade_mats: Array[Dictionary] = []
var _groups := {}
var _roof_st := SurfaceTool.new()
var _ac_st := SurfaceTool.new()
var _tank_st := SurfaceTool.new()
var _marker_st := SurfaceTool.new()
var _neon_sts := {}
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
		_facade_records.append(_make_facade_set(color, 0.25, Color.WHITE))
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.albedo_color = Color(0.2, 0.21, 0.23)
	_roof_mat.roughness = 0.95
	_ac_mat = StandardMaterial3D.new()
	_ac_mat.albedo_color = Color(0.55, 0.56, 0.6)
	_ac_mat.roughness = 0.7
	_tank_mat = StandardMaterial3D.new()
	_tank_mat.albedo_color = Color(0.45, 0.42, 0.4)
	_tank_mat.roughness = 0.8


## Facade texture set for one palette: day albedo (glass windows with
## frames/mullions), night albedo (lit windows), an emission mask that
## lights the night-lit windows, a roughness/metallic spec map and a
## normal map with inset windows and raised frames.
func _make_facade_set(
	base: Color,
	lit_chance: float,
	color: Color,
	tex_w := FACADE_W,
	tex_h := FACADE_H
) -> Dictionary:
	var plan := PackedByteArray()
	plan.resize(TILE_COLS * TILE_ROWS)
	for i in plan.size():
		var roll := _rng.randf()
		if roll < lit_chance:
			plan[i] = 1
		elif roll < lit_chance + NIGHT_LIT_EXTRA:
			plan[i] = 3
	var wf := _rng.randf_range(0.52, 0.9)
	var hf := _rng.randf_range(0.45, 0.78)
	var glass := GLASS_DAY * _rng.randf_range(0.85, 1.15)
	return {
		"day": _raster_day(base, tex_w, tex_h, wf, hf, glass),
		"night": _raster_night(base * NIGHT_WALL_SCALE, plan, tex_w, tex_h, wf, hf),
		"mask": _raster_mask(plan, tex_w, tex_h, wf, hf),
		"mask_twilight": _raster_mask_twilight(plan, tex_w, tex_h, wf, hf),
		"spec": _raster_spec(tex_w, tex_h, wf, hf),
		"normal": _raster_normal(tex_w, tex_h, wf, hf),
		"color": color,
		"landmark": false,
	}


func _window_rect(cell: Rect2i, wf: float, hf: float) -> Rect2i:
	var w := int(cell.size.x * wf)
	var h := int(cell.size.y * hf)
	return Rect2i(
		cell.position.x + int((cell.size.x - w) * 0.5),
		cell.position.y + int((cell.size.y - h) * 0.5),
		w, h
	)


func _window_rects(w: int, h: int, wf: float, hf: float) -> Array[Rect2i]:
	var wins: Array[Rect2i] = []
	var cell_w := float(w) / TILE_COLS
	var cell_h := float(h) / TILE_ROWS
	for row in TILE_ROWS:
		for col in TILE_COLS:
			wins.append(_window_rect(Rect2i(
				int(col * cell_w), int(row * cell_h), int(cell_w), int(cell_h)), wf, hf))
	return wins


func _speckle(img: Image, base: Color, count: int) -> void:
	for i in count:
		var shade := _rng.randf_range(-0.05, 0.05)
		img.set_pixel(_rng.randi() % img.get_width(), _rng.randi() % img.get_height(), base * (1.0 + shade))


func _raster_day(base: Color, w: int, h: int, wf: float, hf: float, glass: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(base)
	_speckle(img, base, 12000)
	for win in _window_rects(w, h, wf, hf):
		var frame := base * 0.55
		img.fill_rect(win.grow(3), frame)
		var g := glass * _rng.randf_range(0.9, 1.08)
		var slices := 6
		for s in slices:
			var t := float(s) / slices
			var c := g.lerp(Color(0.55, 0.65, 0.78), t * 0.6)
			img.fill_rect(Rect2i(
				win.position.x, win.position.y + int(win.size.y * t),
				win.size.x, int(win.size.y * (t + 1.0 / slices)) - int(win.size.y * t)), c)
		var m := maxi(2, win.size.x / 24)
		img.fill_rect(Rect2i(
			win.position.x + win.size.x / 2 - m / 2, win.position.y,
			m, win.size.y), frame)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _raster_night(wall: Color, plan: PackedByteArray, w: int, h: int, wf: float, hf: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(wall)
	_speckle(img, wall, 12000)
	var wins := _window_rects(w, h, wf, hf)
	for i in wins.size():
		var win := wins[i]
		var kind := plan[i]
		var fill := GLASS_NIGHT * _rng.randf_range(0.7, 1.3)
		if kind != 0:
			fill = Color(1.0, 0.85, 0.55) * (0.9 if kind == 1 else 0.55)
		img.fill_rect(win.grow(3), wall * 0.5)
		img.fill_rect(win, fill)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _raster_mask(plan: PackedByteArray, w: int, h: int, wf: float, hf: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var wins := _window_rects(w, h, wf, hf)
	for i in wins.size():
		var kind := plan[i]
		if kind == 0:
			continue
		var brightness := _rng.randf_range(0.75, 1.0) if kind == 1 else _rng.randf_range(0.45, 0.6)
		img.fill_rect(wins[i], Color(brightness, brightness, brightness))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Shared channel map: R = roughness, G = metallic. Glass is smooth and
## partially metallic so day windows pick up sky reflections.
func _raster_spec(w: int, h: int, wf: float, hf: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.92, 0.0, 0.0))
	for win in _window_rects(w, h, wf, hf):
		img.fill_rect(win.grow(3), Color(0.55, 0.1, 0.0))
		img.fill_rect(win, Color(0.14, 0.62, 0.0))
	return ImageTexture.create_from_image(img)


func _raster_normal(w: int, h: int, wf: float, hf: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	for win in _window_rects(w, h, wf, hf):
		img.fill_rect(win.grow(3), Color(0.62, 0.62, 0.62))
		img.fill_rect(win, Color(0.3, 0.3, 0.3))
	img.bump_map_to_normal_map(1.6)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Sparse "someone's home" emission mask for twilight mode.
func _raster_mask_twilight(plan: PackedByteArray, w: int, h: int, wf: float, hf: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var wins := _window_rects(w, h, wf, hf)
	for i in wins.size():
		if plan[i] == 0:
			continue
		if _rng.randf() > TWILIGHT_LIT_CHANCE:
			continue
		var brightness := _rng.randf_range(0.8, 1.0)
		img.fill_rect(wins[i], Color(brightness, brightness, brightness))
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
	_roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ac_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tank_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_marker_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_neon_sts = {
		NEON_GREEN: SurfaceTool.new(),
		NEON_PURPLE: SurfaceTool.new(),
	}
	for st in _neon_sts.values():
		(st as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := (GRID_SIZE - 1) * 0.5
	var center := Vector3.ZERO
	var spawn_record := {}

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
			var rec_idx := _rng.randi() % _facade_records.size()
			var shade_idx := _rng.randi() % TINT_SHADES.size()
			var rec := _spawn_building(root, pos, width, depth, height, rec_idx, shade_idx)
			building_count += 1
			roof_spots.append(pos + Vector3(0.0, rec["top_y"] + 0.5, 0.0))
			_building_boxes.append({
				"pos": pos,
				"w": width,
				"d": depth,
				"h": height,
			})
			if dist_to_center < SPACING:
				spawn_record = rec

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
			_spawn_day_switch(tower, pos, width, height, "DAY / NIGHT", false)
		elif i == 1:
			_spawn_day_switch(tower, pos, width, height, "DAY / TWILIGHT", true)
		roof_spots.append(pos + Vector3(0.0, height + 1.0, 0.0))
		_building_boxes.append({
			"pos": pos,
			"w": width,
			"d": depth,
			"h": height,
		})

	if spawn_record.is_empty() and building_count > 0:
		spawn_record = {"pos": Vector3.ZERO, "top_y": 20.0}
	if not spawn_record.is_empty():
		var rec_pos: Vector3 = spawn_record["pos"]
		spawn_point = rec_pos + Vector3(0.0, float(spawn_record["top_y"]) + 1.0, 0.0)

	_commit_merged_meshes(root)


## Stacked setback tiers for tall buildings; a single box for low ones.
## Entries: y0, h1 (tier top y), w/d (tier footprint), plus render flags.
func _tier_plan(w: float, d: float, h: float) -> Array:
	var groups := []
	if h >= SETBACK_TALL:
		var f0 := _rng.randf_range(0.45, 0.6)
		var f1 := _rng.randf_range(0.72, 0.82)
		groups = [
			[0.0, h * f0, 1.0],
			[h * f0, h * f1, _rng.randf_range(0.75, 0.88)],
			[h * f1, h, _rng.randf_range(0.55, 0.68)],
		]
	elif h >= SETBACK_MID:
		var f0 := _rng.randf_range(0.6, 0.75)
		groups = [
			[0.0, h * f0, 1.0],
			[h * f0, h, _rng.randf_range(0.7, 0.85)],
		]
	else:
		groups = [[0.0, h, 1.0]]
	var tiers := []
	for i in groups.size():
		var g: Array = groups[i]
		tiers.append({
			"y0": g[0],
			"h1": g[1],
			"w": w * g[2],
			"d": d * g[2],
			"top_face": i < groups.size() - 1,
			"cornice": i < groups.size() - 1,
		})
	return tiers


## Collision body + merged visual geometry for one regular building.
func _spawn_building(
	root: Node3D,
	pos: Vector3,
	width: float,
	depth: float,
	height: float,
	rec_idx: int,
	shade_idx: int
) -> Dictionary:
	var building := Node3D.new()
	building.name = "Building%03d" % building_count
	building.position = pos
	root.add_child(building)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = BUILDING_LAYER
	body.collision_mask = 0
	building.add_child(body)

	var st := _facade_group(rec_idx, shade_idx)
	var tiers := _tier_plan(width, depth, height)
	for tier in tiers:
		var tier_h: float = tier["h1"] - tier["y0"]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(tier["w"], tier_h, tier["d"])
		shape.shape = box
		shape.position = Vector3(0.0, tier["y0"] + tier_h * 0.5, 0.0)
		body.add_child(shape)
		_add_facade_sides(
			st,
			pos + Vector3(0.0, tier["y0"] + tier_h * 0.5, 0.0),
			Vector3(tier["w"], tier_h, tier["d"]))
		if tier["top_face"]:
			_add_box_top(_roof_st, pos + Vector3(0.0, tier["h1"], 0.0), Vector3(tier["w"], 0.0, tier["d"]))
		if tier["cornice"]:
			_append_box(
				_roof_st,
				pos + Vector3(0.0, tier["h1"] + 0.22, 0.0),
				Vector3(tier["w"] + 0.4, 0.45, tier["d"] + 0.4))

	var top: Dictionary = tiers[tiers.size() - 1]
	_append_box(
		_roof_st,
		pos + Vector3(0.0, height + 0.25, 0.0),
		Vector3(top["w"] + 0.4, 0.5, top["d"] + 0.4))
	_append_parapet(pos + Vector3(0.0, height + 0.5, 0.0), top["w"] + 0.4, top["d"] + 0.4)
	_add_roof_prop(pos + Vector3(0.0, height + 0.5, 0.0), top["w"], top["d"])
	_spawn_neon(pos, width, depth, height)
	_maybe_roof_marker(pos, height)
	return {"pos": pos, "top_y": height + 0.5}


func _make_landmark(pos: Vector3, width: float, depth: float, height: float, color: Color) -> Node3D:
	var rec := _make_facade_set(
		color.lightened(0.3), 0.85, color, LANDMARK_FACADE_W, LANDMARK_FACADE_H)
	rec["landmark"] = true
	var rec_idx := _facade_records.size()
	_facade_records.append(rec)
	var st := _facade_group(rec_idx, 2)
	_add_facade_sides(
		st, pos + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth))
	_append_box(
		_roof_st,
		pos + Vector3(0.0, height + 0.25, 0.0),
		Vector3(width + 0.4, 0.5, depth + 0.4))
	_append_parapet(pos + Vector3(0.0, height + 0.5, 0.0), width + 0.4, depth + 0.4)

	var building := Node3D.new()
	building.name = "Landmark%02d" % landmark_count
	building.position = pos
	building.add_to_group("landmarks")

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


func _facade_group(rec_idx: int, shade_idx: int) -> SurfaceTool:
	var key := "%d_%d" % [rec_idx, shade_idx]
	if _groups.has(key):
		return _groups[key]["st"] as SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rec := _facade_records[rec_idx]
	var mat := StandardMaterial3D.new()
	_apply_group_material(mat, rec, TINT_SHADES[shade_idx])
	_groups[key] = {"st": st, "mat": mat, "rec": rec}
	return st


func _apply_group_material(mat: StandardMaterial3D, rec: Dictionary, shade: float) -> void:
	mat.albedo_texture = rec["day"]
	mat.albedo_color = Color(shade, shade, shade)
	mat.roughness = 1.0
	mat.roughness_texture = rec["spec"]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.metallic = 1.0
	mat.metallic_texture = rec["spec"]
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.normal_enabled = true
	mat.normal_texture = rec["normal"]
	mat.normal_scale = 0.9


func _commit_merged_meshes(root: Node3D) -> void:
	for key in _groups:
		var entry: Dictionary = _groups[key]
		var mesh := (entry["st"] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.name = "Facade_%s" % key
		mi.mesh = mesh
		mi.material_override = entry["mat"]
		root.add_child(mi)
		_apply_facade_mode(entry["mat"] as StandardMaterial3D, entry["rec"] as Dictionary)
		_facade_mats.append({"mat": entry["mat"], "rec": entry["rec"], "neon": Color(0.0, 0.0, 0.0)})

	var roof := _mesh_from(_roof_st, _roof_mat)
	roof.name = "RoofCaps"
	root.add_child(roof)
	var ac := _mesh_from(_ac_st, _ac_mat)
	ac.name = "ACUnits"
	root.add_child(ac)
	var tanks := _mesh_from(_tank_st, _tank_mat)
	tanks.name = "WaterTanks"
	root.add_child(tanks)

	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(0.95, 0.55, 0.1)
	var markers := _mesh_from(_marker_st, marker_mat)
	markers.name = "RoofMarkers"
	root.add_child(markers)

	for color in _neon_sts:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		var mesh := _mesh_from(_neon_sts[color], mat)
		mesh.name = "NeonGreen" if color == NEON_GREEN else "NeonPurple"
		mesh.visible = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
		_neon_nodes.append(mesh)


func _mesh_from(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## Four side faces of one box with facade UVs that tile whole window
## tiles horizontally and whole floors vertically.
func _add_facade_sides(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var rx := maxf(1.0, ceilf(size.x / TILE_W_METERS))
	var ry := maxf(1.0, ceilf(size.y / TILE_H_METERS))
	_facade_face(st,
		center + Vector3(-hx, -hy, hz), center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz), center + Vector3(-hx, hy, hz),
		rx, ry, Vector3(0.0, 0.0, 1.0))
	_facade_face(st,
		center + Vector3(hx, -hy, -hz), center + Vector3(-hx, -hy, -hz),
		center + Vector3(-hx, hy, -hz), center + Vector3(hx, hy, -hz),
		rx, ry, Vector3(0.0, 0.0, -1.0))
	_facade_face(st,
		center + Vector3(hx, -hy, hz), center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz), center + Vector3(hx, hy, hz),
		rx, ry, Vector3(1.0, 0.0, 0.0))
	_facade_face(st,
		center + Vector3(-hx, -hy, -hz), center + Vector3(-hx, -hy, hz),
		center + Vector3(-hx, hy, hz), center + Vector3(-hx, hy, -hz),
		rx, ry, Vector3(-1.0, 0.0, 0.0))


## Corners given as bottom-left, bottom-right, top-right, top-left as seen
## from outside; emits CCW (bl, tl, tr) and (bl, tr, br).
func _facade_face(
	st: SurfaceTool,
	bl: Vector3,
	br: Vector3,
	tr: Vector3,
	tl: Vector3,
	rx: float,
	ry: float,
	normal: Vector3
) -> void:
	var corners := [bl, br, tr, tl]
	var uvs := [Vector2(0.0, ry), Vector2(rx, ry), Vector2(rx, 0.0), Vector2(0.0, 0.0)]
	for idx in [[0, 3, 2], [0, 2, 1]]:
		for i in idx:
			st.set_normal(normal)
			st.set_uv(uvs[i])
			st.add_vertex(corners[i])


func _add_box_top(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var normal := Vector3.UP
	var corners := [
		center + Vector3(-hx, 0.0, -hz),
		center + Vector3(hx, 0.0, -hz),
		center + Vector3(hx, 0.0, hz),
		center + Vector3(-hx, 0.0, hz),
	]
	for idx in [[0, 3, 2], [0, 2, 1]]:
		for i in idx:
			st.set_normal(normal)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(corners[i])


func _append_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	st.append_from(mesh, 0, Transform3D(Basis.IDENTITY, center))


func _append_parapet(base: Vector3, w: float, d: float) -> void:
	var t := 0.22
	var ph := 0.38
	var y := base.y + ph * 0.5
	_append_box(_roof_st, Vector3(base.x, y, base.z + (d * 0.5 - t * 0.5)), Vector3(w, ph, t))
	_append_box(_roof_st, Vector3(base.x, y, base.z - (d * 0.5 - t * 0.5)), Vector3(w, ph, t))
	_append_box(_roof_st, Vector3(base.x + (w * 0.5 - t * 0.5), y, base.z), Vector3(t, ph, d - t * 2.0))
	_append_box(_roof_st, Vector3(base.x - (w * 0.5 - t * 0.5), y, base.z), Vector3(t, ph, d - t * 2.0))


## Green/purple neon accents, visible only at night: thin vertical corner
## strips. Roofline bands were removed because the overhangs hurt night
## fill-rate and looked visually noisy.
func _spawn_neon(pos: Vector3, width: float, depth: float, height: float) -> void:
	if _rng.randf() >= NEON_STRIP_CHANCE:
		return
	var neon := NEON_GREEN if _rng.randf() < 0.5 else NEON_PURPLE
	var st := _neon_sts[neon] as SurfaceTool
	for corner in 4:
		var sx := (width * 0.5 - 0.045) * (1.0 if corner % 2 == 0 else -1.0)
		var sz := (depth * 0.5 - 0.045) * (1.0 if corner < 2 else -1.0)
		_append_box(
			st,
			pos + Vector3(sx, height * 0.5, sz),
			Vector3(0.09, height, 0.09))


func _add_roof_prop(base: Vector3, width: float, depth: float) -> void:
	var roll := _rng.randf()
	if roll >= 0.3:
		return
	var x := _rng.randf_range(-(width * 0.5 - 1.6), width * 0.5 - 1.6)
	var z := _rng.randf_range(-(depth * 0.5 - 1.6), depth * 0.5 - 1.6)
	if roll < 0.18:
		var ac := BoxMesh.new()
		ac.size = Vector3(1.4, 0.7, 1.1)
		_ac_st.append_from(ac, 0, Transform3D(
			Basis.IDENTITY, Vector3(base.x + x, base.y + 0.35, base.z + z)))
	else:
		var tank := CylinderMesh.new()
		tank.top_radius = 0.55
		tank.bottom_radius = 0.6
		tank.height = 1.1
		_tank_st.append_from(tank, 0, Transform3D(
			Basis.IDENTITY, Vector3(base.x + x, base.y + 0.55, base.z + z)))


func _maybe_roof_marker(pos: Vector3, height: float) -> void:
	if not build_roof_hud or _rng.randf() >= 0.06:
		return
	var marker := BoxMesh.new()
	marker.size = Vector3(1.2, 1.2, 1.2)
	_marker_st.append_from(marker, 0, Transform3D(
		Basis.IDENTITY, pos + Vector3(0.0, height + 0.7, 0.0)))


func _spawn_day_switch(
	landmark: Node3D,
	pos: Vector3,
	width: float,
	height: float,
	label: String,
	twilight: bool
) -> void:
	var sw := DaySwitch.new()
	sw.name = "DaySwitch"
	sw.label_text = label
	sw.position = pos + Vector3(width * 0.28, height + 0.5, width * 0.28)
	if twilight:
		sw.toggled.connect(_on_twilight_switch_toggled)
	else:
		sw.toggled.connect(_on_switch_toggled)
	add_child(sw)


func _on_switch_toggled(switch_is_night: bool) -> void:
	set_mode(Mode.NIGHT if switch_is_night else Mode.DAY)


func _on_twilight_switch_toggled(switch_is_twilight: bool) -> void:
	set_mode(Mode.TWILIGHT if switch_is_twilight else Mode.DAY)


## Swap the whole city between day, night, and twilight: sun/sky/fog,
## window emission on every facade, and dimmed unshaded backdrop silhouettes.
func set_mode(mode: Mode) -> void:
	if _mode == mode:
		return
	_mode = mode
	is_night = mode != Mode.DAY
	_apply_mode_lighting()
	for entry in _facade_mats:
		_apply_facade_mode(entry["mat"] as StandardMaterial3D, entry["rec"] as Dictionary)
	for mat in _backdrop_mats:
		mat.albedo_color = (mat.get_meta("base") as Color) * (BACKDROP_NIGHT_SCALE if is_night else 1.0)
	for node in _neon_nodes:
		node.visible = is_night
	if _sky != null:
		_sky.sky_material = _procedural_sky_mat if mode == Mode.DAY else _night_sky_mat
	night_changed.emit(is_night)


func set_night(night: bool) -> void:
	set_mode(Mode.NIGHT if night else Mode.DAY)


func toggle_night() -> void:
	set_night(not is_night)


func _apply_facade_mode(mat: StandardMaterial3D, rec: Dictionary) -> void:
	match _mode:
		Mode.DAY:
			mat.albedo_texture = rec["day"]
			mat.emission_texture = null
			if rec["landmark"]:
				mat.emission_enabled = true
				mat.emission = (rec["color"] as Color) * 0.25
				mat.emission_energy_multiplier = 0.6
			else:
				mat.emission_enabled = false
		Mode.NIGHT:
			mat.albedo_texture = rec["night"]
			mat.emission_enabled = true
			mat.emission_texture = rec["mask"]
			if rec["landmark"]:
				mat.emission = (rec["color"] as Color).lightened(0.2)
				mat.emission_energy_multiplier = 1.7
			else:
				mat.emission = WINDOW_WARM
				mat.emission_energy_multiplier = 0.75
		Mode.TWILIGHT:
			mat.albedo_texture = rec["day"]
			mat.emission_enabled = true
			mat.emission_texture = rec["mask_twilight"]
			if rec["landmark"]:
				mat.emission = (rec["color"] as Color).lightened(0.2)
				mat.emission_energy_multiplier = 1.4
			else:
				mat.emission = WINDOW_WARM
				mat.emission_energy_multiplier = 1.0


func _apply_mode_lighting() -> void:
	if _sun != null:
		match _mode:
			Mode.DAY:
				_sun.light_energy = DAY_SUN_ENERGY
				_sun.light_color = DAY_SUN_COLOR
			Mode.NIGHT:
				_sun.light_energy = NIGHT_SUN_ENERGY
				_sun.light_color = NIGHT_SUN_COLOR
			Mode.TWILIGHT:
				_sun.light_energy = 0.75
				_sun.light_color = Color(0.72, 0.78, 1.0)
	if _sky_mat != null:
		match _mode:
			Mode.DAY:
				_sky_mat.sky_top_color = DAY_SKY_TOP
				_sky_mat.sky_horizon_color = DAY_SKY_HORIZON
				_sky_mat.ground_bottom_color = DAY_GROUND_BOTTOM
				_sky_mat.ground_horizon_color = DAY_GROUND_HORIZON
			_:
				_sky_mat.sky_top_color = NIGHT_SKY_TOP
				_sky_mat.sky_horizon_color = NIGHT_SKY_HORIZON
				_sky_mat.ground_bottom_color = NIGHT_GROUND_BOTTOM
				_sky_mat.ground_horizon_color = NIGHT_GROUND_HORIZON
	if _env != null:
		match _mode:
			Mode.DAY:
				_env.fog_light_color = DAY_FOG_COLOR
				_env.fog_density = DAY_FOG_DENSITY
				_env.fog_height = DAY_FOG_HEIGHT
				_env.fog_height_density = DAY_FOG_HEIGHT_DENSITY
				_env.fog_sky_affect = DAY_FOG_SKY_AFFECT
				_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
				_env.ambient_light_sky_contribution = DAY_AMBIENT_SKY
			Mode.NIGHT:
				_env.fog_light_color = NIGHT_FOG_COLOR
				_env.fog_density = NIGHT_FOG_DENSITY
				_env.fog_height = NIGHT_FOG_HEIGHT
				_env.fog_height_density = NIGHT_FOG_HEIGHT_DENSITY
				_env.fog_sky_affect = 0.2
				_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
				_env.ambient_light_sky_contribution = NIGHT_AMBIENT_SKY
			Mode.TWILIGHT:
				_env.fog_light_color = DAY_FOG_COLOR
				_env.fog_density = DAY_FOG_DENSITY * 0.85
				_env.fog_height = DAY_FOG_HEIGHT
				_env.fog_height_density = DAY_FOG_HEIGHT_DENSITY
				_env.fog_sky_affect = 0.05
				_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				_env.ambient_light_color = Color(0.18, 0.20, 0.26)
				_env.ambient_light_energy = 0.65


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
	sun.light_color = DAY_SUN_COLOR
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	_sun = sun

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = DAY_SKY_TOP
	sky_mat.sky_horizon_color = DAY_SKY_HORIZON
	sky_mat.ground_bottom_color = DAY_GROUND_BOTTOM
	sky_mat.ground_horizon_color = DAY_GROUND_HORIZON
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = DAY_AMBIENT_SKY
	env.fog_enabled = true
	env.fog_light_color = DAY_FOG_COLOR
	env.fog_density = DAY_FOG_DENSITY
	env.fog_height = DAY_FOG_HEIGHT
	env.fog_height_density = DAY_FOG_HEIGHT_DENSITY
	env.fog_sky_affect = DAY_FOG_SKY_AFFECT
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
