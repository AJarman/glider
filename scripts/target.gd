extends AnimatableBody3D
## A floating target. Discs score by ring; the mover slides about, the splitter
## breaks in two and rejoins, the pyramid scores by tier and the pinprick is a
## tiny, far-off jackpot.

enum Kind { DISC, MOVER, SPLITTER, PYRAMID, PINPRICK }

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
	400: Color(0.8, 0.15, 0.8),
	500: Color(0.6, 0.2, 0.95),
	1000: Color(1.0, 0.95, 0.5),
}
const RIM := 0.5
const BASE_H := 1.2
## A body counts as on a surface from just under it to this far above it.
const ABOVE := 2.5
const BELOW := 0.5
const MOVER_SWING := 22.0
const MOVER_PERIOD := 11.0
const SPLIT_GAP := 6.0  # Each half's travel, so the full gap is twice this.
const SPLIT_PERIOD := 9.0
const TIER_H := 3.0

var kind := Kind.DISC
var radius := 15.0
var scores: Array = [10, 20, 30, 50, 100]
var title := "TARGET"
## Moving targets hold still while a landing is being scored.
var frozen := false
var _home := Vector3.ZERO
var _time := 0.0
var _halves: Array[AnimatableBody3D] = []


func setup(k: Kind, r: float, s: Array, t: String) -> void:
	kind = k
	radius = r
	scores = s
	title = t


func top_score() -> int:
	return scores.max()


func _ready() -> void:
	add_to_group("target")
	_home = position
	match kind:
		Kind.SPLITTER:
			_build_splitter()
		Kind.PYRAMID:
			_build_pyramid()
		_:
			_build_disc()
	if kind == Kind.PINPRICK:
		_build_beacon()


func _physics_process(delta: float) -> void:
	if frozen:
		set_meta("vel", Vector3.ZERO)
		for h in _halves:
			h.set_meta("vel", Vector3.ZERO)
		return
	_time += delta
	match kind:
		Kind.MOVER:
			var a := _time * TAU / MOVER_PERIOD
			_move_to(self, _home + Vector3(sin(a) * MOVER_SWING, 0, sin(a * 0.5) * MOVER_SWING * 0.35), delta)
		Kind.SPLITTER:
			var open := _split_amount(fmod(_time, SPLIT_PERIOD) / SPLIT_PERIOD)
			for h in _halves:
				_move_to(h, h.get_meta("dir") * SPLIT_GAP * open, delta)


## Moves a deck and notes its velocity (meta "vel"), so a body lying on it can
## tell resting from riding.
func _move_to(deck: Node3D, to: Vector3, delta: float) -> void:
	deck.set_meta("vel", (to - deck.position) / delta)
	deck.position = to


## 0 closed to 1 fully apart: shut, slide open, hang open, slide shut.
func _split_amount(phase: float) -> float:
	if phase < 0.3:
		return 0.0
	if phase < 0.45:
		return smoothstep(0.3, 0.45, phase)
	if phase < 0.75:
		return 1.0
	if phase < 0.9:
		return 1.0 - smoothstep(0.75, 0.9, phase)
	return 0.0


func score_at(p: Vector3) -> int:
	match kind:
		Kind.SPLITTER:
			var best := 0
			for h in _halves:
				var c := h.global_position
				var side := (p - c).dot(h.get_meta("dir"))
				if side > -0.4 and _on_surface(p, c.y):
					best = maxi(best, _ring_score(p, c))
			return best
		Kind.PYRAMID:
			var y := global_position.y
			for i in range(scores.size() - 1, -1, -1):
				var half := _tier_half(i) + 0.3
				var d := p - global_position
				if absf(d.x) <= half and absf(d.z) <= half and _on_surface(p, y + i * TIER_H):
					return scores[i]
			return 0
	if not _on_surface(p, global_position.y):
		return 0
	return _ring_score(p, global_position)


func _on_surface(p: Vector3, top: float) -> bool:
	return p.y > top - BELOW and p.y < top + ABOVE


