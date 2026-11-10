extends Node3D
class_name PowerUp

## Rooftop powerup orb: spins above a roof, hides on collect, respawns
## at a random roof after a delay. Kind determines the buff and color.

const LOWGRAV := "lowgrav"
const TURBO := "turbo"
const RESPAWN_SECONDS := 25.0
const SPIN_SPEED := 1.8
const BOB_AMPLITUDE := 0.25
const BOB_SPEED := 2.0

const COLORS := {
	LOWGRAV: Color(0.3, 0.9, 1.0),
	TURBO: Color(1.0, 0.55, 0.2),
}

var kind := LOWGRAV
var collected := false

var _phase := 0.0
var _ring: MeshInstance3D
var _core: MeshInstance3D


func _ready() -> void:
	add_to_group("powerups")
	_phase = fmod(global_position.x + global_position.z, TAU)
	var color: Color = COLORS[kind]

	_core = MeshInstance3D.new()
	_core.name = "Core"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.26
	core_mesh.height = 0.52
	core_mesh.radial_segments = 16
	core_mesh.rings = 8
	_core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	_core.material_override = core_mat
	add_child(_core)

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.42
	ring_mesh.outer_radius = 0.5
	ring_mesh.rings = 24
	_ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	_ring.material_override = ring_mat
	add_child(_ring)


func _process(delta: float) -> void:
	if collected:
		return
	_phase += delta
	_ring.rotate(Vector3.UP, SPIN_SPEED * delta)
	_core.position = Vector3(0.0, sin(_phase * BOB_SPEED) * BOB_AMPLITUDE, 0.0)


func is_available() -> bool:
	return not collected


func collect() -> void:
	collected = true
	visible = false
	set_process(false)
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(_respawn)


func _respawn() -> void:
	var city := _find_city()
	if city != null:
		global_position = city.random_roof_spot()
	_phase = fmod(global_position.x + global_position.z, TAU)
	collected = false
	visible = true
	set_process(true)


func _find_city() -> Node:
	var node := get_parent()
	while node != null and not (node is CityBuilder):
		node = node.get_parent()
	return node
