extends XROrigin3D
class_name WebRig

## XR rig with Spider-Man-style web swinging.
## Hold a trigger to shoot a web at a building (layer 2); the cord tethers
## the head to the anchor as a pendulum constraint. Release the trigger to
## let go and keep your momentum. Left AX = jump, right AX = respawn,
## grip while attached = reel in.

signal web_attached(side: String, anchor: Vector3)
signal web_detached(side: String, velocity: Vector3)

const SWING_GRAVITY := 8.0
const FLOAT_GRAVITY := 3.0
const MAX_SPEED := 28.0
const AIR_STEER_ACCEL := 7.0
const AIR_TURN_SPEED := 90.0
const WALK_SPEED := 2.5
const SNAP_TURN_DEGREES := 30.0
const STICK_DEADZONE := 0.2
const GROUND_FRICTION := 4.0
const GROUND_SLIDE_MIN := 0.4
const JUMP_UP := 6.0
const JUMP_FORWARD := 3.5
const WEB_REACH := 60.0
const WEBBABLE_MASK := 2
const SURFACE_MASK := 3
const SURFACE_PROBE_UP := 50.0
const PLAYER_RADIUS := 0.45
const PUSH_PROBES := 8
const WEB_PULL_SPEED := 6.0
const WEB_PULL_ACCEL := 6.0
const GRIP_REEL_SPEED := 8.0
const MIN_ROPE := 1.2
const CORD_RADIUS := 0.012
const AIM_DOT_RADIUS := 0.062
const HAND_TILT_DEGREES := 72.0
const POWERUP_DURATION := 20.0
const POWERUP_COLLECT_RADIUS := 1.3
const LOWGRAV_GRAVITY_SCALE := 0.65
const TURBO_SPEED_SCALE := 1.6
const TURBO_REEL_SCALE := 1.5
const HUD_FADE_SECONDS := 12.0
const MIN_SWING_SECONDS := 0.3
const SWING_BASE_POINTS := 25.0
const SPEED_POINT_SCALE := 2.0
const CHAIN_MULT_STEP := 0.1
const CHAIN_BANK_BONUS := 50
const MASK_VIGNETTE_SIZE := 3.0
const MASK_VIGNETTE_DEPTH := 1.1
const MUSIC_TRACKS := [
	{"path": "res://assets/audio/freefloat.mp3", "title": "Free Float"},
	{"path": "res://assets/audio/freefloat-1.mp3", "title": "City Heartbeat"},
	{"path": "res://assets/audio/freefloat-2.mp3", "title": "Canyon of Glass"},
	{"path": "res://assets/audio/freefloat-3.mp3", "title": "We Swing"},
	{"path": "res://assets/audio/freefloat-4.mp3", "title": "The Long Way Home"},
	{"path": "res://assets/audio/freefloat-5.mp3", "title": "Watcher of the Skyline"},
]
const MUSIC_VOLUME_DB := -10.0
const MUSIC_FADE_SECONDS := 2.0
const MUSIC_TITLE_SECONDS := 5.0
const WIND_MIN_DB := -42.0
const WIND_MAX_DB := -5.0
const WIND_SMOOTH := 3.0
const THUD_MIN_IMPACT := 2.0
const CORD_SEGMENTS := 14

@export var spawn_point := Vector3(0.0, 30.0, 0.0)

@onready var camera: XRCamera3D = $XRCamera3D
@onready var left_controller: XRController3D = $LeftController
@onready var right_controller: XRController3D = $RightController

var locomotion_enabled := true

var _velocity := Vector3.ZERO
var _snap_ready := true
var _left_jump_was := false
var _right_respawn_was := false
var _hud_time := 0.0
var _hint: Label3D
var _status: Label3D
var _webs := {}
var _powerup_times := {}
var _aura: OmniLight3D
var _aura_color := Color(0.0, 0.0, 0.0)
var _land_fx: GPUParticles3D
var _buzzer: AudioStreamPlayer
var _music: AudioStreamPlayer
var _score := 0
var _chain := 0
var _best_chain := 0
var _chain_pulse := 0.0
var _score_label: Label3D
var _chain_label: Label3D
var _mask_mat: ShaderMaterial
var _playlist: Array = []
var _track_index := -1
var _now_playing_time := 0.0
var _now_playing: Label3D
var _thud: AudioStreamPlayer
var _wind: AudioStreamPlayer


