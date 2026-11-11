extends SceneTree

const WebRigScript = preload("res://scripts/web_rig.gd")
const CityBuilderScript = preload("res://scripts/city_builder.gd")
const BuildVersionScript = preload("res://scripts/build_version.gd")
const MainScript = preload("res://scripts/main.gd")

var failures := 0


func _init() -> void:
	_test_rope_math()
	_test_city_generation()
	_test_web_rig_scene()
	_test_scoring()
	_test_main_scene()
	_test_build_version()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILED: %d test(s)" % failures)
	quit(1 if failures > 0 else 0)


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
	await process_frame
	var rig := rig_scene.get_node_or_null("XROrigin3D") as WebRigScript
	check(rig != null, "WebRig on XROrigin3D")
	if rig == null:
		rig_scene.queue_free()
		return
	check(rig.camera != null, "camera wired")
	check(rig.left_controller != null and rig.right_controller != null, "controllers wired")
	var webs: Dictionary = rig._webs
	check(webs.has("L") and webs.has("R"), "both hands have web state")
	var left_web: Dictionary = webs["L"]
	check(left_web["hand"] == rig.left_controller, "L web bound to left controller")
	var cord := left_web["cord"] as MeshInstance3D
	check(cord != null and not cord.visible, "L cord hidden before attach")
	check(rig._velocity.length_squared() < 0.000001, "starts at rest")
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


func _test_main_scene() -> void:
	print("main script wiring")
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if main_scene == null:
		check(false, "main scene loads")
		return
	root.add_child(main_scene)
	await process_frame
	var rig := main_scene.get_node_or_null("XROrigin3D") as WebRigScript
	var city := main_scene.get_node_or_null("City") as CityBuilderScript
	check(rig != null and city != null, "main wires city and rig")
	if rig != null and city != null:
		check(rig.global_position.distance_to(city.spawn_point) < 0.5, "player respawned at city spawn")
	main_scene.queue_free()
	await process_frame


func _test_build_version() -> void:
	print("build version")
	check(BuildVersionScript.TEXT.length() > 0, "build version stamp exists")
	check(WebRigScript.FLOAT_GRAVITY < WebRigScript.SWING_GRAVITY, "no-web gravity is floatier than swing gravity")
	check(WebRigScript.WEB_PULL_SPEED > 0.0 and WebRigScript.WEB_PULL_ACCEL > 0.0, "web pull is configured")
