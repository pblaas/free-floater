extends Node

const OUT_PATH := "user://captures/city_shot.png"

var _frame := 0
var _scene: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_scene)
	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.far = 400.0
	add_child(cam)
	var city = _scene.get_node("City")
	var spawn: Vector3 = city.spawn_point
	cam.global_position = spawn + Vector3(0.0, 60.0, 100.0)
	cam.look_at(spawn + Vector3(0.0, 0.0, -20.0), Vector3.UP)
	cam.make_current()
	print("capture ready")


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		_snap(OUT_PATH)
	elif _frame >= 35:
		get_tree().quit(0)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("capture failed for ", path)
		return
	img.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path), " ", img.get_size())