func _ready() -> void:
	_setup_webs()
	_setup_hud()
	_setup_aura()
	_setup_landing_fx()
	_setup_buzzer()
	_setup_music()
	_setup_thud()
	_setup_wind()
	_setup_mask_hud()
	respawn()


func _process(delta: float) -> void:
	_update_web_inputs()
	_update_locomotion(delta)
	_update_powerups(delta)
	_update_cords()
	_update_wind(delta)
	_update_hud(delta)


func _setup_thud() -> void:
	_thud = AudioStreamPlayer.new()
	_thud.name = "LandingThud"
	_thud.stream = load("res://assets/audio/thud.wav")
	_thud.volume_db = -60.0
	add_child(_thud)


func _setup_wind() -> void:
	_wind = AudioStreamPlayer.new()
	_wind.name = "WindLoop"
	var stream := load("res://assets/audio/wind.wav") as AudioStreamWAV
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.data.size() / 2)
	_wind.stream = stream
	_wind.volume_db = WIND_MIN_DB
	add_child(_wind)
	if _wind.stream != null:
		_wind.play()


func _play_thud(impact: float) -> void:
	if _thud == null or _thud.stream == null or impact < THUD_MIN_IMPACT:
		return
	var strength := clampf(impact / MAX_SPEED, 0.0, 1.0)
	_thud.volume_db = linear_to_db(clampf(0.15 + strength * 0.85, 0.05, 1.0)) - 6.0
	_thud.pitch_scale = randf_range(0.9, 1.1)
	_thud.play()


func _update_wind(delta: float) -> void:
	if _wind == null or _wind.stream == null:
		return
	var speed := _velocity.length()
	var ratio := clampf(speed / _max_speed(), 0.0, 1.0)
	var target := lerpf(WIND_MIN_DB, WIND_MAX_DB, ratio)
	var decay := 1.0 - exp(-WIND_SMOOTH * delta)
	_wind.volume_db = lerpf(_wind.volume_db, target, decay)
	_wind.pitch_scale = lerpf(_wind.pitch_scale, 0.85 + 0.35 * ratio, decay)


func _duck_music() -> void:
	if _music == null or _music.stream == null:
		return
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB - 10.0, 0.15)
	tween.tween_interval(1.1)
	tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB, 1.2)


static func solve_rope(
	position: Vector3,
	velocity: Vector3,
	anchor: Vector3,
	rope_length: float
) -> Array:
	var offset := position - anchor
	var dist := offset.length()
	if dist <= rope_length or dist <= 0.0001:
		return [position, velocity]
	var normal := offset / dist
	var new_position := anchor + normal * rope_length
	var radial := velocity.dot(normal)
	var new_velocity := velocity
	if radial > 0.0:
		new_velocity = velocity - normal * radial
	return [new_position, new_velocity]


func _setup_webs() -> void:
	_webs["L"] = _make_web(left_controller, Color(1.0, 0.3, 0.24), true)
	_webs["R"] = _make_web(right_controller, Color(0.24, 0.62, 1.0), false)


func _make_web(hand: XRController3D, color: Color, is_left: bool) -> Dictionary:
	var hand_mesh := _make_hand_mesh(hand, color, is_left)
	var cord := MeshInstance3D.new()
	cord.name = "Cord_%s" % String(hand.name)
	cord.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	cord.material_override = mat
	cord.visible = false
	var parent := get_parent()
	if parent != null:
		parent.add_child.call_deferred(cord)
	var dot := MeshInstance3D.new()
	dot.name = "AimDot_%s" % String(hand.name)
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = AIM_DOT_RADIUS
	dot_mesh.height = AIM_DOT_RADIUS * 2.0
	dot_mesh.radial_segments = 12
	dot_mesh.rings = 6
	dot.mesh = dot_mesh
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	dot.material_override = dot_mat
	dot.visible = false
	if parent != null:
		parent.add_child.call_deferred(dot)
	return {
		"hand": hand,
		"web_origin": hand_mesh.get_node("WebOrigin") as Node3D,
		"attached": false,
		"anchor": Vector3.ZERO,
		"rope_length": 0.0,
		"cord": cord,
		"cord_color": color,
		"pressed_was": false,
		"aim_dot": dot,
		"aiming_was": false,
	}


