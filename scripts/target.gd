extends StaticBody3D
## Floating target platform with concentric scoring rings.

const FRACS := [1.0, 0.76, 0.52, 0.3, 0.11]
## Cool to hot, so a points value looks the same on every target.
const SCORE_COLORS := {
	10: Color(0.15, 0.3, 0.85),
	20: Color(0.1, 0.55, 0.95),
	30: Color(0.1, 0.8, 0.85),
	50: Color(0.2, 0.8, 0.3),
	60: Color(0.55, 0.85, 0.2),
	80: Color(0.8, 0.9, 0.15),
	100: Color(1.0, 0.85, 0.1),
	120: Color(1.0, 0.68, 0.1),
	150: Color(1.0, 0.5, 0.1),
	200: Color(1.0, 0.32, 0.12),
	250: Color(0.95, 0.15, 0.15),
	300: Color(0.9, 0.15, 0.6),
	500: Color(0.6, 0.2, 0.95),
}
const RIM := 0.5

var radius := 15.0
var scores: Array = [10, 20, 30, 50, 100]


func setup(r: float, s: Array) -> void:
	radius = r
	scores = s


func _ready() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius + RIM
	shape.height = 1.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -0.6
	add_child(cs)

	var base := CylinderMesh.new()
	base.top_radius = radius + RIM
	base.bottom_radius = radius + RIM
	base.height = 1.2
	base.radial_segments = 64
	_mesh(base, Vector3(0, -0.6, 0), _mat(Color(0.95, 0.95, 0.97)))

	for i in FRACS.size():
		var ring := CylinderMesh.new()
		ring.top_radius = radius * FRACS[i]
		ring.bottom_radius = ring.top_radius
		ring.height = 0.04
		ring.radial_segments = 64
		_mesh(ring, Vector3(0, 0.01 * (i + 1), 0), _mat(SCORE_COLORS[scores[i]]))

		var inner: float = FRACS[i + 1] if i + 1 < FRACS.size() else 0.0
		var rmid: float = radius * (FRACS[i] + inner) * 0.5
		var lbl := Label3D.new()
		lbl.text = str(scores[i])
		lbl.font_size = 96
		lbl.outline_size = 16
		lbl.pixel_size = clampf(radius * 0.0012, 0.01, 0.022)
		lbl.position = Vector3(0, 0.1, rmid)
		lbl.rotation.x = -PI / 2
		lbl.shaded = false
		add_child(lbl)

	# Pontoon legs down into the sea.
	var depth := global_position.y + 2.0
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4
		var leg := CylinderMesh.new()
		leg.top_radius = maxf(radius * 0.08, 0.6)
		leg.bottom_radius = leg.top_radius * 1.3
		leg.height = depth
		_mesh(leg, Vector3(cos(a), 0, sin(a)) * radius * 0.6 + Vector3(0, -1.2 - depth * 0.5, 0), _mat(Color(0.5, 0.5, 0.55)))


func score_at(p: Vector3) -> int:
	var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
	for i in range(FRACS.size() - 1, -1, -1):
		if d <= radius * FRACS[i]:
			return scores[i]
	if d <= radius + RIM + 0.3:
		return scores[0]
	return 0


func _mesh(m: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m
