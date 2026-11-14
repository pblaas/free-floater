extends SceneTree

const WebRigScript = preload("res://scripts/web_rig.gd")
const CityBuilderScript = preload("res://scripts/city_builder.gd")
const BuildVersionScript = preload("res://scripts/build_version.gd")
const MainScript = preload("res://scripts/main.gd")

var failures := 0


func _init() -> void:
	await _test_rope_math()
	await _test_city_generation()
	await _test_web_rig_scene()
	await _test_scoring()
	await _test_day_night()
	await _test_main_scene()
	await _test_build_version()
	await _stop_audio()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILED: %d test(s)" % failures)
	quit(1 if failures > 0 else 0)


func _stop_audio() -> void:
	await process_frame
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		(player as AudioStreamPlayer).stop()
	await process_frame
	await process_frame


func _stop_rig_audio(rig: Node) -> void:
	await process_frame
	for player in rig.find_children("*", "AudioStreamPlayer", true, false):
		(player as AudioStreamPlayer).stop()
	for i in 12:
		await process_frame


func check(condition: bool, message: String) -> void:
	if condition:
		print("  ok - %s" % message)
	else:
		failures += 1
		printerr("  FAIL - %s" % message)


func _test_rope_math() -> void:
	print("rope constraint math")
	var anchor := Vector3(0.0, 20.0, 0.0)

	var slack := WebRigScript.solve_rope(
		anchor + Vector3(2.0, -3.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		anchor,
		10.0
	)
	check((slack[0] as Vector3).is_equal_approx(anchor + Vector3(2.0, -3.0, 0.0)), "slack rope keeps position")
	check((slack[1] as Vector3).is_equal_approx(Vector3(1.0, 0.0, 0.0)), "slack rope keeps velocity")

	var outward_pos := anchor + Vector3(9.0, -12.0, 0.0)
	var outward_vel := Vector3(4.0, -2.0, 0.0)
	var taut := WebRigScript.solve_rope(outward_pos, outward_vel, anchor, 10.0)
	var new_pos := taut[0] as Vector3
	var new_vel := taut[1] as Vector3
	check(is_equal_approx(new_pos.distance_to(anchor), 10.0), "taut rope projects onto sphere")
	var offset := (new_pos - anchor).normalized()
	check(is_equal_approx(new_vel.dot(offset), 0.0), "outward velocity removed")
	check(new_vel.dot(offset) <= 0.0, "no outward residual")

	var inward_vel := Vector3(-4.0, -2.0, 0.0)
	var falling := WebRigScript.solve_rope(outward_pos, inward_vel, anchor, 10.0)
	check((falling[1] as Vector3).is_equal_approx(inward_vel), "inward velocity kept")

	var tiny := WebRigScript.solve_rope(anchor, Vector3.ONE, anchor, 10.0)
	check((tiny[0] as Vector3).is_equal_approx(anchor), "zero-length offset is safe")


func _test_city_generation() -> void:
	print("city generation")
	var city: CityBuilderScript = CityBuilderScript.new()
	city.name = "TestCity"
	root.add_child(city)
	await process_frame
	check(city.building_count > 100, "city has many buildings (%d)" % city.building_count)
	check(city.spawn_point.y > 5.0, "spawn on a rooftop (y=%.1f)" % city.spawn_point.y)
	var buildings := city.get_node_or_null("Buildings")
	check(buildings != null, "Buildings container exists")
	if buildings == null:
		return
	var webbable := 0
	for building in buildings.get_children():
		var body := building.get_node_or_null("Body") as StaticBody3D
		if body != null and body.collision_layer == 2:
			webbable += 1
	check(webbable == city.building_count, "every building is webbable (layer 2)")
	check(city.landmark_count == 4, "city has 4 landmark towers (%d)" % city.landmark_count)
	var landmarks := 0
	for building in city.get_node("Buildings").get_children():
		if building.is_in_group("landmarks"):
			landmarks += 1
	check(landmarks == city.landmark_count, "landmarks tagged in group (%d)" % landmarks)
	for landmark in city.get_node("Buildings").get_children():
		if not landmark.is_in_group("landmarks"):
			continue
		check(
			landmark.get_node_or_null("Beacon") != null
			and landmark.get_node_or_null("BeaconLight") != null,
			"%s has a lit beacon" % landmark.name
		)
		check(
			(landmark.get_node("Body/Shape").shape as BoxShape3D).size.y >= 38.0,
			"%s is taller than normal buildings" % landmark.name
		)
	var ground := city.get_node_or_null("Ground") as StaticBody3D
	check(ground != null and ground.collision_layer == 1, "ground is walkable (layer 1)")
	var sun := city.get_node_or_null("Sun")
	check(sun != null, "sun light exists")
	check(city.get_node_or_null("WorldEnv") != null, "world environment exists")


func _test_web_rig_scene() -> void:
	print("web rig scene")
	var rig_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	check(rig_scene != null, "main scene instantiates")
	if rig_scene == null:
		return
	root.add_child(rig_scene)
	var rig := rig_scene.get_node_or_null("XROrigin3D") as WebRigScript
	check(rig != null, "WebRig on XROrigin3D")
	check(rig != null and rig._velocity.length_squared() < 0.000001, "starts at rest")
	if rig == null:
		rig_scene.queue_free()
		return
	await process_frame
	check(rig.camera != null, "camera wired")
	check(rig.left_controller != null and rig.right_controller != null, "controllers wired")
	var webs: Dictionary = rig._webs
	check(webs.has("L") and webs.has("R"), "both hands have web state")
	var left_web: Dictionary = webs["L"]
	check(left_web["hand"] == rig.left_controller, "L web bound to left controller")
	var cord := left_web["cord"] as MeshInstance3D
	check(cord != null and not cord.visible, "L cord hidden before attach")
	check(cord.mesh is ImmediateMesh, "cord uses dynamic sagging mesh")
	check(cord.material_override.albedo_color == Color(1.0, 0.3, 0.24), "L cord uses distinct side color")
	var right_web: Dictionary = webs["R"]
	check(
		(right_web["cord"] as MeshInstance3D).material_override.albedo_color == Color(0.24, 0.62, 1.0),
		"R cord uses distinct side color"
	)
	check(rig.get_node_or_null("LandingThud") != null, "landing thud player exists")
	var wind := rig.get_node_or_null("WindLoop") as AudioStreamPlayer
	check(wind != null and wind.stream != null, "wind loop player exists")
	check(wind.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "wind loop is seamless")
	check(WebRigScript.MUSIC_TRACKS.size() >= 5, "music playlist has multiple tracks")
	check(rig._playlist.size() == WebRigScript.MUSIC_TRACKS.size(), "playlist covers every track")
	check(rig._track_index == 0, "playlist starts on first track")
	check(rig._music != null and rig._music.stream != null, "background music loaded")
	check(rig._music.stream.loop == false, "playlist tracks advance instead of looping")
	await _stop_rig_audio(rig)
	rig_scene.queue_free()
	await process_frame


func _test_scoring() -> void:
	print("scoring + swing chain")
	check(WebRigScript.SWING_BASE_POINTS > 0.0, "swing base points configured")
	check(WebRigScript.CHAIN_MULT_STEP > 0.0, "chain multiplier step configured")
	check(WebRigScript.MIN_SWING_SECONDS > 0.0, "minimum swing duration configured")
	var score := WebRigScript.new()
	check(score._format_score(1234567) == "1,234,567", "score formatting groups digits")
	check(score._format_score(0) == "0", "zero score formats plain")
	check(score._chain_multiplier() == 1.0, "multiplier starts at ×1")
	score._chain = 10
	check(score._chain_multiplier() == 2.0, "multiplier doubles after 10 swings")
	score._chain = 0
	score._register_swing(10.0)
	check(score._chain == 1, "swing increments chain")
	check(score._score > 0, "swing awards points")
	check(score._best_chain == 1, "best chain tracked")
	score._bank_chain()
	check(score._chain == 0, "landing banks and resets chain")
	score._register_swing(5.0)
	score._register_swing(5.0)
	score._register_swing(5.0)
	check(score._chain == 3, "three swings build a chain")
	var before_bonus := score._score
	score._bank_chain()
	check(
		score._score == before_bonus + WebRigScript.CHAIN_BANK_BONUS * 3,
		"bank bonus awarded for chain >= 3"
	)
	score.free()


func _test_day_night() -> void:
	print("day/night switch")
	var city: CityBuilderScript = CityBuilderScript.new()
	city.name = "TestCityDN"
	root.add_child(city)
	await process_frame
	check(city.is_night == false, "city starts in day mode")
	var sw := city.get_node_or_null("DaySwitch")
	check(sw != null, "day/night switch spawned")
	if sw == null:
		city.queue_free()
		await process_frame
		return
	check(sw.has_method("activate"), "switch exposes activate()")
	check(sw.is_night == false, "switch starts in day state")
	check(sw.global_position.y > 30.0, "switch is up on a tall roof (y=%.1f)" % sw.global_position.y)
	var landmark_roof := false
	for box in city._building_boxes:
		var pos: Vector3 = box["pos"]
		if absf(sw.global_position.x - pos.x) <= float(box["w"]) * 0.5 \
				and absf(sw.global_position.z - pos.z) <= float(box["d"]) * 0.5 \
				and absf(sw.global_position.y - float(box["h"])) < 2.0 \
				and float(box["h"]) >= 38.0:
			landmark_roof = true
	check(landmark_roof, "switch spawned on a colored landmark roof")
	var body := sw.get_node_or_null("Body") as StaticBody3D
	check(body != null and body.collision_layer == 8, "switch collider on interaction layer 8")
	check(body.is_in_group("day_switch"), "switch collider discoverable by web raycast")
	check(body.get_meta("switch_node") == sw, "collider links back to the switch")

	var sun := city.get_node_or_null("Sun") as DirectionalLight3D
	check(sun != null, "sun light exists for day/night swap")
	var day_energy := sun.light_energy
	var facade: MeshInstance3D = null
	var lmat: StandardMaterial3D = null
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Facade_"):
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		if m.emission_enabled and lmat == null:
			lmat = m
		elif not m.emission_enabled and facade == null:
			facade = mi
	check(facade != null, "merged facade meshes exist")
	if facade == null:
		city.queue_free()
		await process_frame
		return
	var mat := facade.material_override as StandardMaterial3D
	var day_albedo := mat.albedo_texture
	check(not mat.emission_enabled, "day facades do not emit")
	check(mat.roughness_texture != null and mat.metallic_texture != null, "facades carry a glass spec map")
	check(mat.normal_texture != null, "facades carry a window normal map")

	city.set_night(true)
	check(city.is_night, "set_night(true) flips state")
	check(sun.light_energy < day_energy * 0.4, "night dims the sun")
	check(mat.emission_enabled, "night enables window emission on buildings")
	check(mat.emission_texture != null, "night windows glow via emission mask")
	check(mat.albedo_texture != day_albedo, "night swaps in darker facade albedo")

	city.set_night(false)
	check(not city.is_night and sun.light_energy == day_energy, "set_night(false) restores day")
	check(not mat.emission_enabled, "day disables window emission again")
	check(mat.albedo_texture == day_albedo, "day restores facade albedo")

	sw.activate()
	check(city.is_night, "switch activation toggles city to night")
	check(sw.is_night, "switch state matches city after activation")
	sw.activate()
	check(not city.is_night, "switch activation toggles back to day")
	check(sun.light_energy == day_energy, "sun restored after round trip")

	if lmat != null:
		var day_emission: Color = lmat.emission
		city.set_night(true)
		check(lmat.emission_enabled, "night keeps landmark emission on")
		check((lmat.emission as Color) != day_emission, "night recolors landmark glow")
		check((lmat.emission_energy_multiplier as float) > 1.0, "landmark windows glow brighter at night")
		var warm_windows := 0
		for entry in city._facade_mats:
			var rec: Dictionary = entry["rec"]
			if rec["landmark"]:
				continue
			if (entry["mat"] as StandardMaterial3D).emission == Color(1.0, 0.72, 0.42):
				warm_windows += 1
		check(warm_windows > 5, "facade groups emit warm night windows (%d)" % warm_windows)
		city.set_night(false)
	else:
		check(false, "landmark facade material found")

	var neon_g := city.get_node("Buildings").get_node_or_null("NeonGreen") as GeometryInstance3D
	var neon_p := city.get_node("Buildings").get_node_or_null("NeonPurple") as GeometryInstance3D
	check(neon_g != null and neon_p != null, "merged neon meshes exist")
	check(neon_g != null and not neon_g.visible, "neon hidden during day")
	city.set_night(true)
	check(neon_g != null and neon_g.visible and neon_p.visible, "neon glows at night")
	var night_env: Environment = city.get_node("WorldEnv").environment
	check(night_env.sky.sky_material is ShaderMaterial, "night swaps in starfield sky shader")
	city.set_night(false)
	check(not neon_g.visible, "neon off again in day")
	check(
		city.get_node("WorldEnv").environment.sky.sky_material is ProceduralSkyMaterial,
		"day restores procedural sky"
	)
	city.queue_free()
	await process_frame


func _test_main_scene() -> void:
	print("main script wiring")
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if main_scene == null:
		check(false, "main scene loads")
		return
	root.add_child(main_scene)
	await process_frame
	await process_frame
	var rig := main_scene.get_node_or_null("XROrigin3D") as WebRigScript
	var city := main_scene.get_node_or_null("City") as CityBuilderScript
	check(rig != null and city != null, "main wires city and rig")
	if rig != null and city != null:
		check(rig.global_position.distance_to(city.spawn_point) < 0.5, "player respawned at city spawn")
		await _stop_rig_audio(rig)
	main_scene.queue_free()
	await process_frame


func _test_build_version() -> void:
	print("build version")
	check(BuildVersionScript.TEXT.length() > 0, "build version stamp exists")
	check(WebRigScript.FLOAT_GRAVITY < WebRigScript.SWING_GRAVITY, "no-web gravity is floatier than swing gravity")
	check(WebRigScript.WEB_PULL_SPEED > 0.0 and WebRigScript.WEB_PULL_ACCEL > 0.0, "web pull is configured")