func _make_hand_mesh(hand: XRController3D, color: Color, is_left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "HandMesh_%s" % String(hand.name)
	root.rotation.x = -deg_to_rad(HAND_TILT_DEGREES)
	var glove := StandardMaterial3D.new()
	glove.albedo_color = color
	glove.roughness = 0.6

	var palm := MeshInstance3D.new()
	palm.name = "Palm"
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.085, 0.11, 0.03)
	palm.mesh = palm_mesh
	palm.material_override = glove
	palm.position = Vector3(0.0, 0.01, -0.045)
	root.add_child(palm)

	for i in 4:
		var finger := MeshInstance3D.new()
		finger.name = "Finger%d" % i
		var finger_mesh := CapsuleMesh.new()
		finger_mesh.radius = 0.011
		finger_mesh.height = 0.1
		finger.mesh = finger_mesh
		finger.material_override = glove
		var x := -0.032 + float(i) * 0.021
		finger.position = Vector3(x, 0.1, -0.045)
		finger.rotation.z = -x * 2.2
		root.add_child(finger)

	var thumb := MeshInstance3D.new()
	thumb.name = "Thumb"
	var thumb_mesh := CapsuleMesh.new()
	thumb_mesh.radius = 0.012
	thumb_mesh.height = 0.075
	thumb.mesh = thumb_mesh
	thumb.material_override = glove
	var side := -1.0 if not is_left else 1.0
	thumb.position = Vector3(side * 0.05, -0.005, -0.02)
	thumb.rotation.z = side * -0.9
	thumb.rotation.x = -0.3
	root.add_child(thumb)

	var shooter := MeshInstance3D.new()
	shooter.name = "WebShooter"
	var shooter_mesh := BoxMesh.new()
	shooter_mesh.size = Vector3(0.028, 0.028, 0.006)
	shooter.mesh = shooter_mesh
	var shooter_mat := StandardMaterial3D.new()
	shooter_mat.albedo_color = Color(0.85, 0.85, 0.9)
	shooter_mat.metallic = 0.6
	shooter_mat.roughness = 0.3
	shooter.material_override = shooter_mat
	shooter.position = Vector3(0.0, 0.01, -0.064)
	root.add_child(shooter)

	var origin := Marker3D.new()
	origin.name = "WebOrigin"
	origin.position = Vector3(0.0, 0.01, -0.07)
	root.add_child(origin)

	hand.add_child(root)
	return root


func _setup_hud() -> void:
	_hint = Label3D.new()
	_hint.name = "Hint"
	_hint.position = Vector3(0.0, -0.35, -0.8)
	_hint.pixel_size = 0.001
	_hint.font_size = 22
	_hint.modulate = Color(0.75, 0.85, 1.0, 0.95)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.no_depth_test = true
	_hint.text = (
		"Hold TRIGGER at a building: shoot web\n"
		+ "Web pulls you to the anchor; GRIP reels faster\n"
		+ "Release TRIGGER: let go (keep momentum)\n"
		+ "No web out: floaty low-gravity air\n"
		+ "Sticks: walk / turn · Left AX: jump · Right AX: respawn"
	)
	camera.add_child(_hint)
	_hud_time = HUD_FADE_SECONDS

	_status = Label3D.new()
	_status.name = "Status"
	_status.position = Vector3(0.0, -0.62, -0.8)
	_status.pixel_size = 0.001
	_status.font_size = 26
	_status.modulate = Color(0.5, 0.95, 0.7)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.no_depth_test = true
	camera.add_child(_status)

	var caption := Label3D.new()
	caption.name = "ScoreCaption"
	caption.position = Vector3(0.0, 0.345, -0.9)
	caption.pixel_size = 0.001
	caption.font_size = 16
	caption.modulate = Color(0.98, 0.82, 0.84)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.no_depth_test = true
	caption.text = "SWING SCORE"
	camera.add_child(caption)

	_score_label = Label3D.new()
	_score_label.name = "Score"
	_score_label.position = Vector3(0.0, 0.255, -0.9)
	_score_label.pixel_size = 0.001
	_score_label.font_size = 54
	_score_label.modulate = Color(1.0, 0.97, 0.92)
	_score_label.outline_size = 10
	_score_label.outline_modulate = Color(0.42, 0.05, 0.09)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.no_depth_test = true
	_score_label.text = "0"
	camera.add_child(_score_label)

	_chain_label = Label3D.new()
	_chain_label.name = "SwingChain"
	_chain_label.position = Vector3(0.0, -0.28, -0.9)
	_chain_label.pixel_size = 0.001
	_chain_label.font_size = 40
	_chain_label.modulate = Color(1.0, 0.85, 0.3)
	_chain_label.outline_size = 8
	_chain_label.outline_modulate = Color(0.25, 0.12, 0.02)
	_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chain_label.no_depth_test = true
	_chain_label.visible = false
	camera.add_child(_chain_label)


