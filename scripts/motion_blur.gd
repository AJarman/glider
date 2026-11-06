extends CanvasLayer
## Full-screen speed blur, drawn under the HUD.

const SHADER := preload("res://scripts/motion_blur.gdshader")
## Blur length per m/s, as a fraction of the distance to the focus point.
const PER_SPEED := 0.0017
const MAX_AMOUNT := 0.1

var _rect: ColorRect
var _mat: ShaderMaterial
var _amount := 0.0


func _ready() -> void:
	layer = 0
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func update(cam: Camera3D, vel: Vector3, delta: float) -> void:
	var goal := minf(vel.length() * PER_SPEED, MAX_AMOUNT)
	_amount = lerpf(_amount, goal, 1.0 - exp(-10.0 * delta))
	_rect.visible = _amount > 0.002
	if not _rect.visible or vel.length() < 0.1:
		return
	# The point everything appears to stream away from when moving this way.
	var ahead := cam.global_position + vel.normalized() * 100.0
	if cam.is_position_behind(ahead):
		ahead = cam.global_position - vel.normalized() * 100.0
	var size := cam.get_viewport().get_visible_rect().size
	var focus := (cam.unproject_position(ahead) / size).clamp(Vector2(-0.5, -0.5), Vector2(1.5, 1.5))
	_mat.set_shader_parameter("focus", focus)
	_mat.set_shader_parameter("amount", _amount)
