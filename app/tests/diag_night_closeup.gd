extends Node

var _frame := 0
var _scene: Node
var _mat: StandardMaterial3D
var _base_emission := false


func _ready() -> void:
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_scene)
	var city = _scene.get_node("City")
	city.set_night(true)
	for child in city.get_node("Buildings").get_children():
		var mi := child as MeshInstance3D
		if mi != null and String(mi.name).begins_with("Facade_"):
			_mat = mi.material_override
			break
	var cam := Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	var spawn: Vector3 = city.spawn_point
	# close-up on a facade across the street
	var target: Vector3 = spawn + Vector3(17.0, -6.0, 0.0)
	cam.global_position = spawn + Vector3(8.0, 2.0, 6.0)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	print("diag ready, mat found: ", _mat != null)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		_snap("user://captures/night_closeup_a.png")
	elif _frame == 32:
		_base_emission = _mat.emission_enabled
		_mat.emission_enabled = false
	elif _frame == 60:
		_snap("user://captures/night_closeup_b.png")
	elif _frame == 62:
		_mat.emission_enabled = _base_emission
	elif _frame >= 66:
		get_tree().quit(0)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