func _setup_mask_hud() -> void:
	var mask := MeshInstance3D.new()
	mask.name = "MaskVignette"
	var quad := QuadMesh.new()
	quad.size = Vector2(MASK_VIGNETTE_SIZE, MASK_VIGNETTE_SIZE)
	mask.mesh = quad
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = load("res://assets/shaders/mask_vignette.gdshader")
	mask.material_override = _mask_mat
	mask.position = Vector3(0.0, 0.0, -MASK_VIGNETTE_DEPTH)
	camera.add_child(mask)


func _update_web_inputs() -> void:
	_update_web_input(_webs["L"], "L")
	_update_web_input(_webs["R"], "R")


func _update_web_input(web: Dictionary, side: String) -> void:
	var hand := web["hand"] as XRController3D
	var pressed := hand.is_button_pressed("trigger_click")
	if pressed and not bool(web["pressed_was"]):
		_try_attach(web, side)
	elif not pressed and bool(web["pressed_was"]):
		_detach(web, side)
	web["pressed_was"] = pressed
	if bool(web["attached"]):
		var delta := get_process_delta_time()
		var reel := _reel_base()
		if hand.get_float("grip") > 0.5 or hand.is_button_pressed("grip_click"):
			reel += GRIP_REEL_SPEED
		web["rope_length"] = maxf(float(web["rope_length"]) - reel * delta, MIN_ROPE)


func _try_attach(web: Dictionary, side: String) -> void:
	var hand := web["hand"] as XRController3D
	var palm := web["web_origin"] as Node3D
	var from := palm.global_position if palm != null else hand.global_position
	var dir := -hand.global_transform.basis.z
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * WEB_REACH, WEBBABLE_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_flash_hint("no attach point — aim at a building")
		return
	web["attached"] = true
	web["anchor"] = hit["position"] as Vector3
	web["attach_time"] = float(Time.get_ticks_msec()) * 0.001
	var head := camera.global_position
	web["rope_length"] = maxf(head.distance_to(hit["position"] as Vector3), MIN_ROPE)
	_pulse_haptic(hand, 0.8)
	web_attached.emit(side, hit["position"] as Vector3)


func _detach(web: Dictionary, side: String) -> void:
	if not bool(web["attached"]):
		return
	var held_for := float(Time.get_ticks_msec()) * 0.001 - float(web.get("attach_time", -1.0e9))
	web["attached"] = false
	var cord := web["cord"] as MeshInstance3D
	if cord != null:
		cord.visible = false
	var hand := web["hand"] as XRController3D
	_pulse_haptic(hand, 0.3)
	if held_for >= MIN_SWING_SECONDS:
		_register_swing(_velocity.length())
	web_detached.emit(side, _velocity)


func _register_swing(speed: float) -> void:
	_chain += 1
	_best_chain = maxi(_best_chain, _chain)
	var points := int(roundf((SWING_BASE_POINTS + speed * SPEED_POINT_SCALE) * _chain_multiplier()))
	_score += points
	_chain_pulse = 1.0
	if _chain_label != null:
		_chain_label.text = "×%d SWING CHAIN  ·  ×%.1f" % [_chain, _chain_multiplier()]
		_chain_label.visible = true


func _chain_multiplier() -> float:
	return 1.0 + CHAIN_MULT_STEP * float(_chain)


func _bank_chain() -> void:
	if _chain >= 3:
		var bonus := CHAIN_BANK_BONUS * _chain
		_score += bonus
		_flash_hint("SWING CHAIN ×%d banked  ·  +%d" % [_chain, bonus])
	_reset_chain()


func _reset_chain() -> void:
	_chain = 0
	_chain_pulse = 0.0
	if _chain_label != null:
		_chain_label.visible = false


