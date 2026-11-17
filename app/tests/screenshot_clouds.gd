extends Node

var _frame := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://captures")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(scene)
	var city = scene.get_node("City")
	var clouds := city.get_node("Clouds")
	var mat: StandardMaterial3D = (clouds.get_child(0) as MeshInstance3D).material_override
	var tex: Image = (mat.albedo_texture as ImageTexture).get_image()
	tex.save_png("user://captures/cloud_tex.png")
	print("texture dumped ", tex.get_size())
	var cam := Camera3D.new()
	cam.far = 800.0
	add_child(cam)
	var spawn: Vector3 = city.spawn_point
	cam.global_position = spawn + Vector3(0.0, 70.0, 260.0)
	cam.look_at(spawn + Vector3(0.0, 170.0, -40.0), Vector3.UP)
	cam.make_current()

func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://captures/clouds_day.png")
		print("saved ", ProjectSettings.globalize_path("user://captures/clouds_day.png"))
	elif _frame >= 35:
		get_tree().quit(0)
