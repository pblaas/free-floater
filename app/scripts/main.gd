extends Node3D

const BuildVersion = preload("res://scripts/build_version.gd")

@onready var city: CityBuilder = $City
@onready var rig: WebRig = $XROrigin3D


func _init() -> void:
	AppLog.install()


func _ready() -> void:
	var openxr := XRServer.find_interface("OpenXR")
	if openxr != null and openxr.is_initialized():
		get_viewport().use_xr = true
	print("Free Floater ", BuildVersion.TEXT)
	print("log file: ", AppLog.global_path())
	rig.spawn_point = city.spawn_point
	rig.respawn()