func _update_locomotion(delta: float) -> void:
	if not locomotion_enabled:
		return
	var surface_y := _surface_y_below()
	var grounded := (
		surface_y >= 0.0
		and absf(global_position.y - surface_y) <= 0.02
		and _velocity.y <= 0.001
	)
	if grounded and not _any_attached():
		_apply_ground_friction(delta)
		_update_walk(delta)
		_update_snap_turn()
		_update_jump()
	else:
		_velocity.y -= (_swing_gravity()) * delta
		_apply_air_steer(delta)
		_velocity = _velocity.limit_length(_max_speed())
		var prev_y := global_position.y
		global_position += _velocity * delta
		_solve_web_constraints(delta)
		_push_out_of_buildings()
		_land_on_surface(prev_y)
		if global_position.y < 0.0:
			global_position.y = 0.0
			_velocity.y = 0.0
			_bank_chain()


func _surface_y_below() -> float:
	var feet := global_position
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP, feet - Vector3.UP, SURFACE_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return (hit["position"] as Vector3).y


func _land_on_surface(prev_y: float) -> void:
	if _velocity.y > 0.001:
		return
	var feet := global_position
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * SURFACE_PROBE_UP, feet - Vector3.UP, SURFACE_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var surface_y := (hit["position"] as Vector3).y
	if prev_y < surface_y - 0.05:
		return
	if feet.y >= surface_y:
		return
	var impact := -_velocity.y
	global_position.y = surface_y
	_velocity.y = 0.0
	_bank_chain()
	_play_thud(impact)
	if _land_fx != null:
		_land_fx.global_position = global_position + Vector3(0.0, 0.1, 0.0)
		_land_fx.restart()


func _apply_ground_friction(delta: float) -> void:
	var decay := maxf(0.0, 1.0 - GROUND_FRICTION * delta)
	var horizontal := Vector3(_velocity.x, 0.0, _velocity.z) * decay
	if horizontal.length() < GROUND_SLIDE_MIN:
		horizontal = Vector3.ZERO
	_velocity = horizontal


func _update_walk(delta: float) -> void:
	var move := _walk_axis(left_controller.get_vector2("primary"))
	move += _walk_axis(right_controller.get_vector2("primary"))
	move = clampf(move, -1.0, 1.0)
	if is_zero_approx(move):
		return
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	global_position += forward * move * WALK_SPEED * delta


func _walk_axis(stick: Vector2) -> float:
	stick = _rescaled(stick)
	if stick == Vector2.ZERO or absf(stick.y) <= absf(stick.x):
		return 0.0
	return stick.y


func _turn_axis(stick: Vector2) -> float:
	if stick.length() < STICK_DEADZONE:
		return 0.0
	if absf(stick.x) <= absf(stick.y):
		return 0.0
	return stick.x


func _update_snap_turn() -> void:
	var turn := _turn_axis(left_controller.get_vector2("primary"))
	turn += _turn_axis(right_controller.get_vector2("primary"))
	if not _snap_ready:
		if absf(turn) < STICK_DEADZONE:
			_snap_ready = true
		return
	if absf(turn) < STICK_DEADZONE:
		return
	_rotate_rig(-deg_to_rad(SNAP_TURN_DEGREES) * signf(turn))
	_snap_ready = false


func _apply_air_steer(delta: float) -> void:
	var steer := _rescaled(left_controller.get_vector2("primary"))
	steer += _rescaled(right_controller.get_vector2("primary"))
	steer = steer.limit_length(1.0)
	var turn := _turn_axis(left_controller.get_vector2("primary"))
	turn += _turn_axis(right_controller.get_vector2("primary"))
	if absf(turn) > STICK_DEADZONE:
		_rotate_rig(-deg_to_rad(AIR_TURN_SPEED) * signf(turn) * delta)
	if steer == Vector2.ZERO:
		return
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var right := Vector3(forward.z, 0.0, -forward.x)
	_velocity += (forward * steer.y + right * steer.x) * AIR_STEER_ACCEL * delta


func _rotate_rig(angle: float) -> void:
	var head := camera.global_position
	global_position = head + (global_position - head).rotated(Vector3.UP, angle)
	global_rotate(Vector3.UP, angle)