func _ring_score(p: Vector3, centre: Vector3) -> int:
	var d := Vector2(p.x - centre.x, p.z - centre.z).length()
	for i in range(scores.size() - 1, -1, -1):
		if d <= radius * _frac(i):
			return scores[i]
	if d <= radius + RIM + 0.3:
		return scores[0]
	return 0


func _frac(i: int) -> float:
	return 1.0 if scores.size() == 1 else FRACS[i]


func _build_disc() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius + RIM
	shape.height = BASE_H
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = -BASE_H * 0.5
	add_child(cs)

	var base := CylinderMesh.new()
	base.top_radius = radius + RIM
	base.bottom_radius = radius + RIM
	base.height = BASE_H
	base.radial_segments = 64
	_mesh(self, base, Vector3(0, -BASE_H * 0.5, 0), _mat(Color(0.95, 0.95, 0.97)))

	for i in scores.size():
		var ring := CylinderMesh.new()
		ring.top_radius = radius * _frac(i)
		ring.bottom_radius = ring.top_radius
		ring.height = 0.04
		ring.radial_segments = 64
		_mesh(self, ring, Vector3(0, 0.01 * (i + 1), 0), _mat(SCORE_COLORS[scores[i]]))
		_ring_label(self, i, Vector3.BACK)

	if kind == Kind.MOVER:
		# A raft hull riding on the sea, so it reads as something that sails.
		var hull := CylinderMesh.new()
		hull.top_radius = radius * 0.75
		hull.bottom_radius = radius * 0.6
		hull.height = 1.6
		hull.radial_segments = 32
		_mesh(self, hull, Vector3(0, -position.y + 0.3, 0), _mat(Color(0.75, 0.3, 0.15)))
		for k in 3:
			var a := TAU * k / 3.0
			var leg := CylinderMesh.new()
			leg.top_radius = 0.6
			leg.bottom_radius = 0.8
			leg.height = position.y - 1.0
			_mesh(self, leg, Vector3(cos(a), 0, sin(a)) * radius * 0.45 + Vector3(0, -BASE_H - leg.height * 0.5 + 0.2, 0), _mat(Color(0.5, 0.5, 0.55)))
	else:
		_legs(self, radius * 0.6, 4)


## Two half discs, split across X. Each half's origin is the full disc's centre,
## so its rings are measured from where its own paint is centred.
func _build_splitter() -> void:
	for sx in [-1.0, 1.0]:
		var half := AnimatableBody3D.new()
		half.add_to_group("target")
		var dir := Vector3(sx, 0, 0)
		half.set_meta("dir", dir)
		add_child(half)
		_halves.append(half)
		var pts := PackedVector3Array()
		for y in [0.0, -BASE_H]:
			for k in 17:
				var a := -PI / 2 + PI * k / 16.0
				pts.append(Vector3(cos(a) * sx, 0, sin(a)) * (radius + RIM) + Vector3(0, y, 0))
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		half.add_child(cs)
		_mesh(half, _half_disc(radius + RIM, BASE_H, sx), Vector3.ZERO, _mat(Color(0.95, 0.95, 0.97), true))
		for i in scores.size():
			_mesh(half, _half_disc(radius * _frac(i), 0.04, sx), Vector3(0, 0.01 * (i + 1) + 0.04, 0), _mat(SCORE_COLORS[scores[i]], true))
			_ring_label(half, i, dir, true)
		# Each half floats on its own pair of legs.
		for z in [-1.0, 1.0]:
			_leg(half, Vector3(sx * radius * 0.45, 0, z * radius * 0.45), maxf(radius * 0.08, 0.6))


