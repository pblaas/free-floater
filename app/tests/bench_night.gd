extends SceneTree

# Frame-time bench for day vs night while flying a camera between buildings.
# Variants isolate night-specific render costs: animated sky radiance,
# sun shadows, sky-sourced ambient.

const FLIGHT_SECONDS := 8.0
const W := 0.5

var _city: CityBuilder
var _cam: Camera3D
var _env: Environment
var _sun: DirectionalLight3D
var _sky: Sky
var _t := 0.0
var _deltas: PackedFloat32Array = []
var _phase := 0
var _results := {}
var _phase_names := ["DAY", "NIGHT", "NIGHT_SKY_QUALITY", "NIGHT_NO_SHADOWS", "NIGHT_AMBIENT_COLOR"]


func _init() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_city = scene.get_node("City")
	_cam = Camera3D.new()
	_cam.far = 400.0
	root.add_child(_cam)
	var spawn: Vector3 = _city.spawn_point
	_cam.global_position = spawn
	_cam.make_current()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	await process_frame
	_sun = _city.get_node("Sun")
	_sky = _city.get_node("WorldEnv").environment.sky
	_env = _city.get_node("WorldEnv").environment
	_run_phase()


func _run_phase() -> void:
	_deltas.clear()
	_t = 0.0
	_phase += 1
	if _phase > _phase_names.size():
		_report()
		quit(0)
		return
	match _phase:
		2:
			_city.set_night(true)
		3:
			_sky.process_mode = Sky.PROCESS_MODE_QUALITY
		4:
			_sky.process_mode = Sky.PROCESS_MODE_REALTIME
			_sun.shadow_enabled = false
		5:
			_sun.shadow_enabled = true
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			_env.ambient_light_color = Color(0.08, 0.09, 0.13)
	print("phase: ", _phase_names[_phase - 1])
	await _flight()


func _flight() -> void:
	var half := 8.0 * CityBuilder.SPACING
	var prev_us := Time.get_ticks_usec()
	while _t < FLIGHT_SECONDS:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - prev_us) * 1e-6
		prev_us = now
		_t += delta
		_deltas.append(delta)
		_cam.global_position = Vector3(
			sin(_t * W) * half,
			26.0 + 6.0 * sin(_t * W * 2.0),
			cos(_t * W) * half)
		var forward := Vector3(-cos(_t * W), -0.05, -sin(_t * W))
		_cam.look_at(_cam.global_position + forward, Vector3.UP)
	_results[_phase_names[_phase - 1]] = _summarize()
	_reset_variant()
	await _run_phase()


func _reset_variant() -> void:
	if _phase >= 3:
		_sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
		_sun.shadow_enabled = true
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = CityBuilder.NIGHT_AMBIENT_SKY


func _summarize() -> Dictionary:
	var ds := _deltas.slice(24)  # warm-up
	var total := 0.0
	var mx := 0.0
	var stutters := 0
	var hitches := 0
	var sorted := ds.duplicate()
	sorted.sort()
	for d in ds:
		total += d
		mx = maxf(mx, d)
		if d > 1.0 / 45.0:
			stutters += 1
		if d > 1.0 / 30.0:
			hitches += 1
	var n := float(ds.size())
	return {
		"avg_ms": total / n * 1000.0,
		"p99_ms": sorted[int(n * 0.99)] * 1000.0,
		"max_ms": mx * 1000.0,
		"below_45fps": stutters,
		"below_30fps": hitches,
		"frames": ds.size(),
	}


func _report() -> void:
	print("=== bench results (8s flight each, 26m altitude weave) ===")
	for name in _phase_names:
		if _results.has(name):
			var r: Dictionary = _results[name]
			print("%-20s avg %5.1fms  p99 %5.1fms  max %5.1fms  <45fps:%3d  <30fps:%3d" % [
				name, r["avg_ms"], r["p99_ms"], r["max_ms"], r["below_45fps"], r["below_30fps"]])