func _update_jump() -> void:
	var pressed := left_controller.is_button_pressed("ax_button")
	if pressed and not _left_jump_was:
		_velocity.y = JUMP_UP
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			_velocity += forward.normalized() * JUMP_FORWARD
		_pulse_haptic(left_controller, 0.4)
	_left_jump_was = pressed


func _swing_gravity() -> float:
	var base := SWING_GRAVITY if _any_attached() else FLOAT_GRAVITY
	if _powerup_times.has(PowerUp.LOWGRAV):
		base *= LOWGRAV_GRAVITY_SCALE
	return base


func _max_speed() -> float:
	return MAX_SPEED * (TURBO_SPEED_SCALE if _powerup_times.has(PowerUp.TURBO) else 1.0)


func _reel_base() -> float:
	return WEB_PULL_SPEED * (TURBO_REEL_SCALE if _powerup_times.has(PowerUp.TURBO) else 1.0)


func _setup_aura() -> void:
	_aura = OmniLight3D.new()
	_aura.name = "PowerUpAura"
	_aura.omni_range = 9.0
	_aura.light_energy = 1.3
	_aura.visible = false
	camera.add_child(_aura)


func _setup_landing_fx() -> void:
	_land_fx = GPUParticles3D.new()
	_land_fx.name = "LandFx"
	_land_fx.emitting = false
	_land_fx.one_shot = true
	_land_fx.amount = 10
	_land_fx.lifetime = 0.6
	_land_fx.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 65.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 0.8
	pm.color = Color(0.72, 0.74, 0.8, 0.6)
	_land_fx.process_material = pm
	var draw := SphereMesh.new()
	draw.radius = 0.07
	draw.height = 0.14
	draw.radial_segments = 8
	draw.rings = 4
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.8, 0.82, 0.86, 0.55)
	draw.material = draw_mat
	_land_fx.draw_pass_1 = draw
	add_child(_land_fx)


func _setup_buzzer() -> void:
	_buzzer = AudioStreamPlayer.new()
	_buzzer.name = "PowerUpBuzzer"
	_buzzer.stream = load("res://assets/audio/powerup_buzzer.ogg")
	_buzzer.volume_db = -6.0
	add_child(_buzzer)


func _setup_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "BackgroundMusic"
	_music.volume_db = MUSIC_VOLUME_DB
	add_child(_music)
	_music.finished.connect(_play_next_track)
	_playlist = range(MUSIC_TRACKS.size())
	_playlist.shuffle()
	_now_playing = Label3D.new()
	_now_playing.name = "NowPlaying"
	_now_playing.position = Vector3(0.0, 0.155, -0.9)
	_now_playing.pixel_size = 0.001
	_now_playing.font_size = 15
	_now_playing.modulate = Color(0.72, 0.8, 0.92, 0.9)
	_now_playing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_now_playing.no_depth_test = true
	_now_playing.text = ""
	camera.add_child(_now_playing)
	_play_track(0)


func _play_track(index: int) -> void:
	_track_index = index
	var info: Dictionary = MUSIC_TRACKS[int(_playlist[index])]
	var stream: AudioStreamMP3 = load(info["path"])
	if stream == null:
		_play_next_track()
		return
	stream.loop = false
	_music.stream = stream
	_music.volume_db = MUSIC_VOLUME_DB - 20.0
	_music.play()
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB, MUSIC_FADE_SECONDS)
	_now_playing_time = MUSIC_TITLE_SECONDS
	_update_now_playing_label()


func _play_next_track() -> void:
	if MUSIC_TRACKS.is_empty():
		return
	_play_track((_track_index + 1) % MUSIC_TRACKS.size())


func _update_now_playing_label() -> void:
	if _now_playing == null:
		return
	var info: Dictionary = MUSIC_TRACKS[int(_playlist[_track_index])]
	if _now_playing_time > 0.0:
		_now_playing.text = "♪ %d/%d · %s" % [_track_index + 1, MUSIC_TRACKS.size(), info["title"]]
	else:
		_now_playing.text = "♪ %d/%d" % [_track_index + 1, MUSIC_TRACKS.size()]


