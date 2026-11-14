extends Node3D
class_name DaySwitch

## Rooftop day/night lever. Aim at it and pull the trigger: the lever flips
## and the connected CityBuilder swaps between day and night lighting.

signal toggled(is_night: bool)

@export var label_text := "DAY / NIGHT"

const SWITCH_LAYER := 8
const LEVER_DAY_ROT := -0.55
const LEVER_NIGHT_ROT := 0.55
const TWIST_SECONDS := 0.45
const DAY_GLOW := Color(1.0, 0.83, 0.35)
const NIGHT_GLOW := Color(0.4, 0.5, 1.0)

var is_night := false

var _pivot: Node3D
var _orb_mat: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	_build_pedestal()
	_build_lever()
	_build_label()
	_apply_look(true)


func activate() -> void:
	is_night = not is_night
	_apply_look(false)
	toggled.emit(is_night)


func _build_pedestal() -> void:
	var base := MeshInstance3D.new()
	base.name = "Pedestal"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.1, 1.0)
	base.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.15, 0.18)
	mat.metallic = 0.4
	mat.roughness = 0.4
	base.material_override = mat
	base.position = Vector3(0.0, 0.55, 0.0)
	add_child(base)

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = SWITCH_LAYER
	body.collision_mask = 0
	body.add_to_group("day_switch")
	body.set_meta("switch_node", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.2, 1.4)
	shape.shape = box
	shape.position = Vector3(0.0, 1.1, 0.0)
	body.add_child(shape)
	add_child(body)


func _build_lever() -> void:
	_pivot = Node3D.new()
	_pivot.name = "LeverPivot"
	_pivot.position = Vector3(0.0, 1.1, 0.0)
	add_child(_pivot)

	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.06
	arm_mesh.height = 0.75
	arm.mesh = arm_mesh
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.8, 0.55, 0.1)
	arm_mat.metallic = 0.5
	arm_mat.roughness = 0.35
	arm.material_override = arm_mat
	arm.position = Vector3(0.0, 0.36, 0.0)
	_pivot.add_child(arm)

	var orb := MeshInstance3D.new()
	orb.name = "Orb"
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.17
	orb_mesh.height = 0.34
	orb_mesh.radial_segments = 16
	orb_mesh.rings = 8
	orb.mesh = orb_mesh
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb.material_override = _orb_mat
	orb.position = Vector3(0.0, 0.78, 0.0)
	_pivot.add_child(orb)

	_light = OmniLight3D.new()
	_light.name = "GlowLight"
	_light.omni_range = 6.0
	_light.light_energy = 1.6
	_light.position = Vector3(0.0, 0.78, 0.0)
	_pivot.add_child(_light)


func _build_label() -> void:
	var label := Label3D.new()
	label.name = "Tag"
	label.text = label_text
	label.font_size = 48
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.93, 0.8)
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.05, 0.08, 0.9)
	label.position = Vector3(0.0, 2.1, 0.0)
	add_child(label)


func _apply_look(instant: bool) -> void:
	var lever_rot := LEVER_NIGHT_ROT if is_night else LEVER_DAY_ROT
	var glow := NIGHT_GLOW if is_night else DAY_GLOW
	if instant:
		_pivot.rotation.x = lever_rot
		_orb_mat.albedo_color = glow
		_light.light_color = glow
		return
	var tween := create_tween().set_parallel()
	tween.tween_property(_pivot, "rotation:x", lever_rot, TWIST_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_orb_mat, "albedo_color", glow, TWIST_SECONDS)
	tween.tween_property(_light, "light_color", glow, TWIST_SECONDS)