## A half cylinder of the given height whose top sits at y = 0, on the sx side.
func _half_disc(r: float, h: float, sx: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var arc := []
	for k in n + 1:
		var a := -PI / 2 + PI * k / n
		arc.append(Vector3(cos(a) * sx, 0, sin(a)) * r)
	var down := Vector3(0, -h, 0)
	for k in n:
		var a: Vector3 = arc[k]
		var b: Vector3 = arc[k + 1]
		# Top and bottom fans, winding so both face outward for either half.
		_tri(st, Vector3.ZERO, a, b, Vector3.UP, sx)
		_tri(st, down, b + down, a + down, Vector3.DOWN, sx)
		var out := ((a + b) * 0.5).normalized()
		_tri(st, a, a + down, b + down, out, sx)
		_tri(st, a, b + down, b, out, sx)
	var first: Vector3 = arc[0]
	var last: Vector3 = arc[n]
	var cut := Vector3(-sx, 0, 0)
	_tri(st, first, last, last + down, cut, sx)
	_tri(st, first, last + down, first + down, cut, sx)
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, sx: float) -> void:
	var pts := [a, c, b] if sx < 0.0 else [a, b, c]
	for p in pts:
		st.set_normal(nrm)
		st.add_vertex(p)


## Stepped and square: the higher the tier, the smaller and the richer.
func _build_pyramid() -> void:
	for i in scores.size():
		var half := _tier_half(i)
		var h := BASE_H + i * TIER_H
		var size := Vector3(half * 2.0, h, half * 2.0)
		var centre := Vector3(0, i * TIER_H - h * 0.5, 0)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = centre
		add_child(cs)
		var box := BoxMesh.new()
		box.size = size
		var col: Color = SCORE_COLORS[scores[i]]
		_mesh(self, box, centre, _mat(col.lerp(Color.WHITE, 0.15)))
		var lbl := _label(str(scores[i]), clampf(half * 0.004, 0.012, 0.03))
		var inner := _tier_half(i + 1) if i + 1 < scores.size() else 0.0
		lbl.position = Vector3(0, i * TIER_H + 0.1, (half + inner) * 0.5)
		add_child(lbl)
	_legs(self, _tier_half(0) * 0.6, 4)


func _tier_half(i: int) -> float:
	return radius * lerpf(1.0, 0.22, float(i) / maxf(scores.size() - 1, 1))


## A pillar of light so the far-off jackpot can be found from the ramp.
func _build_beacon() -> void:
	var beam := CylinderMesh.new()
	beam.top_radius = radius * 0.6
	beam.bottom_radius = radius * 0.9
	beam.height = 120.0
	beam.cap_top = false
	beam.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.92, 0.4, 0.18)
	var mi := MeshInstance3D.new()
	mi.mesh = beam
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 62.0
	add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.9, 0.4)
	glow.light_energy = 4.0
	glow.omni_range = 18.0
	glow.position.y = 3.0
	add_child(glow)


func _legs(parent: Node3D, spread: float, count: int) -> void:
	for k in count:
		var a := TAU * k / count + PI / 4
		_leg(parent, Vector3(cos(a), 0, sin(a)) * spread, maxf(radius * 0.08, 0.6))


## A pontoon leg from under the deck down into the sea.
func _leg(parent: Node3D, at: Vector3, r: float) -> void:
	var depth := position.y + 2.0
	var leg := CylinderMesh.new()
	leg.top_radius = r
	leg.bottom_radius = r * 1.3
	leg.height = depth
	_mesh(parent, leg, at + Vector3(0, -BASE_H - depth * 0.5, 0), _mat(Color(0.5, 0.5, 0.55)))


## On a half disc the labels run down the cut edge, each set to its own side.
func _ring_label(parent: Node3D, i: int, dir: Vector3, half := false) -> void:
	var inner: float = _frac(i + 1) if i + 1 < scores.size() else 0.0
	var rmid: float = radius * (_frac(i) + inner) * 0.5
	var px := radius * 0.006 if scores.size() == 1 else clampf(radius * 0.0012, 0.01, 0.022)
	var lbl := _label(str(scores[i]), px)
	lbl.position = Vector3(0, 0.1, 0) + dir * rmid
	if half:
		lbl.position = Vector3(dir.x * 0.6, 0.1, rmid)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if dir.x > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(lbl)


func _label(text: String, px: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.outline_size = 16
	lbl.pixel_size = px
	lbl.rotation.x = -PI / 2
	lbl.shaded = false
	return lbl


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _mat(c: Color, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.6
	return m