func _update_powerups(delta: float) -> void:
	for kind in _powerup_times.keys():
		_powerup_times[kind] = float(_powerup_times[kind]) - delta
		if float(_powerup_times[kind]) <= 0.0:
			_powerup_times.erase(kind)
	var cam := camera.global_position
	for node in get_tree().get_nodes_in_group("powerups"):
		var pickup := node as PowerUp
		if pickup == null or not pickup.is_available():
			continue
		if pickup.global_position.distance_to(cam) <= POWERUP_COLLECT_RADIUS:
			pickup.collect()
			_activate_powerup(pickup.kind)
	if _powerup_times.is_empty() or _aura == null:
		if _aura != null:
			_aura.visible = false
		return
	_aura.visible = true
	_aura.light_color = _aura_color


func _activate_powerup(kind: String) -> void:
	_powerup_times[kind] = POWERUP_DURATION
	var color: Color = PowerUp.COLORS[kind]
	_aura_color = color if _aura_color.is_equal_approx(Color(0.0, 0.0, 0.0)) else _aura_color.lerp(color, 0.5)
	var label := "Anti-Gravity" if kind == PowerUp.LOWGRAV else "Turbo Swing"
	_flash_hint("POWER UP — %s" % label)
	if _buzzer != null and _buzzer.stream != null:
		_buzzer.play()
		_duck_music()
	_pulse_haptic(right_controller, 0.6)


func _any_attached() -> bool:
	return bool(_webs["L"]["attached"]) or bool(_webs["R"]["attached"])


func _solve_web_constraints(delta: float) -> void:
	for side in ["L", "R"]:
		var web: Dictionary = _webs[side]
		if not bool(web["attached"]):
			continue
		var head := camera.global_position
		var to_anchor := (web["anchor"] as Vector3) - head
		var dist := to_anchor.length()
		if dist > 0.5:
			_velocity += (to_anchor / dist) * WEB_PULL_ACCEL * delta
		var solved := solve_rope(
			head,
			_velocity,
			web["anchor"] as Vector3,
			float(web["rope_length"])
		)
		global_position += (solved[0] as Vector3) - head
		_velocity = solved[1] as Vector3


func _push_out_of_buildings() -> void:
	var head := camera.global_position
	var space := get_viewport().get_world_3d().direct_space_state
	for i in PUSH_PROBES:
		var angle := TAU * float(i) / float(PUSH_PROBES)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(head, head + dir * PLAYER_RADIUS, WEBBABLE_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var penetration := PLAYER_RADIUS - head.distance_to(hit["position"] as Vector3)
		if penetration <= 0.0:
			continue
		global_position -= dir * penetration
		var into_wall := _velocity.dot(dir)
		if into_wall > 0.0:
			_velocity -= dir * into_wall


func _update_cords() -> void:
	_update_cord(_webs["L"])
	_update_cord(_webs["R"])
	_update_aim_dot(_webs["L"])
	_update_aim_dot(_webs["R"])


func _update_aim_dot(web: Dictionary) -> void:
	var dot := web["aim_dot"] as MeshInstance3D
	if dot == null:
		return
	var hand := web["hand"] as XRController3D
	if bool(web["attached"]):
		dot.visible = false
		web["aiming_was"] = false
		return
	var palm := web["web_origin"] as Node3D
	var from := palm.global_position if palm != null else hand.global_position
	var dir := -hand.global_transform.basis.z
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * WEB_REACH, WEBBABLE_MASK)
	var hit := space.intersect_ray(query)
	var aiming := not hit.is_empty()
	if aiming:
		var point := hit["position"] as Vector3
		dot.visible = true
		dot.global_position = point + (from - point).normalized() * 0.06
	else:
		dot.visible = false
	if aiming and not bool(web["aiming_was"]):
		_pulse_haptic(hand, 0.1)
	web["aiming_was"] = aiming


func _update_cord(web: Dictionary) -> void:
	var cord := web["cord"] as MeshInstance3D
	if cord == null:
		return
	if not bool(web["attached"]):
		cord.visible = false
		return
	var hand := web["hand"] as XRController3D
	var palm := web["web_origin"] as Node3D
	var anchor := web["anchor"] as Vector3
	var from := palm.global_position if palm != null else hand.global_position
	var length := from.distance_to(anchor)
	if length < 0.05:
		cord.visible = false
		return
	cord.visible = true
	var mat := cord.material_override as StandardMaterial3D
	var base := web["cord_color"] as Color
	if _grip_held():
		var pulse := float(Time.get_ticks_msec()) * 0.012
		mat.albedo_color = base * (1.0 + 0.3 * sin(pulse))
	else:
		mat.albedo_color = base
	var mesh := cord.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var slack := maxf(float(web["rope_length"]) - length, 0.0)
	var sag := clampf(slack * 0.55, 0.015, 1.4)
	var mid := (from + anchor) * 0.5 - Vector3.UP * sag
	var cam_pos := camera.global_position
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in CORD_SEGMENTS + 1:
		var t := float(i) / float(CORD_SEGMENTS)
		var p := from.lerp(mid, t).lerp(mid.lerp(anchor, t), t)
		var tangent := _bezier_tangent(from, mid, anchor, t, length)
		var view := (p - cam_pos).normalized()
		var side := tangent.cross(view)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized() * CORD_RADIUS
		mesh.surface_add_vertex(p + side)
		mesh.surface_add_vertex(p - side)
	mesh.surface_end()


func _bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, t: float, total: float) -> Vector3:
	var t0 := maxf(t - 0.02, 0.0)
	var t1 := minf(t + 0.02, 1.0)
	var a := p0.lerp(p1, t0).lerp(p1.lerp(p2, t0), t0)
	var b := p0.lerp(p1, t1).lerp(p1.lerp(p2, t1), t1)
	var tangent := b - a
	if tangent.length_squared() < 0.000001:
		tangent = p2 - p0
	return tangent / maxf(total, 0.001)


func respawn() -> void:
	for side in ["L", "R"]:
		_detach(_webs[side], side)
	_velocity = Vector3.ZERO
	global_position = spawn_point
	_reset_chain()


func _update_hud(delta: float) -> void:
	if _hud_time > 0.0:
		_hud_time -= delta
		if _hud_time <= 0.0:
			_hint.visible = false
	if _score_label != null:
		_score_label.text = _format_score(_score)
	if _chain_pulse > 0.0:
		_chain_pulse = maxf(0.0, _chain_pulse - delta * 2.5)
		var scale := 1.0 + 0.35 * _chain_pulse
		_chain_label.scale = Vector3(scale, scale, scale)
	if _now_playing_time > 0.0:
		_now_playing_time -= delta
		_update_now_playing_label()
	if _mask_mat != null:
		_mask_mat.set_shader_parameter("pulse", _chain_pulse)
	var sides := ""
	if bool(_webs["L"]["attached"]):
		sides += "L "
	if bool(_webs["R"]["attached"]):
		sides += "R "
	var buffs := ""
	for kind in [PowerUp.LOWGRAV, PowerUp.TURBO]:
		if _powerup_times.has(kind):
			var label := "LOW-G" if kind == PowerUp.LOWGRAV else "TURBO"
			buffs += "  ·  %s %ds" % [label, int(ceil(float(_powerup_times[kind])))]
	var speed := _velocity.length()
	if bool(_webs["L"]["attached"]) or bool(_webs["R"]["attached"]):
		var reel_note := "  ·  reel" if _grip_held() else ""
		_status.text = "web: %s  ·  %.1f m/s%s%s" % [sides.strip_edges(), speed, reel_note, buffs]
	elif speed > 1.0:
		_status.text = "%.1f m/s%s" % [speed, buffs]
	else:
		_status.text = buffs.strip_edges()


func _flash_hint(text: String) -> void:
	if _hint == null:
		return
	_hint.text = text
	_hint.visible = true
	_hud_time = 1.5


func _format_score(value: int) -> String:
	var digits := str(value)
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3, 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return digits + grouped


func _grip_held() -> bool:
	for side in ["L", "R"]:
		var web: Dictionary = _webs[side]
		if not bool(web["attached"]):
			continue
		var hand := web["hand"] as XRController3D
		if hand.get_float("grip") > 0.5 or hand.is_button_pressed("grip_click"):
			return true
	return false


func _pulse_haptic(hand: XRController3D, strength: float) -> void:
	var interface := XRServer.find_interface("OpenXR")
	if interface == null or not interface.is_initialized():
		return
	interface.trigger_haptic_pulse("haptic", hand.tracker, 0.0, strength, 0.08, 0.0)


func _rescaled(stick: Vector2) -> Vector2:
	var magnitude := stick.length()
	if magnitude < STICK_DEADZONE:
		return Vector2.ZERO
	if magnitude >= 1.0:
		return stick
	return stick * ((magnitude - STICK_DEADZONE) / ((1.0 - STICK_DEADZONE) * magnitude))
